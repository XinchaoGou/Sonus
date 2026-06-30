import Foundation
import SwiftUI
import UserNotifications

enum AppSettings {
    static let serverURLKey = "serverURL"
    static let serverPortKey = "serverPort"
    static let useExternalServerKey = "useExternalServer"
    static let customModelsPathKey = "customModelsPath"
    static let activeEngineKey = "activeEngine"
    static let defaultVoiceKey = "defaultVoice"
    static let defaultSpeedKey = "defaultSpeed"
    static let hotkeyConfigKey = "hotkeyConfig"
    static let clipboardFallbackKey = "clipboardFallbackEnabled"
    static let cacheEnabledKey = "cacheEnabled"
    static let cachedVoicesKey = "cachedVoices"

    static let defaultServerURL = "http://127.0.0.1:8000"
    static let defaultServerPort = 8000
    static let defaultEngineID = "kokoro"
    static let defaultVoiceID = "zh_female"
    static let defaultSpeedValue = 1.0

    static var serverPort: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: serverPortKey)
            return value == 0 ? defaultServerPort : value
        }
        set { UserDefaults.standard.set(newValue, forKey: serverPortKey) }
    }

    static var useExternalServer: Bool {
        get {
            if UserDefaults.standard.object(forKey: useExternalServerKey) == nil {
                return EmbeddedBackendConfig.prefersExternalServerByDefault
            }
            return UserDefaults.standard.bool(forKey: useExternalServerKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: useExternalServerKey) }
    }

    static var customModelsPath: String {
        get { UserDefaults.standard.string(forKey: customModelsPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customModelsPathKey) }
    }

    static var activeEngine: String {
        get { UserDefaults.standard.string(forKey: activeEngineKey) ?? defaultEngineID }
        set { UserDefaults.standard.set(newValue, forKey: activeEngineKey) }
    }

    static func embeddedServerURL(port: Int = serverPort) -> String {
        EmbeddedBackendConfig.embeddedBaseURL(port: port)
    }

    static var serverURL: String {
        get {
            if useExternalServer {
                return UserDefaults.standard.string(forKey: serverURLKey) ?? defaultServerURL
            }
            return embeddedServerURL()
        }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }

    static var defaultVoice: String {
        get { UserDefaults.standard.string(forKey: defaultVoiceKey) ?? defaultVoiceID }
        set { UserDefaults.standard.set(newValue, forKey: defaultVoiceKey) }
    }

    static var defaultSpeed: Double {
        get {
            let value = UserDefaults.standard.double(forKey: defaultSpeedKey)
            return value == 0 ? defaultSpeedValue : value
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultSpeedKey) }
    }

    static var clipboardFallbackEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: clipboardFallbackKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: clipboardFallbackKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: clipboardFallbackKey) }
    }

    static var cacheEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: cacheEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: cacheEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: cacheEnabledKey) }
    }

    static var hotkeyConfiguration: HotkeyConfiguration {
        get {
            guard let data = UserDefaults.standard.data(forKey: hotkeyConfigKey),
                  let config = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
                return .default
            }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: hotkeyConfigKey)
            }
        }
    }

    static var cachedVoices: [Voice] {
        get {
            guard let data = UserDefaults.standard.data(forKey: cachedVoicesKey),
                  let voices = try? JSONDecoder().decode([Voice].self, from: data) else {
                return fallbackVoices
            }
            return voices
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: cachedVoicesKey)
            }
        }
    }

    static let fallbackVoices: [Voice] = [
        Voice(id: "zh_female", name: "中文女声", language: "cmn"),
        Voice(id: "zh_male", name: "中文男声", language: "cmn"),
        Voice(id: "en_female", name: "English Female", language: "en-us"),
        Voice(id: "en_male", name: "English Male", language: "en-us"),
        Voice(id: "ja_female", name: "日本語女声", language: "ja"),
    ]

    static let speedOptions: [Double] = [0.8, 1.0, 1.2, 1.5, 2.0]
}

