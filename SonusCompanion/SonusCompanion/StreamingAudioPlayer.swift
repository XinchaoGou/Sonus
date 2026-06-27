import AVFoundation
import Foundation

enum StreamingAudioPlayerError: LocalizedError {
    case engineStartFailed(String)
    case invalidPCM

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let reason):
            return "Streaming playback failed: \(reason)"
        case .invalidPCM:
            return "Invalid PCM audio data."
        }
    }
}

/// Plays 16-bit mono PCM chunks (24 kHz) from POST /tts/stream as they arrive.
@MainActor
final class StreamingAudioPlayer {
    static let sampleRate: Double = 24_000

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var pcmFormat: AVAudioFormat?
    private var isActive = false
    private var scheduledBuffers = 0
    private var streamEnded = false
    private var didEmitFirstBuffer = false
    private var playbackSpeed: Float = 1.0

    private(set) var accumulatedPCM = Data()

    var onFirstBuffer: (() -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?

    func start(speed: Double) throws {
        stop()
        accumulatedPCM = Data()
        scheduledBuffers = 0
        streamEnded = false
        didEmitFirstBuffer = false
        playbackSpeed = Float(speed)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw StreamingAudioPlayerError.engineStartFailed("Unsupported PCM format")
        }

        pcmFormat = format
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.rate = playbackSpeed
            playerNode.play()
            isActive = true
            AppLogger.log("stream playback engine started speed=\(speed)")
        } catch {
            engine.detach(playerNode)
            throw StreamingAudioPlayerError.engineStartFailed(error.localizedDescription)
        }
    }

    func appendPCM(_ data: Data) {
        guard isActive, let pcmFormat, !data.isEmpty else { return }

        accumulatedPCM.append(data)

        if !didEmitFirstBuffer {
            didEmitFirstBuffer = true
            onFirstBuffer?()
        }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let channel = buffer.int16ChannelData?[0] else { return }
            memcpy(channel, base, data.count)
        }

        scheduledBuffers += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.bufferDidComplete()
            }
        }
    }

    func finishStream() {
        streamEnded = true
        if accumulatedPCM.isEmpty {
            onFailure?("Sonus returned empty audio stream.")
            stop()
            return
        }
        checkCompletion()
    }

    func pause() {
        guard isActive else { return }
        playerNode.pause()
        AppLogger.log("stream playback paused")
    }

    func resume(speed: Double) {
        guard isActive else { return }
        playbackSpeed = Float(speed)
        playerNode.rate = playbackSpeed
        playerNode.play()
        AppLogger.log("stream playback resumed")
    }

    func setRate(speed: Double) {
        playbackSpeed = Float(speed)
        playerNode.rate = playbackSpeed
    }

    func stop() {
        guard isActive else { return }
        playerNode.stop()
        engine.stop()
        engine.detach(playerNode)
        isActive = false
        scheduledBuffers = 0
        streamEnded = false
        didEmitFirstBuffer = false
        pcmFormat = nil
        AppLogger.log("stream playback stopped")
    }

    var isRunning: Bool { isActive }

    private func bufferDidComplete() {
        scheduledBuffers = max(0, scheduledBuffers - 1)
        checkCompletion()
    }

    private func checkCompletion() {
        guard streamEnded, scheduledBuffers == 0, isActive else { return }
        AppLogger.log("stream playback finished bytes=\(accumulatedPCM.count)")
        let finished = onFinished
        stop()
        finished?()
    }
}

enum WAVEncoder {
    static func wrapPCM(_ pcm: Data, sampleRate: UInt32 = 24_000, channels: UInt16 = 1, bitsPerSample: UInt16 = 16) -> Data {
        var data = Data()
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcm.count)
        let riffSize = 36 + dataSize

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        appendUInt32(riffSize, to: &data)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(channels, to: &data)
        appendUInt32(sampleRate, to: &data)
        appendUInt32(byteRate, to: &data)
        appendUInt16(blockAlign, to: &data)
        appendUInt16(bitsPerSample, to: &data)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        appendUInt32(dataSize, to: &data)
        data.append(pcm)
        return data
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { raw in
            data.append(contentsOf: raw)
        }
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { raw in
            data.append(contentsOf: raw)
        }
    }
}
