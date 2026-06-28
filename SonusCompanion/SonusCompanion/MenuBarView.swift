import AppKit
import SwiftUI

enum SettingsWindowPresenter {
    static func show(_ openSettings: OpenSettingsAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        bringSettingsWindowToCurrentSpace(retryIfMissing: true)
    }

    static func configureForCurrentSpace(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.insert(.moveToActiveSpace)
        behavior.remove(.canJoinAllSpaces)
        window.collectionBehavior = behavior
    }

    static func configureSettingsWindowIfPresent() {
        guard let window = settingsWindow else { return }
        configureForCurrentSpace(window)
    }

    static func restoreMenuBarActivationPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    private static func bringSettingsWindowToCurrentSpace(retryIfMissing: Bool) {
        DispatchQueue.main.async {
            guard let window = settingsWindow else {
                if retryIfMissing {
                    bringSettingsWindowToCurrentSpace(retryIfMissing: false)
                }
                return
            }
            configureForCurrentSpace(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first(where: isSettingsWindow)
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue.localizedCaseInsensitiveContains("Settings") == true {
            return true
        }
        let title = window.title
        return title.localizedCaseInsensitiveContains("Settings")
            || title.localizedCaseInsensitiveContains("Sonus")
    }
}

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var serverCheckResult: String?

    var body: some View {
        Group {
            Text("Status: \(appState.statusMessage)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            Button("Speak Selection") {
                appState.speakSelection()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(appState.playbackState == .paused ? "Resume" : "Pause") {
                appState.pauseOrResume()
            }
            .disabled(appState.playbackState != .playing && appState.playbackState != .paused)

            Button("Stop") {
                appState.stop()
            }
            .disabled(appState.playbackState == .idle)

            Menu("Voice") {
                ForEach(appState.voices) { voice in
                    Button {
                        appState.setVoice(voice.id)
                    } label: {
                        if voice.id == appState.selectedVoiceID {
                            Text("✓ \(voice.name)")
                        } else {
                            Text(voice.name)
                        }
                    }
                }
            }

            Menu("Speed") {
                ForEach(AppSettings.speedOptions, id: \.self) { option in
                    Button {
                        appState.setSpeed(option)
                    } label: {
                        if option == appState.speed {
                            Text("✓ \(option, specifier: "%.1f")x")
                        } else {
                            Text("\(option, specifier: "%.1f")x")
                        }
                    }
                }
            }

            Text("Rules: \(appState.textRuleStore.statusSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu("Text Rules Profile") {
                Toggle(isOn: Binding(
                    get: { appState.textRuleStore.rulesEnabled },
                    set: { appState.textRuleStore.setRulesEnabled($0) }
                )) {
                    Text("Enable text rules")
                }
                Divider()
                ForEach(appState.textRuleStore.profiles) { profile in
                    Button {
                        appState.textRuleStore.setActiveProfile(id: profile.id)
                    } label: {
                        if profile.id == appState.textRuleStore.activeProfileId {
                            Text("✓ \(profile.name)")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }

            Divider()

            Button("Settings…") {
                SettingsWindowPresenter.show(openSettings)
            }

            Button("Check Sonus Server") {
                Task {
                    serverCheckResult = await appState.checkServer()
                }
            }

            if let serverCheckResult {
                Text(serverCheckResult)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            AppUpdateController.shared.startAutomaticChecks()
            appState.startup()
        }
    }
}
