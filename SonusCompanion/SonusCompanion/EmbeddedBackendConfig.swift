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
            // Return the venv shim (bin/python3.12), NOT the resolved symlink target.
            // Executing the shim lets Python read pyvenv.cfg and activate the venv,
            // so sys.prefix points at the venv root and site-packages resolves to
            // <runtime>/lib/python3.12/site-packages (where sonus lives).
            // Resolving symlinks here would run <runtime>/python/bin/python3.12
            // directly, which uses the bundled prefix and cannot find sonus.
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            let resolved = candidate.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(runtime.path) || resolved.path.contains("/sonus-runtime/python/") else {
                continue
            }
            return candidate
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
            return "Broken Python shim at \(python312.path) → \(resolved.path). Reinstall Sonus v0.3.3+."
        }
        if let launchError = runtimeLaunchError() {
            return launchError
        }
        return "Runtime found at \(resolved.path)"
    }

    /// Returns nil when embedded Python can execute; otherwise a user-facing error.
    static func runtimeLaunchError() -> String? {
        guard let python = embeddedPythonExecutable else {
            return "Embedded Python runtime was not found in the app bundle."
        }

        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-c",
            """
            import os, sonus, uvicorn
            runtime = os.path.realpath(os.environ["SONUS_RUNTIME_DIR"])
            path = os.path.realpath(sonus.__file__)
            if not path.startswith(runtime):
                raise SystemExit(f"sonus not bundled: {path} (runtime={runtime})")
            """,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        environment.removeValue(forKey: "PYTHONDONTWRITEBYTECODE")
        environment["PYTHONUNBUFFERED"] = "1"
        if let runtime = embeddedRuntimeURL {
            let binPath = runtime.appendingPathComponent("bin").path
            environment["PATH"] = binPath + ":" + (environment["PATH"] ?? "")
            environment["SONUS_RUNTIME_DIR"] = runtime.path
        }
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: "/")

        do {
            try process.run()
        } catch {
            return "Failed to launch embedded Python: \(error.localizedDescription)"
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = readPipeText(process.standardError)
            if stderr.contains("ModuleNotFoundError: No module named 'sonus'")
                || stderr.contains("sonus not bundled:") {
                return """
                Embedded backend package is missing from this build. \
                Install Sonus v0.3.3+ from GitHub Releases or use Settings → Advanced → Use external Sonus server.
                """
            }
            if stderr.contains("Library not loaded")
                || stderr.contains("Python.framework")
                || process.terminationStatus == 6 {
                return """
                Embedded Python cannot load on this Mac (exit \(process.terminationStatus)). \
                Install Sonus v0.3.3+ or enable Settings → Advanced → Use external Sonus server.
                """
            }
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Embedded Python failed to start (exit \(process.terminationStatus))."
            }
            return "Embedded Python failed to start: \(detail)"
        }
        return nil
    }

    private static func readPipeText(_ handle: Any?) -> String {
        guard let pipe = handle as? Pipe else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
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
