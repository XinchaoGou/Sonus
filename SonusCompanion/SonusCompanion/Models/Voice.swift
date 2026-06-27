import Foundation

struct Voice: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let language: String

    static func fromLogical(id: String, entry: LogicalVoiceEntry) -> Voice {
        Voice(id: id, name: friendlyName(for: id, lang: entry.lang), language: entry.lang)
    }

    private static func friendlyName(for id: String, lang: String) -> String {
        switch id {
        case "zh_female": return "中文女声"
        case "zh_male": return "中文男声"
        case "en_female": return "English Female"
        case "en_male": return "English Male"
        case "ja_female": return "日本語女声"
        default:
            return "\(id) (\(lang))"
        }
    }
}
