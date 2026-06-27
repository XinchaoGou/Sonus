import Foundation

/// Phase 2 placeholder for macOS System Voice integration via
/// AVSpeechSynthesisProviderVoice / AVSpeechSynthesisProviderAudioUnit.
enum SonusSystemVoiceInstaller {
    static let isAvailable = false

    static func install() async throws {
        throw InstallError.notImplemented
    }

    enum InstallError: LocalizedError {
        case notImplemented

        var errorDescription: String? {
            "System Voice installation is not available yet. See docs/SYSTEM_VOICE_RESEARCH.md."
        }
    }
}
