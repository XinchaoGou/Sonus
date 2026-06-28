import Foundation

enum BackendState: Equatable {
    case idle
    case checkingModels
    case downloadingModels(progress: Double, message: String)
    case starting
    case running
    case external
    case failed(String)

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .checkingModels:
            return "Checking models…"
        case .downloadingModels(let progress, _):
            return "Downloading models \(Int(progress * 100))%"
        case .starting:
            return "Starting backend…"
        case .running:
            return "Running"
        case .external:
            return "External server"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    var isOperational: Bool {
        switch self {
        case .running, .external:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class BackendManager {
    private(set) var state: BackendState = .idle
    private var process: Process?
    private var spawnedByApp = false
    private var startupTask: Task<Void, Never>?

    var onStateChange: ((BackendState) -> Void)?

    func ensureRunning(
        useExternalServer: Bool,
        externalServerURL: String,
        port: Int,
        customModelsPath: String?
    ) async -> String {
        if useExternalServer {
            stopSpawnedProcess()
            updateState(.external)
            return externalServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard EmbeddedBackendConfig.canUseEmbeddedBackend else {
            let message = EmbeddedBackendConfig.runtimeDiagnosticMessage
            updateState(.failed(message))
            return EmbeddedBackendConfig.embeddedBaseURL(port: port)
        }

        startupTask?.cancel()
        startupTask = Task {
            await self.runEmbeddedStartup(port: port, customModelsPath: customModelsPath)
        }
        await startupTask?.value
        return EmbeddedBackendConfig.embeddedBaseURL(port: port)
    }

    func shutdown() {
        startupTask?.cancel()
        startupTask = nil
        stopSpawnedProcess()
        updateState(.idle)
    }

    func restart(port: Int, customModelsPath: String?) async {
        stopSpawnedProcess()
        await runEmbeddedStartup(port: port, customModelsPath: customModelsPath)
    }

    private func runEmbeddedStartup(port: Int, customModelsPath: String?) async {
        updateState(.checkingModels)

        let targetDirectory = ModelManager.targetModelsDirectory(customPath: customModelsPath)
        if ModelManager.resolveModelsDirectory(customPath: customModelsPath) == nil {
            do {
                try await ModelManager.downloadMissingModels(into: targetDirectory) { [weak self] progress, message in
                    Task { @MainActor in
                        self?.updateState(.downloadingModels(progress: progress, message: message))
                    }
                }
            } catch {
                if Task.isCancelled { return }
                updateState(.failed(error.localizedDescription))
                return
            }
        }

        if Task.isCancelled { return }

        let modelsDirectory = ModelManager.resolveModelsDirectory(customPath: customModelsPath) ?? targetDirectory
        guard ModelManager.directoryIsReady(modelsDirectory) else {
            updateState(.failed("Model files are incomplete."))
            return
        }

        updateState(.starting)

        do {
            try spawnBackend(port: port, modelsDirectory: modelsDirectory)
        } catch {
            updateState(.failed(error.localizedDescription))
            return
        }

        if Task.isCancelled {
            stopSpawnedProcess()
            return
        }

        let baseURL = EmbeddedBackendConfig.embeddedBaseURL(port: port)
        let ready = await waitForHealthyServer(baseURL: baseURL, timeoutSeconds: 45)
        if Task.isCancelled {
            stopSpawnedProcess()
            return
        }

        if ready {
            updateState(.running)
        } else {
            stopSpawnedProcess()
            updateState(.failed("Embedded backend did not become ready on port \(port)."))
        }
    }

    private func spawnBackend(port: Int, modelsDirectory: URL) throws {
        stopSpawnedProcess()

        guard let python = EmbeddedBackendConfig.embeddedPythonExecutable else {
            throw BackendManagerError.runtimeMissing
        }

        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-m", "uvicorn",
            "sonus.app:app",
            "--host", "127.0.0.1",
            "--port", String(port),
            "--log-level", "info",
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["SONUS_HOST"] = "127.0.0.1"
        environment["SONUS_PORT"] = String(port)
        environment["SONUS_MODELS_DIR"] = modelsDirectory.path
        environment["SONUS_CACHE_DIR"] = EmbeddedBackendConfig.cacheDirectory.path
        environment["SONUS_LOG_LEVEL"] = "info"

        if let runtime = EmbeddedBackendConfig.embeddedRuntimeURL {
            let binPath = runtime.appendingPathComponent("bin").path
            environment["PATH"] = binPath + ":" + (environment["PATH"] ?? "")
        }

        process.environment = environment
        process.currentDirectoryURL = modelsDirectory.deletingLastPathComponent()

        process.standardOutput = Pipe()
        process.standardError = Pipe()

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                if self.spawnedByApp, proc.terminationStatus != 0, self.state == .running || self.state == .starting {
                    self.updateState(.failed("Backend exited unexpectedly (code \(proc.terminationStatus))."))
                }
                if self.process === proc {
                    self.process = nil
                    self.spawnedByApp = false
                }
            }
        }

        try process.run()
        self.process = process
        spawnedByApp = true
        AppLogger.log("embedded backend spawned pid=\(process.processIdentifier) port=\(port)")
    }

    private func stopSpawnedProcess() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            AppLogger.log("embedded backend terminate pid=\(process.processIdentifier)")
        }
        self.process = nil
        spawnedByApp = false
    }

    private func waitForHealthyServer(baseURL: String, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await backendIsHealthy(baseURL: baseURL) {
                return true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    private func backendIsHealthy(baseURL: String) async -> Bool {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let decoded = try JSONDecoder().decode(HealthProbeResponse.self, from: data)
            return decoded.status == "ok" && decoded.modelsReady == true
        } catch {
            return false
        }
    }

    private func updateState(_ newState: BackendState) {
        state = newState
        onStateChange?(newState)
        AppLogger.log("backend state: \(newState.displayName)")
    }
}

private struct HealthProbeResponse: Decodable {
    let status: String
    let modelsReady: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case modelsReady = "models_ready"
    }
}

enum BackendManagerError: LocalizedError {
    case runtimeMissing

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return "Embedded Python runtime was not found in the app bundle."
        }
    }
}
