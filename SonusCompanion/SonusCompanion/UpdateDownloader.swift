import Foundation

enum UpdateDownloader {
    enum Error: LocalizedError {
        case downloadFailed(String)
        case unzipFailed(String)
        case missingAppBundle

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            case .unzipFailed(let reason):
                return "Failed to extract update: \(reason)"
            case .missingAppBundle:
                return "Update archive did not contain \(UpdateConfig.appBundleName)."
            }
        }
    }

    static func cacheDirectory(fileManager: FileManager = .default) -> URL {
        let dir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Sonus/Updates", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func downloadAndExtract(
        update: AvailableUpdate,
        onProgress: @Sendable @escaping (Double, String) -> Void = { _, _ in },
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let workDir = cacheDirectory(fileManager: fileManager)
            .appendingPathComponent(update.versionString, isDirectory: true)
        try? fileManager.removeItem(at: workDir)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = workDir.appendingPathComponent(UpdateConfig.assetFileName)
        let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)

        onProgress(0, "Downloading update…")

        do {
            try await downloadFile(
                from: update.downloadURL,
                to: zipURL,
                session: session,
                fileManager: fileManager,
                onProgress: { fileProgress, bytesDownloaded in
                    let overall = fileProgress * 0.9
                    let megabytes = Double(bytesDownloaded) / 1_000_000.0
                    let message: String
                    if fileProgress > 0 {
                        message = String(
                            format: "Downloading update (%d%% · %.1f MB)…",
                            Int(fileProgress * 100),
                            megabytes
                        )
                    } else {
                        message = String(format: "Downloading update (%.1f MB)…", megabytes)
                    }
                    onProgress(overall, message)
                }
            )
        } catch let error as Error {
            throw error
        } catch {
            throw Error.downloadFailed(error.localizedDescription)
        }

        onProgress(0.92, "Extracting update…")
        try? fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runDittoUnzip(from: zipURL, to: extractDir)
        onProgress(1.0, "Update ready")

        let appURL = extractDir.appendingPathComponent(UpdateConfig.appBundleName, isDirectory: true)
        guard fileManager.fileExists(atPath: appURL.path) else {
            throw Error.missingAppBundle
        }
        return appURL
    }

    private static func downloadFile(
        from url: URL,
        to destination: URL,
        session: URLSession,
        fileManager: FileManager,
        onProgress: @Sendable @escaping (Double, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60 * 30

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.downloadFailed("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.downloadFailed("HTTP \(http.statusCode)")
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

    private static func runDittoUnzip(from zipURL: URL, to extractDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, extractDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw Error.unzipFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.unzipFailed(message?.isEmpty == false ? message! : "ditto exit \(process.terminationStatus)")
        }
    }
}
