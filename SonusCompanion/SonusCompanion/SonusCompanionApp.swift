import SwiftUI
import UserNotifications

@main
struct SonusCompanionApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label("Sonus", systemImage: menuBarIconName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState)
        }
    }

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private var menuBarIconName: String {
        switch appState.playbackState {
        case .idle:
            return "waveform"
        case .generating:
            return "waveform.circle"
        case .playing:
            return "play.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}
