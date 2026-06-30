import Foundation

enum QwenAddonManager {
    static let assetFileName = "Sonus-qwen-addon.zip"
    private static let addonRootName = "qwen-addon"

    static var addonRootURL: URL {
        EmbeddedBackendConfig.applicationSupportRoot
            .appendingPathComponent(addonRootName, isDirectory: true)
    }

    static var sitePackagesURL: URL {
        addonRootURL.appendingPathComponent("site-packages", isDirectory: true)
    }

    private static var manifestURL: URL {
        addonRootURL.appendingPathComponent("manifest.json")
    }

    static func isInstalled(fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return false }
        let qwenPackage = sitePackagesURL.appendingPathComponent("qwen_tts", isDirectory: true)
        guard fileManager.fileExists(atPath: qwenPackage.path) else { return false }
        return verifyImport()
    }

    static func verifyImport() -> Bool {
        guard let python = EmbeddedBackendConfig.embeddedPythonExecutable else { return false }

        let process = Process()
        process.executableURL = python
        process.arguments = ["-c", "import qwen_tts; print('ok')"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONPATH"] = sitePackagesURL.path
        if let runtime = EmbeddedBackendConfig.embeddedRuntimeURL {
            let binPath = runtime.appendingPathComponent("bin").path
            environment["PATH"] = binPath + ":" + (environment["PATH"] ?? "")
            environment["SONUS_RUNTIME_DIR"] = runtime.path
        }
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: "/")

        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func downloadAndInstall(
        onProgress: @Sendable @escaping (Double, String) -> Void,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws {
        guard let version = AppVersion.current else {
            throw QwenAddonError.missingAppVersion
        }

        let tag = "v\(version.displayString)"
        let downloadURL = try await GitHubReleaseClient.fetchAssetDownloadURL(
            assetName: assetFileName,
            tag: tag,
            session: session
        )

        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("sonus-qwen-addon-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workDir)
        }

        let zipURL = workDir.appendingPathComponent(assetFileName)
        let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)

        onProgress(0.01, "Downloading Qwen runtime (~250 MB)…")
        try await downloadFile(
            from: downloadURL,
            to: zipURL,
            session: session,
            fileManager: fileManager,
            onProgress: { fileProgress, bytesDownloaded in
                let overall = 0.01 + (fileProgress * 0.84)
                let megabytes = Double(bytesDownloaded) / 1_000_000.0
                let message: String
                if fileProgress > 0 {
                    message = String(
                        format: "Downloading Qwen runtime (%d%% · %.1f MB)…",
                        Int(fileProgress * 100),
                        megabytes
                    )
                } else {
                    message = String(format: "Downloading Qwen runtime (%.1f MB)…", megabytes)
                }
                onProgress(min(overall, 0.85), message)
            }
        )

        onProgress(0.86, "Extracting Qwen runtime…")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runDittoUnzip(from: zipURL, to: extractDir, fileManager: fileManager)

        let extractedManifest = extractDir.appendingPathComponent("manifest.json")
        let extractedSitePackages = extractDir.appendingPathComponent("site-packages", isDirectory: true)
        guard fileManager.fileExists(atPath: extractedManifest.path),
              fileManager.fileExists(atPath: extractedSitePackages.path) else {
            throw QwenAddonError.invalidArchive
        }

        onProgress(0.92, "Installing Qwen runtime…")
        if fileManager.fileExists(atPath: addonRootURL.path) {
            try fileManager.removeItem(at: addonRootURL)
        }
        try fileManager.createDirectory(at: addonRootURL, withIntermediateDirectories: true)
        try fileManager.moveItem(at: extractedSitePackages, to: sitePackagesURL)
        try fileManager.moveItem(at: extractedManifest, to: manifestURL)

        guard verifyImport() else {
            try? fileManager.removeItem(at: addonRootURL)
            throw QwenAddonError.verifyFailed
        }

        onProgress(1.0, "Qwen runtime ready")
    }

    private static func downloadFile(
        from url: URL,
        to destination: URL,
        session: URLSession,
        fileManager: FileManager,
        onProgress: @Sendable @escaping (Double, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60 * 60

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QwenAddonError.downloadFailed
        }

        let expectedLength = response.expectedContentLength
        let tempURL = destination.appendingPathExtension("download")
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        fileManager.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer {
            try? handle.close()
        }

        var bytesDownloaded: Int64 = 0
        var lastReportedMegabytes = -1
        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)

        for try await byte in asyncBytes {
            buffer.append(byte)
            bytesDownloaded += 1

            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            if expectedLength > 0 {
                let fileProgress = Double(bytesDownloaded) / Double(expectedLength)
                onProgress(fileProgress, bytesDownloaded)
            } else {
                let megabytes = Int(bytesDownloaded / 1_000_000)
                if megabytes != lastReportedMegabytes {
                    lastReportedMegabytes = megabytes
                    onProgress(0, bytesDownloaded)
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        try handle.close()
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
    }

    private static func runDittoUnzip(from zipURL: URL, to extractDir: URL, fileManager: FileManager) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, extractDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw QwenAddonError.unzipFailed(message ?? "ditto exit \(process.terminationStatus)")
        }
    }
}

enum QwenAddonError: LocalizedError {
    case missingAppVersion
    case downloadFailed
    case invalidArchive
    case verifyFailed
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAppVersion:
            return "Cannot resolve app version for Qwen runtime download."
        case .downloadFailed:
            return "Failed to download Qwen runtime from GitHub Releases."
        case .invalidArchive:
            return "Downloaded Qwen runtime archive is invalid."
        case .verifyFailed:
            return "Qwen runtime installed but failed import verification."
        case .unzipFailed(let reason):
            return "Failed to extract Qwen runtime: \(reason)"
        }
    }
}
