import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .updateFailed(let detail):
            return "Could not update Launch at Login: \(detail)"
        }
    }
}

enum LaunchAtLoginManager {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    /// User requested login item (includes pending approval).
    static var isRegistered: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    static var needsApproval: Bool {
        status == .requiresApproval
    }

    static var statusHint: String? {
        switch status {
        case .enabled, .notRegistered:
            return nil
        case .requiresApproval:
            return "Approve Sonus Companion in System Settings → General → Login Items."
        case .notFound:
            return "Launch at Login is unavailable for this build."
        @unknown default:
            return nil
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppLogger.log("launch at login set enabled=\(enabled) status=\(String(describing: SMAppService.mainApp.status))")
        } catch {
            AppLogger.log("launch at login error: \(error.localizedDescription)")
            throw LaunchAtLoginError.updateFailed(error.localizedDescription)
        }
    }

    static func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