@MainActor
@Observable
final class AppState {
    var playbackState: PlaybackState = .idle
    var statusMessage: String = "Idle"
    var errorMessage: String?
    var voices: [Voice] = AppSettings.cachedVoices
    var selectedVoiceID: String = AppSettings.defaultVoice
    var speed: Double = AppSettings.defaultSpeed
    var serverURL: String = AppSettings.serverURL
    var serverPort: Int = AppSettings.serverPort
    var useExternalServer: Bool = AppSettings.useExternalServer
    var customModelsPath: String = AppSettings.customModelsPath
    var activeEngine: String = AppSettings.activeEngine
    var engines: [EngineStatusResponse] = []
    var engineSwitchMessage: String?
    var backendState: BackendState = .idle
    var backendStatusMessage: String = BackendState.idle.displayName
    var clipboardFallbackEnabled: Bool = AppSettings.clipboardFallbackEnabled
    var cacheEnabled: Bool = AppSettings.cacheEnabled
    var hotkeyConfiguration: HotkeyConfiguration = AppSettings.hotkeyConfiguration
    var isAccessibilityTrusted: Bool = SelectedTextReader.isAccessibilityTrusted
    var textRuleStore = TextRuleStore()
    var lastSelectionText: String?

    private let filePlayer = AudioPlayer()
    private var streamPlayer: StreamingAudioPlayer?
    private var usesStreamPlayback = false
    private let hotkeyManager = HotkeyManager()
    private var generationTask: Task<Void, Never>?
    private let backendManager = BackendManager()

    init() {
        filePlayer.onFinished = { [weak self] in
            guard self?.usesStreamPlayback == false else { return }
            self?.playbackState = .idle
            self?.statusMessage = PlaybackState.idle.rawValue
        }
        filePlayer.onFailure = { [weak self] message in
            guard self?.usesStreamPlayback == false else { return }
            self?.setError(message)
        }
        backendManager.onStateChange = { [weak self] state in
            self?.backendState = state
            self?.backendStatusMessage = state.displayName
        }
    }

    func startup() {
        AppLogger.log("app start")
        registerHotkey()
        Task { await startBackendAndRefreshVoices() }
    }

    func shutdown() {
        backendManager.shutdown()
    }

    func startBackendAndRefreshVoices() async {
        syncServerURLFromSettings()
        let resolvedURL = await backendManager.ensureRunning(
            useExternalServer: useExternalServer,
            externalServerURL: externalServerURLValue(),
            port: serverPort,
            customModelsPath: customModelsPath.nilIfEmpty,
            activeEngine: activeEngine
        )
        serverURL = resolvedURL
        if backendManager.state.isOperational || useExternalServer {
            await refreshEngines()
            await refreshVoices()
        }
    }

    func restartBackend() async {
        if useExternalServer {
            await startBackendAndRefreshVoices()
            return
        }
        syncServerURLFromSettings()
        await backendManager.restart(
            port: serverPort,
            customModelsPath: customModelsPath.nilIfEmpty,
            activeEngine: activeEngine
        )
        serverURL = AppSettings.embeddedServerURL(port: serverPort)
        if backendManager.state.isOperational {
            await refreshEngines()
            await refreshVoices()
        }
    }

    private func externalServerURLValue() -> String {
        UserDefaults.standard.string(forKey: AppSettings.serverURLKey) ?? AppSettings.defaultServerURL
    }

    private func syncServerURLFromSettings() {
        if useExternalServer {
            serverURL = externalServerURLValue()
        } else {
            serverURL = AppSettings.embeddedServerURL(port: serverPort)
        }
    }

    func registerHotkey() {
        hotkeyManager.onHotkey = { [weak self] in
            AppLogger.log("hotkey triggered")
            self?.handleHotkey()
        }
        hotkeyManager.register(configuration: hotkeyConfiguration)
    }

    func updateHotkey(_ config: HotkeyConfiguration) {
        hotkeyConfiguration = config
        AppSettings.hotkeyConfiguration = config
        registerHotkey()
    }

    func handleHotkey() {
        switch playbackState {
        case .playing, .paused, .generating:
            stop()
            speakSelection()
        default:
            speakSelection()
        }
    }

    func speakSelection() {
        generationTask?.cancel()
        errorMessage = nil
        isAccessibilityTrusted = SelectedTextReader.isAccessibilityTrusted

        let reader = SelectedTextReader(clipboardFallbackEnabled: clipboardFallbackEnabled)
        switch reader.readSelectedText() {
        case .success(let text):
            lastSelectionText = text
            speakProcessedSelection(text)
        case .failure(let error):
            if case SelectedTextError.accessibilityDenied = error, !clipboardFallbackEnabled {
                setError(error.localizedDescription)
            } else {
                setError(error.localizedDescription)
            }
            showTransientError(error.localizedDescription ?? "Failed to read selection.")
        }
    }

