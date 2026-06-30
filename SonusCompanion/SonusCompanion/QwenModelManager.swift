import Foundation

enum QwenModelManager {
    static let modelSubdirectory = "qwen3-tts"
    static let huggingFaceRepo = "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"

    static func modelDirectory(in modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(modelSubdirectory, isDirectory: true)
    }

    static func isReady(in modelsRoot: URL, fileManager: FileManager = .default) -> Bool {
        let directory = modelDirectory(in: modelsRoot)
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            return false
        }
        let weightNames = ["model.safetensors", "pytorch_model.bin", "model.safetensors.index.json"]
        return weightNames.contains { name in
            fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }

    static func downloadModel(
        into modelsRoot: URL,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws {
        guard QwenAddonManager.isInstalled() else {
            throw QwenModelError.addonRequired
        }
        guard let python = EmbeddedBackendConfig.embeddedPythonExecutable else {
            throw QwenModelError.runtimeMissing
        }

        let target = modelDirectory(in: modelsRoot)
        if isReady(in: modelsRoot) {
            onProgress(1.0, "Qwen3 model ready")
            return
        }

        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        onProgress(0.05, "Downloading Qwen3-TTS model (~1.7 GB)…")

        let process = Process()
        process.executableURL = python
        process.arguments = ["-c", downloadScript]
        process.standardOutput = Pipe()
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONPATH"] = QwenAddonManager.sitePackagesURL.path
        environment["TARGET"] = target.path
        environment["REPO"] = huggingFaceRepo
        if let runtime = EmbeddedBackendConfig.embeddedRuntimeURL {
            let binPath = runtime.appendingPathComponent("bin").path
            environment["PATH"] = binPath + ":" + (environment["PATH"] ?? "")
            environment["SONUS_RUNTIME_DIR"] = runtime.path
        }
        process.environment = environment
        process.currentDirectoryURL = modelsRoot.deletingLastPathComponent()

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            onProgress(0.5, text)
        }

        try process.run()
        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0, isReady(in: modelsRoot) else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let stderr, !stderr.isEmpty {
                throw QwenModelError.downloadFailed(stderr)
            }
            throw QwenModelError.downloadFailed("Qwen3 model download failed.")
        }

        onProgress(1.0, "Qwen3 model ready")
    }

    private static let downloadScript = """
    import os
    import sys
    from huggingface_hub import snapshot_download

    target = os.environ["TARGET"]
    repo = os.environ["REPO"]
    print(f"Downloading {repo} into {target} ...", file=sys.stderr, flush=True)
    snapshot_download(repo_id=repo, local_dir=target)
    print("Done", file=sys.stderr, flush=True)
    """
}

enum QwenModelError: LocalizedError {
    case addonRequired
    case runtimeMissing
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .addonRequired:
            return "Install the Qwen runtime before downloading the Qwen3 model."
        case .runtimeMissing:
            return "Embedded Python runtime was not found in the app bundle."
        case .downloadFailed(let reason):
            return reason
        }
    }
}
