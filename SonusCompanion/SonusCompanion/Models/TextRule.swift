import Foundation

struct TextRule: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var enabled: Bool
    var isRegex: Bool
    var pattern: String
    var replacement: String
    var builtIn: Bool
}

struct TextRuleProfile: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var builtIn: Bool
    var rules: [TextRule]
}

struct TextRulesDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var rulesEnabled: Bool
    var activeProfileId: String
    var profiles: [TextRuleProfile]

    static func defaults() -> TextRulesDocument {
        TextRulesDocument(
            version: currentVersion,
            rulesEnabled: true,
            activeProfileId: TextRuleDefaults.paperProfileID,
            profiles: TextRuleDefaults.builtInProfiles()
        )
    }
}

enum TextRuleDefaults {
    static let paperProfileID = "paper"
    static let plainProfileID = "plain"
    static let generalProfileID = "general"

    static func builtInProfiles() -> [TextRuleProfile] {
        [
            TextRuleProfile(
                id: paperProfileID,
                name: "Paper Reading",
                builtIn: true,
                rules: paperRules()
            ),
            TextRuleProfile(
                id: plainProfileID,
                name: "Plain",
                builtIn: true,
                rules: []
            ),
            TextRuleProfile(
                id: generalProfileID,
                name: "General",
                builtIn: true,
                rules: []
            ),
        ]
    }

    static func paperRules() -> [TextRule] {
        [
            TextRule(
                id: "bracket-citations",
                name: "Bracket citations",
                enabled: true,
                isRegex: true,
                pattern: #"\[\d+(?:,\s*\d+)*\]"#,
                replacement: "",
                builtIn: true
            ),
            TextRule(
                id: "superscript-citations",
                name: "Superscript citations",
                enabled: true,
                isRegex: true,
                pattern: #"\^\d+"#,
                replacement: "",
                builtIn: true
            ),
            TextRule(
                id: "author-year",
                name: "Author-year parenthetical",
                enabled: true,
                isRegex: true,
                pattern: #"\([A-Z][A-Za-z\-]+(?:\s+et\s+al\.)?,\s*\d{4}[a-z]?\)"#,
                replacement: "",
                builtIn: true
            ),
            TextRule(
                id: "et-al",
                name: "et al.",
                enabled: false,
                isRegex: true,
                pattern: #"\bet\s+al\."#,
                replacement: "等人",
                builtIn: true
            ),
            TextRule(
                id: "figure-ref",
                name: "Figure reference",
                enabled: true,
                isRegex: true,
                pattern: #"\bFig(?:ure)?\.?\s*\d+[a-z]?"#,
                replacement: "",
                builtIn: true
            ),
            TextRule(
                id: "table-ref",
                name: "Table reference",
                enabled: true,
                isRegex: true,
                pattern: #"\bTab(?:le)?\.?\s*\d+"#,
                replacement: "",
                builtIn: true
            ),
            TextRule(
                id: "collapse-space",
                name: "Collapse whitespace",
                enabled: true,
                isRegex: true,
                pattern: #"\s{2,}"#,
                replacement: " ",
                builtIn: true
            ),
        ]
    }

    static func paperRules(for profileID: String) -> [TextRule]? {
        guard profileID == paperProfileID else { return nil }
        return paperRules()
    }
}