    private func speakProcessedSelection(_ rawText: String) {
        let profile = textRuleStore.activeProfile
        let enabledRuleCount = profile.rules.filter(\.enabled).count
        let result = TextPreprocessor.process(
            text: rawText,
            profile: profile,
            rulesEnabled: textRuleStore.rulesEnabled
        ) { name, error in
            AppLogger.log("text rule skipped: \(name) \(error)")
        }

        AppLogger.log(
            "preprocess profile=\(profile.id) rules=\(enabledRuleCount) " +
            "raw_len=\(rawText.count) proc_len=\(result.text.count) fingerprint=\(result.fingerprint.prefix(12))..."
        )

        guard !result.text.isEmpty else {
            showTransientError("No speakable text after rules.")
            return
        }

        speak(text: result.text, rulesFingerprint: result.fingerprint)
    }

    func speak(text: String, rulesFingerprint: String = TextPreprocessor.noopFingerprint) {
        generationTask?.cancel()
        stopPlaybackOnly()
        playbackState = .generating
        statusMessage = PlaybackState.generating.rawValue
        errorMessage = nil
        usesStreamPlayback = false

        let voice = selectedVoiceID
        let currentSpeed = speed
        let client = SonusClient(baseURL: serverURL)
        let useCache = cacheEnabled
        let cacheURL = AudioPlayer.cacheFileURL(
            text: text,
            voice: voice,
            speed: currentSpeed,
            format: "wav",
            rulesFingerprint: rulesFingerprint
        )

        if useCache, AudioPlayer.cachedFileExists(at: cacheURL) {
            AppLogger.log("cache hit voice=\(voice) speed=\(currentSpeed)")
            playCachedFile(at: cacheURL, speed: currentSpeed)
            return
        }

        AppLogger.log("stream request voice=\(voice) speed=\(currentSpeed) text_length=\(text.count)")

        generationTask = Task {
            let started = Date()
            let player = StreamingAudioPlayer()
            streamPlayer = player
            usesStreamPlayback = true

            player.onFirstBuffer = { [weak self] in
                guard let self else { return }
                let ttfbMs = Int(Date().timeIntervalSince(started) * 1000)
                AppLogger.log("stream ttfb_ms=\(ttfbMs)")
                playbackState = .playing
                statusMessage = PlaybackState.playing.rawValue
            }
            player.onFinished = { [weak self] in
                guard let self else { return }
                usesStreamPlayback = false
                streamPlayer = nil
                playbackState = .idle
                statusMessage = PlaybackState.idle.rawValue
            }
            player.onFailure = { [weak self] message in
                guard let self else { return }
                usesStreamPlayback = false
                streamPlayer = nil
                setError(message)
                showTransientError(message)
            }

            do {
                try player.start(speed: currentSpeed)

                var totalBytes = 0
                for try await chunk in client.synthesizeStream(text: text, voice: voice, speed: currentSpeed) {
                    try Task.checkCancellation()
                    totalBytes += chunk.count
                    player.appendPCM(chunk)
                }

                let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
                AppLogger.log("stream complete latency_ms=\(latencyMs) bytes=\(totalBytes)")

                if useCache, !player.accumulatedPCM.isEmpty {
                    let wav = WAVEncoder.wrapPCM(player.accumulatedPCM)
                    try? AudioPlayer.saveToCache(data: wav, url: cacheURL)
                    AppLogger.log("stream cached to wav")
                }

                player.finishStream()
            } catch is CancellationError {
                usesStreamPlayback = false
                streamPlayer = nil
                player.stop()
            } catch {
                guard !Task.isCancelled else { return }
                usesStreamPlayback = false
                streamPlayer = nil
                player.stop()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                AppLogger.log("stream error: \(message)")
                setError(message)
                showTransientError(message)
            }
        }
    }

    private func playCachedFile(at url: URL, speed: Double) {
        usesStreamPlayback = false
        do {
            try filePlayer.play(fileURL: url, speed: speed)
            playbackState = .playing
            statusMessage = PlaybackState.playing.rawValue
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            setError(message)
            showTransientError(message)
        }
    }

    private func stopPlaybackOnly() {
        filePlayer.stop()
        streamPlayer?.stop()
        streamPlayer = nil
        usesStreamPlayback = false
    }

