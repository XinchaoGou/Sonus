import Foundation

enum EmbeddedBackendConfig {
    static let runtimeResourceName = "sonus-runtime"
    static let defaultPort = 8000

    static var applicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sonus", isDirectory: true)
    }

    static var defaultModelsDirectory: URL {
        applicationSupportRoot.appendingPathComponent("models", isDirectory: true)
    }

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sonus/audio", isDirectory: true)
    }

    static var embeddedRuntimeURL: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let runtime = resources.appendingPathComponent(runtimeResourceName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: runtime.path) else { return nil }
        return resolvePythonExecutable(in: runtime) != nil ? runtime : nil
    }

    static var embeddedPythonExecutable: URL? {
        guard let runtime = embeddedRuntimeURL else { return nil }
        return resolvePythonExecutable(in: runtime)
    }

    static func resolvePythonExecutable(in runtime: URL) -> URL? {
        let bin = runtime.appendingPathComponent("bin", isDirectory: true)
        let candidates = ["python3.12", "python3", "python"].map {
            bin.appendingPathComponent($0)
        }

        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: resolved.path) else { continue }
            guard resolved.path.hasPrefix(runtime.path) || resolved.path.contains("/sonus-runtime/python/") else {
                continue
            }
            return resolved
        }
        return nil
    }

    static func embeddedBaseURL(port: Int) -> String {
        "http://127.0.0.1:\(port)"
    }

    static var runtimeDiagnosticMessage: String {
        guard let resources = Bundle.main.resourceURL else {
            return "App Resources directory unavailable."
        }
        let runtime = resources.appendingPathComponent(runtimeResourceName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: runtime.path) {
            return "Missing \(runtime.path). Install the Release build from GitHub Releases."
        }
        let bin = runtime.appendingPathComponent("bin", isDirectory: true)
        let python312 = bin.appendingPathComponent("python3.12")
        let resolved = python312.resolvingSymlinksInPath()
        if !FileManager.default.isExecutableFile(atPath: resolved.path) {
            return "Broken Python shim at \(python312.path) → \(resolved.path). Reinstall Sonus v0.3.1+."
        }
        return "Runtime found at \(resolved.path)"
    }

    #if DEBUG
    static var prefersExternalServerByDefault: Bool { true }
    #else
    static var prefersExternalServerByDefault: Bool { false }
    #endif

    static var canUseEmbeddedBackend: Bool {
        embeddedRuntimeURL != nil
    }
}
