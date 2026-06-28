import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateController {
    static let shared = AppUpdateController()

    private enum DefaultsKey {
        static let autoCheckUpdates = "autoCheckUpdates"
        static let skippedVersion = "skippedVersion"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
    }

    var autoCheckUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: DefaultsKey.autoCheckUpdates) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: DefaultsKey.autoCheckUpdates)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoCheckUpdates)
        }
    }

    var pendingUpdate: AvailableUpdate?
    var statusMessage = ""
    var isChecking = false
    var isDownloading = false

    var currentVersionString: String {
        AppVersion.current?.displayString ?? "Unknown"
    }

    var lastUpdateCheckDate: Date? {
        UserDefaults.standard.object(forKey: DefaultsKey.lastUpdateCheckDate) as? Date
    }

    private var automaticChecksStarted = false
    private var periodicCheckTask: Task<Void, Never>?

    private init() {}

    func startAutomaticChecks() {
        guard !automaticChecksStarted else { return }
        automaticChecksStarted = true

        Task {
            try? await Task.sleep(for: .seconds(5))
            await checkForUpdates(userInitiated: false)
        }

        periodicCheckTask?.cancel()
        periodicCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .hours(24))
                await checkForUpdates(userInitiated: false)
            }
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        if !userInitiated, !autoCheckUpdates {
            return
        }
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        if userInitiated {
            statusMessage = "Checking for updates…"
        }

        do {
            guard let update = try await GitHubReleaseClient.fetchLatestUpdate() else {
                pendingUpdate = nil
                statusMessage = userInitiated ? "Sonus is up to date." : ""
                recordCheckDate()
                return
            }

            guard let current = AppVersion.current else {
                statusMessage = "Unable to read current app version."
                return
            }

            if update.version <= current {
                pendingUpdate = nil
                statusMessage = userInitiated ? "Sonus is up to date." : ""
                recordCheckDate()
                return
            }

            if update.versionString == skippedVersion, !userInitiated {
                pendingUpdate = update
                statusMessage = "Update \(update.versionString) available."
                recordCheckDate()
                return
            }

            pendingUpdate = update
            statusMessage = "Update \(update.versionString) available."
            recordCheckDate()
            presentUpdateAvailableAlert(for: update, userInitiated: userInitiated)
        } catch {
            pendingUpdate = nil
            statusMessage = userInitiated ? "Update check failed: \(error.localizedDescription)" : ""
            AppLogger.log("update check failed: \(error.localizedDescription)")
        }
    }

    func installPendingUpdate() async {
        guard let update = pendingUpdate else { return }
        await downloadAndInstall(update: update)
    }

    func downloadAndInstall(update: AvailableUpdate) async {
        guard !isDownloading else { return }

        if !UpdateConfig.isRunningFromInstallLocation {
            presentNotInstalledAlert()
            return
        }

        isDownloading = true
        statusMessage = "Downloading update…"
        defer { isDownloading = false }

        do {
            let extractedApp = try await UpdateDownloader.downloadAndExtract(update: update)
            statusMessage = "Ready to install update \(update.versionString)."

            guard confirmInstall(version: update.versionString) else {
                statusMessage = "Update \(update.versionString) downloaded."
                return
            }

            try UpdateInstaller.installAndRelaunch(extractedAppURL: extractedApp)
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
            AppLogger.log("update install failed: \(error.localizedDescription)")
        }
    }

    func clearSkippedVersion() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.skippedVersion)
    }

    private var skippedVersion: String? {
        UserDefaults.standard.string(forKey: DefaultsKey.skippedVersion)
    }

    private func recordCheckDate() {
        UserDefaults.standard.set(Date(), forKey: DefaultsKey.lastUpdateCheckDate)
    }

    private func presentUpdateAvailableAlert(for update: AvailableUpdate, userInitiated: Bool) {
        activateForAlert()

        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = informativeText(for: update)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { await downloadAndInstall(update: update) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(update.versionString, forKey: DefaultsKey.skippedVersion)
            statusMessage = "Skipped version \(update.versionString)."
        default:
            if userInitiated {
                statusMessage = "Update \(update.versionString) available."
            }
        }
    }

    private func confirmInstall(version: String) -> Bool {
        activateForAlert()

        let alert = NSAlert()
        alert.messageText = "Install Update?"
        alert.informativeText = """
        Sonus will quit and replace:
        \(UpdateConfig.installPath)

        Version \(version) will launch when installation completes.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentNotInstalledAlert() {
        activateForAlert()

        let alert = NSAlert()
        alert.messageText = "Install Location Required"
        alert.informativeText = """
        Automatic updates require Sonus to be installed at:
        \(UpdateConfig.installPath)

        Move the app to Applications, then try again.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        statusMessage = "Install Sonus in /Applications to enable updates."
    }

    private func informativeText(for update: AvailableUpdate) -> String {
        var lines = ["A new version of Sonus is available: \(update.versionString)"]
        lines.append("Current version: \(currentVersionString)")
        if !update.releaseNotes.isEmpty {
            lines.append("")
            lines.append(update.releaseNotes)
        }
        return lines.joined(separator: "\n")
    }

    private func activateForAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension Duration {
    static func hours(_ value: Double) -> Duration {
        .seconds(value * 3600)
    }
}
