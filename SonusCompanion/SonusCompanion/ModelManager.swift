import Foundation

struct ModelAsset: Sendable {
    let filename: String
    let url: URL

    func destination(in directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }
}

enum ModelManager {
    static let requiredAssets: [ModelAsset] = [
        ModelAsset(
            filename: "kokoro-v1.0.onnx",
            url: URL(string: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx")!
        ),
        ModelAsset(
            filename: "voices-v1.0.bin",
            url: URL(string: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin")!
        ),
        ModelAsset(
            filename: "kokoro-v1.1-zh.onnx",
            url: URL(string: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.1-zh.onnx")!
        ),
        ModelAsset(
            filename: "voices-v1.1-zh.bin",
            url: URL(string: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.1-zh.bin")!
        ),
        ModelAsset(
            filename: "kokoro-v1.1-zh-config.json",
            url: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/raw/main/config.json")!
        ),
    ]

    static func resolveModelsDirectory(customPath: String?) -> URL? {
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: customPath, isDirectory: true)
            if directoryIsReady(url) {
                return url
            }
        }

        let appSupport = EmbeddedBackendConfig.defaultModelsDirectory
        if directoryIsReady(appSupport) {
            return appSupport
        }

        if let envPath = ProcessInfo.processInfo.environment["SONUS_MODELS_DIR"],
           !envPath.isEmpty {
            let url = URL(fileURLWithPath: envPath, isDirectory: true)
            if directoryIsReady(url) {
                return url
            }
        }

        return nil
    }

    static func targetModelsDirectory(customPath: String?) -> URL {
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: customPath, isDirectory: true)
        }
        return EmbeddedBackendConfig.defaultModelsDirectory
    }

    static func directoryIsReady(_ directory: URL) -> Bool {
        requiredAssets.allSatisfy { asset in
            FileManager.default.fileExists(atPath: asset.destination(in: directory).path)
        }
    }

    static func missingAssets(in directory: URL) -> [ModelAsset] {
        requiredAssets.filter { asset in
            !FileManager.default.fileExists(atPath: asset.destination(in: directory).path)
        }
    }

    static func downloadMissingModels(
        into directory: URL,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let missing = missingAssets(in: directory)
        guard !missing.isEmpty else {
            onProgress(1.0, "Models ready")
            return
        }

        let total = Double(missing.count)
        for (index, asset) in missing.enumerated() {
            let baseProgress = Double(index) / total
            onProgress(baseProgress + 0.01, "Downloading \(asset.filename)…")

            let destination = asset.destination(in: directory)
            try await downloadFile(
                from: asset.url,
                to: destination,
                onProgress: { fileProgress, bytesDownloaded in
                    let overall = baseProgress + (fileProgress / total)
                    let megabytes = Double(bytesDownloaded) / 1_000_000.0
                    onProgress(
                        min(overall, (Double(index + 1) / total) - 0.01),
                        String(format: "Downloading %@ (%.1f MB)…", asset.filename, megabytes)
                    )
                }
            )

            onProgress(Double(index + 1) / total, "Downloaded \(asset.filename)")
        }

        onProgress(1.0, "Models ready")
    }

    private static func downloadFile(
        from url: URL,
        to destination: URL,
        onProgress: @Sendable @escaping (Double, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60 * 30

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelManagerError.downloadFailed(url.lastPathComponent)
        }

        let expectedLength = response.expectedContentLength
        let tempURL = destination.appendingPathExtension("download")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
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
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}

enum ModelManagerError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let name):
            return "Failed to download model file: \(name)"
        }
    }
}
