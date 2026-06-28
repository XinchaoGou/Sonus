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
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let workDir = cacheDirectory(fileManager: fileManager)
            .appendingPathComponent(update.versionString, isDirectory: true)
        try? fileManager.removeItem(at: workDir)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = workDir.appendingPathComponent(UpdateConfig.assetFileName)
        let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)

        do {
            let (tempURL, response) = try await session.download(from: update.downloadURL)
            defer { try? fileManager.removeItem(at: tempURL) }

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Error.downloadFailed("HTTP \(http.statusCode)")
            }

            if fileManager.fileExists(atPath: zipURL.path) {
                try fileManager.removeItem(at: zipURL)
            }
            try fileManager.moveItem(at: tempURL, to: zipURL)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.downloadFailed(error.localizedDescription)
        }

        try? fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runDittoUnzip(from: zipURL, to: extractDir)

        let appURL = extractDir.appendingPathComponent(UpdateConfig.appBundleName, isDirectory: true)
        guard fileManager.fileExists(atPath: appURL.path) else {
            throw Error.missingAppBundle
        }
        return appURL
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
