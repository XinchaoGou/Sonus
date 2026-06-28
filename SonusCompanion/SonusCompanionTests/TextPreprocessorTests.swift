import XCTest
@testable import SonusCompanion

final class TextPreprocessorTests: XCTestCase {
    private let paperProfile = TextRuleProfile(
        id: "paper",
        name: "Paper Reading",
        builtIn: true,
        rules: TextRuleDefaults.paperRules()
    )

    func testRulesDisabledReturnsOriginalText() {
        let input = "Hello [1] world"
        let result = TextPreprocessor.process(
            text: input,
            profile: paperProfile,
            rulesEnabled: false
        )
        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.fingerprint, TextPreprocessor.noopFingerprint)
    }

    func testEmptyEnabledRulesReturnsOriginalText() {
        let plain = TextRuleProfile(id: "plain", name: "Plain", builtIn: true, rules: [])
        let input = "Hello [1] world"
        let result = TextPreprocessor.process(
            text: input,
            profile: plain,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.fingerprint, TextPreprocessor.noopFingerprint)
    }

    func testRemovesBracketCitations() {
        let result = TextPreprocessor.process(
            text: "Recent work [1, 2] shows progress.",
            profile: paperProfile,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, "Recent work shows progress.")
        XCTAssertNotEqual(result.fingerprint, TextPreprocessor.noopFingerprint)
    }

    func testRemovesFigureAndTableReferences() {
        let result = TextPreprocessor.process(
            text: "See Fig. 3 and Table 2 for details.",
            profile: paperProfile,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, "See and for details.")
    }

    func testLiteralReplacement() {
        let profile = TextRuleProfile(
            id: "custom",
            name: "Custom",
            builtIn: false,
            rules: [
                TextRule(
                    id: "literal",
                    name: "Literal",
                    enabled: true,
                    isRegex: false,
                    pattern: "Sonus",
                    replacement: "索纳斯",
                    builtIn: false
                ),
            ]
        )
        let result = TextPreprocessor.process(
            text: "Sonus Companion",
            profile: profile,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, "索纳斯 Companion")
    }

    func testRegexCaptureGroupReplacement() {
        let profile = TextRuleProfile(
            id: "custom",
            name: "Custom",
            builtIn: false,
            rules: [
                TextRule(
                    id: "capture",
                    name: "Capture",
                    enabled: true,
                    isRegex: true,
                    pattern: #"(\d+) items"#,
                    replacement: "$1个",
                    builtIn: false
                ),
            ]
        )
        let result = TextPreprocessor.process(
            text: "We found 42 items today.",
            profile: profile,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, "We found 42个 today.")
    }

    func testSkipsInvalidRegexAndContinues() {
        var skipped: [(String, String)] = []
        let profile = TextRuleProfile(
            id: "custom",
            name: "Custom",
            builtIn: false,
            rules: [
                TextRule(
                    id: "bad",
                    name: "Bad Rule",
                    enabled: true,
                    isRegex: true,
                    pattern: "[",
                    replacement: "",
                    builtIn: false
                ),
                TextRule(
                    id: "good",
                    name: "Good Rule",
                    enabled: true,
                    isRegex: false,
                    pattern: "noise",
                    replacement: "",
                    builtIn: false
                ),
            ]
        )

        let result = TextPreprocessor.process(
            text: "remove noise please",
            profile: profile,
            rulesEnabled: true,
            onSkippedRule: { name, error in
                skipped.append((name, error))
            }
        )

        XCTAssertEqual(result.text, "remove  please")
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped[0].0, "Bad Rule")
    }

    func testFingerprintChangesWhenRuleChanges() {
        var profile = paperProfile
        let before = TextPreprocessor.fingerprint(for: profile, rulesEnabled: true)

        profile.rules[0].pattern = #"\[\d+\]"#
        let after = TextPreprocessor.fingerprint(for: profile, rulesEnabled: true)

        XCTAssertNotEqual(before, after)
    }

    func testCollapseWhitespaceRunsLast() {
        let result = TextPreprocessor.process(
            text: "Word [1]   next",
            profile: paperProfile,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, "Word next")
    }

    func testEmptyAfterRulesReturnsEmptyString() {
        let profile = TextRuleProfile(
            id: "strip-all",
            name: "Strip All",
            builtIn: false,
            rules: [
                TextRule(
                    id: "all",
                    name: "All",
                    enabled: true,
                    isRegex: false,
                    pattern: "x",
                    replacement: "",
                    builtIn: false
                ),
            ]
        )
        let result = TextPreprocessor.process(
            text: "xxx",
            profile: profile,
            rulesEnabled: true
        )
        XCTAssertEqual(result.text, "")
    }
}