    func pauseOrResume() {
        switch playbackState {
        case .playing:
            if usesStreamPlayback {
                streamPlayer?.pause()
            } else {
                filePlayer.pause()
            }
            playbackState = .paused
            statusMessage = PlaybackState.paused.rawValue
        case .paused:
            if usesStreamPlayback {
                streamPlayer?.resume(speed: speed)
            } else {
                filePlayer.resume(speed: speed)
            }
            playbackState = .playing
            statusMessage = PlaybackState.playing.rawValue
        default:
            break
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        stopPlaybackOnly()
        playbackState = .idle
        statusMessage = PlaybackState.idle.rawValue
    }

    func setVoice(_ voiceID: String) {
        selectedVoiceID = voiceID
        AppSettings.defaultVoice = voiceID
    }

    func setSpeed(_ newSpeed: Double) {
        speed = newSpeed
        AppSettings.defaultSpeed = newSpeed
        if playbackState == .playing {
            if usesStreamPlayback {
                streamPlayer?.setRate(speed: newSpeed)
            } else {
                filePlayer.resume(speed: newSpeed)
            }
        }
    }

    func persistSettings() {
        AppSettings.serverPort = serverPort
        AppSettings.useExternalServer = useExternalServer
        AppSettings.customModelsPath = customModelsPath
        AppSettings.activeEngine = activeEngine
        if useExternalServer {
            AppSettings.serverURL = serverURL
        }
        AppSettings.clipboardFallbackEnabled = clipboardFallbackEnabled
        AppSettings.cacheEnabled = cacheEnabled
    }

    func applyBackendSettingsChange() {
        Task { await startBackendAndRefreshVoices() }
    }

    func refreshEngines() async {
        let client = SonusClient(baseURL: serverURL)
        do {
            engines = try await client.fetchEngines()
            if let active = engines.first(where: { $0.active }) {
                activeEngine = active.id
                AppSettings.activeEngine = active.id
            }
        } catch {
            AppLogger.log("engines refresh failed: \(error.localizedDescription)")
        }
    }

    func switchActiveEngine(to engineID: String) async {
        engineSwitchMessage = nil
        stop()

        let previousEngine = engines.first(where: { $0.active })?.id ?? activeEngine
        if let serverActive = engines.first(where: { $0.active })?.id,
           serverActive == engineID,
           backendManager.state.isOperational || useExternalServer {
            return
        }

        if useExternalServer {
            let client = SonusClient(baseURL: serverURL, timeoutSeconds: 120)
            do {
                let active = try await client.setActiveEngine(engineID)
                activeEngine = active
                AppSettings.activeEngine = active
                await refreshEngines()
                await refreshVoices()
                engineSwitchMessage = "Active engine: \(active)"
                AppLogger.log("engine switched to \(active)")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                engineSwitchMessage = message
                activeEngine = previousEngine
                AppLogger.log("engine switch failed: \(message)")
            }
            return
        }

        // Embedded backend: restart the Python process instead of hot-switching,
        // so the active engine loads in a clean process with fresh resources.
        activeEngine = engineID
        AppSettings.activeEngine = engineID
        await restartBackend()

        if backendManager.state.isOperational {
            await refreshEngines()
            await refreshVoices()
            engineSwitchMessage = "Active engine: \(engineID)"
            AppLogger.log("engine switched to \(engineID) via backend restart")
            return
        }

        AppLogger.log("engine switch restart failed; reverting to \(previousEngine)")
        activeEngine = previousEngine
        AppSettings.activeEngine = previousEngine
        await restartBackend()
        await refreshEngines()
        if let active = engines.first(where: { $0.active }) {
            activeEngine = active.id
        }
        engineSwitchMessage = backendStatusMessage
    }

    func refreshVoices() async {
        let client = SonusClient(baseURL: serverURL)
        do {
            let fetched = try await client.fetchVoices()
            voices = fetched
            AppSettings.cachedVoices = fetched
            if !fetched.contains(where: { $0.id == selectedVoiceID }), let first = fetched.first {
                setVoice(first.id)
            }
            AppLogger.log("voices refreshed count=\(fetched.count)")
        } catch {
            AppLogger.log("voices refresh failed: \(error.localizedDescription)")
            if voices.isEmpty {
                voices = AppSettings.fallbackVoices
            }
        }
    }

    func checkServer() async -> String {
        let client = SonusClient(baseURL: serverURL)
        do {
            try await client.health()
            await refreshEngines()
            await refreshVoices()
            return "Sonus server is reachable at \(serverURL)."
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.log("health check failed: \(message)")
            return message
        }
    }

    func clearCache() {
        AudioPlayer.clearCache()
    }

    private func setError(_ message: String) {
        playbackState = .error
        statusMessage = PlaybackState.error.rawValue
        errorMessage = message
    }

    private func showTransientError(_ message: String) {
        NotificationManager.shared.show(message: message)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    func show(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sonus Companion"
        content.body = message

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
