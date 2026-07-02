import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var updateController = AppUpdateController.shared
    @State private var serverCheckMessage: String?
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isRegistered
    @State private var launchAtLoginMessage: String?
    @State private var showTextRulesSettings = false
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var hotkeyMessage: String?

    var body: some View {
        Form {
            Section("Backend") {
                HStack {
                    Text("Status")
                    Spacer()
                    backendStatusLabel
                }

                if case .downloadingModels(let progress, let message) = appState.backendState {
                    ProgressView(value: progress)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !appState.backendStatusMessage.isEmpty {
                    Text(appState.backendStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Picker("Engine", selection: $appState.activeEngine) {
                    if appState.engines.isEmpty {
                        Text("Kokoro").tag("kokoro")
                    } else {
                        ForEach(appState.engines) { engine in
                            Text(engineLabel(engine)).tag(engine.id)
                        }
                    }
                }
                .onChange(of: appState.activeEngine) { _, newValue in
                    Task { await appState.switchActiveEngine(to: newValue) }
                }

                if let engineSwitchMessage = appState.engineSwitchMessage {
                    Text(engineSwitchMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if !appState.useExternalServer {
                    Stepper(value: $appState.serverPort, in: 1024...65535) {
                        Text("Port: \(appState.serverPort)")
                    }

                    LabeledContent("Models") {
                        Text(modelsLocationSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    Button("Download / Verify Models") {
                        Task { await appState.restartBackend() }
                    }
                }

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

            Section("Advanced") {
                Toggle("Use external Sonus server", isOn: $appState.useExternalServer)
                    .onChange(of: appState.useExternalServer) { _, _ in
                        appState.applyBackendSettingsChange()
                    }

                if appState.useExternalServer {
                    TextField("Server URL", text: $appState.serverURL)
                        .textFieldStyle(.roundedBorder)
                }

                if !appState.useExternalServer {
                    TextField("Custom models directory (optional)", text: $appState.customModelsPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            appState.applyBackendSettingsChange()
                        }
                    Text("Leave empty to use Application Support or download on first launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if EmbeddedBackendConfig.canUseEmbeddedBackend {
                    Text("Embedded Python runtime is bundled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Embedded runtime not found in this build. Use an external server or a Release build from build_app.sh.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                Text("Default: ⌘Esc. Requires a modifier key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hotkeyMessage {
                    Text(hotkeyMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
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

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updateController.autoCheckUpdates },
                    set: { updateController.autoCheckUpdates = $0 }
                ))

                LabeledContent("Current version") {
                    Text(updateController.currentVersionString)
                        .foregroundStyle(.secondary)
                }

                if let lastCheck = updateController.lastUpdateCheckDate {
                    LabeledContent("Last checked") {
                        Text(lastCheck.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(updateController.isChecking ? "Checking…" : "Check Now…") {
                        Task {
                            await updateController.checkForUpdates(userInitiated: true)
                        }
                    }
                    .disabled(updateController.isChecking || updateController.isDownloading)

                    if updateController.pendingUpdate != nil {
                        Button(updateController.isDownloading ? "Downloading…" : "Install Update…") {
                            Task {
                                await updateController.installPendingUpdate()
                            }
                        }
                        .disabled(updateController.isDownloading)
                    }
                }

                if updateController.isDownloading {
                    if updateController.downloadProgress > 0 {
                        ProgressView(value: updateController.downloadProgress)
                    } else {
                        ProgressView()
                    }
                }

                if !updateController.statusMessage.isEmpty {
                    Text(updateController.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                if !UpdateConfig.isRunningFromInstallLocation {
                    Text("Install Sonus in /Applications to enable automatic updates.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
            appState.applyBackendSettingsChange()
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
        hotkeyMessage = nil
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotkey else { return event }
            guard let config = HotkeyConfiguration.captured(from: event) else { return nil }
            if appState.updateHotkey(config) {
                stopHotkeyRecording()
            } else {
                hotkeyMessage = "Could not register this shortcut. It may be reserved by macOS."
            }
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

    private var backendStatusLabel: some View {
        Group {
            switch appState.backendState {
            case .running, .external:
                Label(appState.backendState.displayName, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label(appState.backendState.displayName, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .downloadingModels, .starting, .checkingModels:
                Label(appState.backendState.displayName, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            case .idle:
                Text(appState.backendState.displayName)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func engineLabel(_ engine: EngineStatusResponse) -> String {
        if engine.ready {
            return engine.name
        }
        if engine.installed {
            return "\(engine.name) (incomplete)"
        }
        return "\(engine.name) (not installed)"
    }

    private var modelsLocationSummary: String {
        if let resolved = ModelManager.resolveModelsDirectory(customPath: appState.customModelsPath.nilIfEmpty)?.path {
            return resolved
        }
        return ModelManager.targetModelsDirectory(customPath: appState.customModelsPath.nilIfEmpty).path
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
