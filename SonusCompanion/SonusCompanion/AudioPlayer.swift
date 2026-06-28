import AVFoundation
import CryptoKit
import Foundation

enum AudioPlayerError: LocalizedError {
    case cacheWriteFailed
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .cacheWriteFailed:
            return "Failed to write audio cache."
        case .playbackFailed(let reason):
            return "Audio playback failed: \(reason)"
        }
    }
}

@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private static var cacheDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/SonusCompanion/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheFileURL(
        text: String,
        voice: String,
        speed: Double,
        format: String,
        rulesFingerprint: String = TextPreprocessor.noopFingerprint
    ) -> URL {
        let key = "\(text)|\(voice)|\(speed)|\(format)|\(rulesFingerprint)"
        let hash = SHA256.hash(data: Data(key.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(hex).\(format)")
    }

    static func cachedFileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func saveToCache(data: Data, url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AudioPlayerError.cacheWriteFailed
        }
    }

    static func clearCache() {
        let dir = cacheDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        AppLogger.log("cache cleared")
    }

    func play(fileURL: URL, speed: Double) throws {
        stop()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: fileURL)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = Float(speed)
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                throw AudioPlayerError.playbackFailed("AVAudioPlayer.play() returned false")
            }
            player = newPlayer
            AppLogger.log("playback started file=\(fileURL.lastPathComponent) speed=\(speed)")
        } catch let error as AudioPlayerError {
            throw error
        } catch {
            throw AudioPlayerError.playbackFailed(error.localizedDescription)
        }
    }

    func pause() {
        player?.pause()
        AppLogger.log("playback paused")
    }

    func resume(speed: Double) {
        guard let player else { return }
        player.enableRate = true
        player.rate = Float(speed)
        player.play()
        AppLogger.log("playback resumed")
    }

    func stop() {
        player?.stop()
        player = nil
        AppLogger.log("playback stopped")
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                AppLogger.log("playback finished")
                onFinished?()
            } else {
                AppLogger.log("playback finished unsuccessfully")
                onFailure?("Playback ended unexpectedly.")
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            let message = error?.localizedDescription ?? "Decode error"
            AppLogger.log("playback decode error: \(message)")
            onFailure?(message)
        }
    }
}
