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
    private var recentBackendOutput: String = ""

    var onStateChange: ((BackendState) -> Void)?

    func ensureRunning(
        useExternalServer: Bool,
        externalServerURL: String,
        port: Int,
        customModelsPath: String?,
        activeEngine: String
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

        if let launchError = EmbeddedBackendConfig.runtimeLaunchError() {
            updateState(.failed(launchError))
            return EmbeddedBackendConfig.embeddedBaseURL(port: port)
        }

        startupTask?.cancel()
        startupTask = Task {
            await self.runEmbeddedStartup(port: port, customModelsPath: customModelsPath, activeEngine: activeEngine)
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

    func restart(port: Int, customModelsPath: String?, activeEngine: String) async {
        stopSpawnedProcess()
        await runEmbeddedStartup(port: port, customModelsPath: customModelsPath, activeEngine: activeEngine)
    }

    private func runEmbeddedStartup(port: Int, customModelsPath: String?, activeEngine: String) async {
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
            try spawnBackend(port: port, modelsDirectory: modelsDirectory, activeEngine: activeEngine)
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
            let detail = recentBackendOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            stopSpawnedProcess()
            if !detail.isEmpty {
                AppLogger.log("embedded backend not ready, output: \(detail)")
            }
            if detail.isEmpty {
                updateState(.failed("Embedded backend did not become ready on port \(port)."))
            } else {
                updateState(.failed("Embedded backend did not become ready on port \(port): \(detail)"))
            }
        }
    }

    private func spawnBackend(port: Int, modelsDirectory: URL, activeEngine: String) throws {
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
        // Embedded venv is self-contained: drop host-side Python overrides that
        // can make the bundled interpreter look outside the bundle and fail to
        // import sonus (e.g. PYTHONPATH pointing at a dev checkout).
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        environment.removeValue(forKey: "PYTHONDONTWRITEBYTECODE")
        environment["PYTHONUNBUFFERED"] = "1"
        if QwenAddonManager.isInstalled() {
            environment["PYTHONPATH"] = QwenAddonManager.sitePackagesURL.path
        }
        environment["SONUS_HOST"] = "127.0.0.1"
        environment["SONUS_PORT"] = String(port)
        environment["SONUS_MODELS_DIR"] = modelsDirectory.path
        environment["SONUS_ENGINE"] = activeEngine
        environment["SONUS_CACHE_DIR"] = EmbeddedBackendConfig.cacheDirectory.path
        environment["SONUS_LOG_LEVEL"] = "info"

        if let runtime = EmbeddedBackendConfig.embeddedRuntimeURL {
            let binPath = runtime.appendingPathComponent("bin").path
            environment["PATH"] = binPath + ":" + (environment["PATH"] ?? "")
            environment["SONUS_RUNTIME_DIR"] = runtime.path
        }

        process.environment = environment
        process.currentDirectoryURL = modelsDirectory.deletingLastPathComponent()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream subprocess output into the app log so failures are diagnosable
        // even when the process exits before the health-check timeout fires.
        startStreamingPipe(stdoutPipe, prefix: "backend stdout")
        startStreamingPipe(stderrPipe, prefix: "backend stderr")

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                if self.spawnedByApp, proc.terminationStatus != 0, self.state == .running || self.state == .starting {
                    let tail = self.recentBackendOutput
                    if tail.isEmpty {
                        self.updateState(.failed("Backend exited unexpectedly (code \(proc.terminationStatus))."))
                    } else {
                        self.updateState(.failed("Backend exited unexpectedly (code \(proc.terminationStatus)): \(tail)"))
                    }
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
        recentBackendOutput = ""
        AppLogger.log("embedded backend spawned pid=\(process.processIdentifier) port=\(port) python=\(python.path)")
    }

    private static let outputByteCap = 8_000

    private func startStreamingPipe(_ pipe: Pipe, prefix: String) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            Task { @MainActor in
                self?.appendBackendOutput(text, prefix: prefix)
            }
        }
    }

    private func appendBackendOutput(_ text: String, prefix: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AppLogger.log("\(prefix): \(trimmed)")
        let combined = recentBackendOutput.isEmpty ? trimmed : (recentBackendOutput + "\n" + trimmed)
        if combined.count > Self.outputByteCap {
            recentBackendOutput = String(combined.suffix(Self.outputByteCap))
        } else {
            recentBackendOutput = combined
        }
    }

    private func stopSpawnedProcess() {
        guard let process else { return }
        detachPipes(process)
        if process.isRunning {
            process.terminate()
            AppLogger.log("embedded backend terminate pid=\(process.processIdentifier)")
        }
        self.process = nil
        spawnedByApp = false
    }

    private func detachPipes(_ process: Process) {
        if let pipe = process.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if let pipe = process.standardError as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
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
