import AppKit
import Foundation

enum UpdateInstaller {
    enum Error: LocalizedError {
        case scriptWriteFailed(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptWriteFailed(let reason):
                return "Failed to prepare install script: \(reason)"
            case .launchFailed(let reason):
                return "Failed to start install script: \(reason)"
            }
        }
    }

    static func installAndRelaunch(extractedAppURL: URL) throws {
        let scriptURL = try writeInstallScript(newAppURL: extractedAppURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw Error.launchFailed(error.localizedDescription)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func writeInstallScript(newAppURL: URL) throws -> URL {
        let scriptDir = UpdateDownloader.cacheDirectory()
            .appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)

        let scriptURL = scriptDir.appendingPathComponent("install-update.sh")
        let target = UpdateConfig.installPath
        let executable = UpdateConfig.executableName
        let newPath = newAppURL.path

        let script = """
        #!/bin/bash
        set -euo pipefail
        TARGET='\(target)'
        NEW='\(newPath)'
        EXEC='\(executable)'

        for _ in $(seq 1 60); do
          pgrep -x "$EXEC" >/dev/null || break
          sleep 0.25
        done

        if [ -w "$(dirname "$TARGET")" ]; then
          rm -rf "$TARGET"
          /usr/bin/ditto "$NEW" "$TARGET"
        else
          /usr/bin/osascript -e "do shell script \\"rm -rf '$TARGET' && /usr/bin/ditto '$NEW' '$TARGET'\\" with administrator privileges"
        fi

        /usr/bin/open "$TARGET"
        """

        do {
            try script.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw Error.scriptWriteFailed(error.localizedDescription)
        }
        return scriptURL
    }
}
