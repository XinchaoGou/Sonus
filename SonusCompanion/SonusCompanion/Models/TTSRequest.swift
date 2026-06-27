import Foundation

struct TTSRequest: Encodable, Sendable {
    let text: String
    let voice: String
    let speed: Double
    let format: String

    enum CodingKeys: String, CodingKey {
        case text
        case voice
        case speed
        case format
    }
}

struct TTSStreamRequest: Encodable, Sendable {
    let text: String
    let voice: String
    let speed: Double
}

struct HealthResponse: Decodable, Sendable {
    let status: String
}

struct VoicesAPIResponse: Decodable, Sendable {
    let engine: String
    let logical: [String: LogicalVoiceEntry]
    let native: [String]?
}

struct LogicalVoiceEntry: Decodable, Sendable {
    let engineVoice: String
    let lang: String

    enum CodingKeys: String, CodingKey {
        case engineVoice = "engine_voice"
        case lang
    }
}

struct APIErrorResponse: Decodable, Sendable {
    let detail: String?
}
