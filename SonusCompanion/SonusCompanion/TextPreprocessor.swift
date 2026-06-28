import CryptoKit
import Foundation

enum TextPreprocessor {
    static let noopFingerprint = "noop"

    struct Result: Equatable, Sendable {
        let text: String
        let fingerprint: String
    }

    static func fingerprint(for profile: TextRuleProfile, rulesEnabled: Bool) -> String {
        guard rulesEnabled else { return noopFingerprint }
        let enabledRules = profile.rules.filter(\.enabled)
        guard !enabledRules.isEmpty else { return noopFingerprint }
        return digest(enabledRules: enabledRules)
    }

    static func process(
        text: String,
        profile: TextRuleProfile,
        rulesEnabled: Bool,
        onSkippedRule: ((String, String) -> Void)? = nil
    ) -> Result {
        guard rulesEnabled else {
            return Result(text: text, fingerprint: noopFingerprint)
        }

        let enabledRules = profile.rules.filter(\.enabled)
        guard !enabledRules.isEmpty else {
            return Result(text: text, fingerprint: noopFingerprint)
        }

        var current = text
        for rule in enabledRules {
            guard !rule.pattern.isEmpty else { continue }
            do {
                if rule.isRegex {
                    current = try applyRegexRule(current, rule: rule)
                } else {
                    current = current.replacingOccurrences(of: rule.pattern, with: rule.replacement)
                }
            } catch {
                onSkippedRule?(rule.name, error.localizedDescription)
            }
        }

        return Result(
            text: current.trimmingCharacters(in: .whitespacesAndNewlines),
            fingerprint: digest(enabledRules: enabledRules)
        )
    }

    static func preview(
        text: String,
        profile: TextRuleProfile,
        rulesEnabled: Bool
    ) -> String {
        process(text: text, profile: profile, rulesEnabled: rulesEnabled).text
    }

    private static func digest(enabledRules: [TextRule]) -> String {
        let payload = enabledRules
            .map { "\($0.id)|\($0.pattern)|\($0.replacement)|\($0.isRegex)" }
            .joined(separator: "\n")
        let hash = SHA256.hash(data: Data(payload.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func applyRegexRule(_ text: String, rule: TextRule) throws -> String {
        let regex = try NSRegularExpression(pattern: rule.pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: rule.replacement
        )
    }
}