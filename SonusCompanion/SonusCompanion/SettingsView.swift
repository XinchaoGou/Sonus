import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var serverCheckMessage: String?
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isRegistered
    @State private var launchAtLoginMessage: String?
    @State private var showTextRulesSettings = false
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?

    var body: some View {
        Form {
            Section("Sonus Server") {
                TextField("Server URL", text: $appState.serverURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Check Connection") {
                        Task {
                            serverCheckMessage = await appState.checkServer()
                        }
                    }
                    if let serverCheckMessage {
                        Text(serverCheckMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }

            Section("Defaults") {
                Picker("Voice", selection: $appState.selectedVoiceID) {
                    ForEach(appState.voices) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
                Picker("Speed", selection: $appState.speed) {
                    ForEach(AppSettings.speedOptions, id: \.self) { option in
                        Text("\(option, specifier: "%.1f")x").tag(option)
                    }
                }
            }

            Section("Hotkey") {
                HStack {
                    Text(appState.hotkeyConfiguration.displayName)
                        .font(.body.monospaced())
                    Spacer()
                    Button(isRecordingHotkey ? "Press keys…" : "Change…") {
                        toggleHotkeyRecording()
                    }
                }
                Text("Default: ⌥Esc. Requires a modifier key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text Capture") {
                Toggle("Enable clipboard fallback (Cmd+C)", isOn: $appState.clipboardFallbackEnabled)
                HStack {
                    Image(systemName: appState.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.isAccessibilityTrusted ? .green : .orange)
                    Text(appState.isAccessibilityTrusted ? "Accessibility permission granted" : "Accessibility permission required")
                    Spacer()
                    Button("Open Settings") {
                        SelectedTextReader.openAccessibilitySettings()
                    }
                    Button("Refresh") {
                        appState.isAccessibilityTrusted = SelectedTextReader.isAccessibilityTrusted
                    }
                }
                if !appState.isAccessibilityTrusted {
                    Text("Grant Accessibility access for selected text and clipboard fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Text Rules") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(appState.textRuleStore.statusSummary)
                        .foregroundStyle(.secondary)
                }
                Button("Manage Text Rules…") {
                    showTextRulesSettings = true
                }
                Text("Preprocess selected text before TTS (citations, figure refs, etc.).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cache") {
                Toggle("Enable local audio cache", isOn: $appState.cacheEnabled)
                Button("Clear Cache") {
                    appState.clearCache()
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
                if LaunchAtLoginManager.needsApproval {
                    HStack {
                        Text("Waiting for approval in Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") {
                            LaunchAtLoginManager.openLoginItemsSettings()
                        }
                    }
                } else if let launchAtLoginMessage {
                    Text(launchAtLoginMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                } else if let hint = LaunchAtLoginManager.statusHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
        .sheet(isPresented: $showTextRulesSettings) {
            TextRulesSettingsView(
                store: appState.textRuleStore,
                lastSelection: Binding(
                    get: { appState.lastSelectionText },
                    set: { appState.lastSelectionText = $0 }
                )
            )
        }
        .onDisappear {
            appState.setVoice(appState.selectedVoiceID)
            appState.persistSettings()
            stopHotkeyRecording()
            SettingsWindowPresenter.restoreMenuBarActivationPolicy()
        }
        .onAppear {
            SettingsWindowPresenter.configureSettingsWindowIfPresent()
            appState.isAccessibilityTrusted = SelectedTextReader.isAccessibilityTrusted
            if !appState.isAccessibilityTrusted {
                SelectedTextReader.requestAccessibilityPermission()
            }
            refreshLaunchAtLoginStatus()
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = LaunchAtLoginManager.isRegistered
        launchAtLoginMessage = LaunchAtLoginManager.statusHint
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLoginMessage = LaunchAtLoginManager.statusHint
        } catch {
            launchAtLoginMessage = error.localizedDescription
            refreshLaunchAtLoginStatus()
        }
    }

    private func toggleHotkeyRecording() {
        if isRecordingHotkey {
            stopHotkeyRecording()
        } else {
            startHotkeyRecording()
        }
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotkey else { return event }
            let carbonMods = carbonModifiers(from: event.modifierFlags)
            guard carbonMods != 0 else { return nil }
            let config = HotkeyConfiguration(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
            appState.updateHotkey(config)
            stopHotkeyRecording()
            return nil
        }
    }

    private func stopHotkeyRecording() {
        isRecordingHotkey = false
        if let hotkeyMonitor {
            NSEvent.removeMonitor(hotkeyMonitor)
            self.hotkeyMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
