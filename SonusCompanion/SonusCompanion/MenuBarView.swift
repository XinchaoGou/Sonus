import SwiftUI

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

            Divider()

            Button("Settings…") {
                openSettings()
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
            appState.startup()
        }
    }
}
