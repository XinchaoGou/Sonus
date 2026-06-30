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
    let engine: String?
    let modelsReady: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case engine
        case modelsReady = "models_ready"
    }
}

struct EngineStatusResponse: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let active: Bool
    let installed: Bool
    let ready: Bool
    let missingModels: [String]
    let optionalDependency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case active
        case installed
        case ready
        case missingModels = "missing_models"
        case optionalDependency = "optional_dependency"
    }
}

struct SetActiveEngineRequest: Encodable, Sendable {
    let engine: String
}

struct SetActiveEngineResponse: Decodable, Sendable {
    let engine: String
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
