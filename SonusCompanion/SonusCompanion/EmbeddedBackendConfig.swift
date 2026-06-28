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
        let python = runtime.appendingPathComponent("bin/python3")
        return FileManager.default.isExecutableFile(atPath: python.path) ? runtime : nil
    }

    static var embeddedPythonExecutable: URL? {
        embeddedRuntimeURL?.appendingPathComponent("bin/python3")
    }

    static func embeddedBaseURL(port: Int) -> String {
        "http://127.0.0.1:\(port)"
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
