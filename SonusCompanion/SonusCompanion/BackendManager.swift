import Foundation
import Darwin

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
        await preparePortForSpawn(port: port)
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

        // Tear down any prior process, reap orphans left by a previous app
        // session (e.g. after an in-app update replaced the bundle without
        // killing its child backend), and wait for the port to actually free
        // before spawning. Without this, the new uvicorn can race an old
        // process still holding port 8000 -> [Errno 48] address already in use
        // -> exit 1, surfaced as "Backend exited unexpectedly" right after a
        // switch or update.
        await preparePortForSpawn(port: port)

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

    /// Stop the spawned backend and block until the process has actually exited
    /// (and the OS has had a chance to release port 8000). Escalates to SIGKILL
    /// if a graceful SIGTERM does not land within ``timeout`` seconds.
    ///
    /// This is the key fix for the "switch to Qwen -> backend exits with code 1"
    /// crash: previously we fired ``terminate()`` and immediately spawned a new
    /// uvicorn, which raced the old one for the port and failed with
    /// ``[Errno 48] address already in use``.
    private func stopAndAwaitExit(timeout: TimeInterval = 6) async {
        guard let proc = process else { return }
        detachPipes(proc)
        if proc.isRunning {
            proc.terminate()
            AppLogger.log("embedded backend terminate pid=\(proc.processIdentifier)")
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let pid = proc.processIdentifier
            DispatchQueue.global(qos: .userInitiated).async {
                // Blocks until the process exits; bounded by the SIGKILL below.
                proc.waitUntilExit()
                cont.resume()
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                if proc.isRunning {
                    AppLogger.log("embedded backend SIGKILL pid=\(pid) (did not exit in \(timeout)s)")
                    kill(pid, SIGKILL)
                }
                // waitUntilExit above will still resume the continuation.
            }
        }

        self.process = nil
        self.spawnedByApp = false
    }

    /// Make port ``port`` safe to spawn a new backend on: stop our tracked
    /// process, reap any orphaned sonus backend still listening (left behind by
    /// a previous app session that was killed/replaced before tearing down its
    /// child), then wait for the port to actually be free.
    private func preparePortForSpawn(port: Int) async {
        await stopAndAwaitExit()
        await reapOrphanedBackends(port: port)
        await waitForPortFree(port: port)
    }

    /// Kill sonus backend processes still listening on ``port`` that we are not
    /// tracking (orphans). Filtered by command line so we never clobber an
    /// unrelated server the user happens to run on the same port.
    private func reapOrphanedBackends(port: Int) async {
        let pids = sonusBackendPidsOnPort(port: port)
        guard !pids.isEmpty else { return }
        AppLogger.log("embedded backend reaping orphan pids=\(pids.map(String.init)) on port \(port)")
        for pid in pids {
            kill(pid, SIGTERM)
        }
        // Give them a moment to exit gracefully, then SIGKILL stragglers.
        try? await Task.sleep(nanoseconds: 800_000_000)
        for pid in pids {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    private func sonusBackendPidsOnPort(port: Int) -> [pid_t] {
        // `lsof -ti tcp:PORT -sTCP:LISTEN` prints PIDs of listeners, one per line.
        let raw = Self.runCapture(launchPath: "/usr/sbin/lsof",
                                  arguments: ["-ti", "tcp:\(port)", "-sTCP:LISTEN"]) ?? ""
        let candidates = raw.split(whereSeparator: { $0.isWhitespace }).compactMap { pid_t($0) }
        // Only kill processes whose command looks like a sonus backend.
        return candidates.filter {
            Self.processCommandContains(pid: $0, needle: "sonus.app:app")
                || Self.processCommandContains(pid: $0, needle: "sonus-runtime")
        }
    }

    private static func processCommandContains(pid: pid_t, needle: String) -> Bool {
        let cmd = runCapture(launchPath: "/bin/ps", arguments: ["-p", "\(pid)", "-o", "command="]) ?? ""
        return cmd.contains(needle)
    }

    private static func runCapture(launchPath: String, arguments: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Poll until nothing is listening on ``port`` (connection refused) or the
    /// timeout elapses. Catches the tail of the old process releasing the port.
    private func waitForPortFree(port: Int, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return }
            if !Self.isPortOpen(port: port) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        AppLogger.log("embedded backend port \(port) still in use after \(timeout)s; spawning anyway")
    }

    private static func isPortOpen(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 {
            return true
        }
        return false
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
