import Foundation

enum AppLogger {
    private static let queue = DispatchQueue(label: "com.sonus.companion.logger")
    private static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SonusCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sonus-companion.log")
    }()

    static func log(_ message: String) {
        let line = "[\(timestamp())] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: logURL)
                }
            }
        }
        #if DEBUG
        print(line, terminator: "")
        #endif
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
