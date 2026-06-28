import XCTest
@testable import Sonus

@MainActor
final class TextRuleStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonusCompanionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        configURL = tempDirectory.appendingPathComponent("text-rules.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testCreatesDefaultDocumentWhenMissing() {
        let store = TextRuleStore(configURL: configURL)
        XCTAssertTrue(store.rulesEnabled)
        XCTAssertEqual(store.activeProfileId, TextRuleDefaults.paperProfileID)
        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testImportReplacesEntireDocument() throws {
        let store = TextRuleStore(configURL: configURL)
        let importURL = tempDirectory.appendingPathComponent("import.json")
        let imported = TextRulesDocument(
            version: 1,
            rulesEnabled: false,
            activeProfileId: TextRuleDefaults.generalProfileID,
            profiles: [
                TextRuleProfile(id: TextRuleDefaults.generalProfileID, name: "General", builtIn: true, rules: []),
            ]
        )
        let data = try JSONEncoder().encode(imported)
        try data.write(to: importURL)

        try store.importDocument(from: importURL)

        XCTAssertFalse(store.rulesEnabled)
        XCTAssertEqual(store.activeProfileId, TextRuleDefaults.generalProfileID)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testRestoreBuiltInDefaultsForPaperProfile() throws {
        let store = TextRuleStore(configURL: configURL)
        guard let index = store.profiles.firstIndex(where: { $0.id == TextRuleDefaults.paperProfileID }) else {
            XCTFail("Paper profile missing")
            return
        }
        store.profiles[index].rules = []
        try store.restoreBuiltInDefaults(for: TextRuleDefaults.paperProfileID)
        XCTAssertFalse(store.profiles[index].rules.isEmpty)
    }

    func testAddCustomProfileAndDelete() throws {
        let store = TextRuleStore(configURL: configURL)
        store.addCustomProfile(name: "Research Notes")
        XCTAssertEqual(store.activeProfileId.hasPrefix("custom-"), true)
        XCTAssertTrue(store.canDeleteActiveProfile)

        let customID = store.activeProfileId
        try store.deleteProfile(id: customID)
        XCTAssertNotEqual(store.activeProfileId, customID)
        XCTAssertFalse(store.canDeleteActiveProfile)
    }

    func testMigratesLegacyPlainProfileToGeneral() throws {
        let legacy = TextRulesDocument(
            version: 1,
            rulesEnabled: true,
            activeProfileId: TextRuleDefaults.legacyPlainProfileID,
            profiles: [
                TextRuleProfile(id: TextRuleDefaults.paperProfileID, name: "Paper Reading", builtIn: true, rules: []),
                TextRuleProfile(id: TextRuleDefaults.legacyPlainProfileID, name: "Plain", builtIn: true, rules: []),
                TextRuleProfile(id: TextRuleDefaults.generalProfileID, name: "General", builtIn: true, rules: []),
            ]
        )
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: configURL)

        let store = TextRuleStore(configURL: configURL)

        XCTAssertEqual(store.activeProfileId, TextRuleDefaults.generalProfileID)
        XCTAssertFalse(store.profiles.contains { $0.id == TextRuleDefaults.legacyPlainProfileID })
        XCTAssertEqual(store.profiles.count, 2)

        let persisted = try JSONDecoder().decode(TextRulesDocument.self, from: Data(contentsOf: configURL))
        XCTAssertEqual(persisted.activeProfileId, TextRuleDefaults.generalProfileID)
        XCTAssertFalse(persisted.profiles.contains { $0.id == TextRuleDefaults.legacyPlainProfileID })
    }

    func testCannotDeleteBuiltInProfile() {
        let store = TextRuleStore(configURL: configURL)
        store.setActiveProfile(id: TextRuleDefaults.generalProfileID)
        XCTAssertFalse(store.canDeleteActiveProfile)
    }

    func testMoveRuleDownSwapsWithNextItem() throws {
        let store = try makeReorderStore()
        guard let profileIndex = activeProfileIndex(in: store) else {
            XCTFail("Active profile missing")
            return
        }

        store.moveRule(from: 2, to: 3)

        XCTAssertEqual(
            store.profiles[profileIndex].rules.map(\.id),
            ["rule-0", "rule-1", "rule-3", "rule-2", "rule-4"]
        )
    }

    func testMoveRuleUpSwapsWithPreviousItem() throws {
        let store = try makeReorderStore()
        guard let profileIndex = activeProfileIndex(in: store) else {
            XCTFail("Active profile missing")
            return
        }

        store.moveRule(from: 3, to: 2)

        XCTAssertEqual(
            store.profiles[profileIndex].rules.map(\.id),
            ["rule-0", "rule-1", "rule-3", "rule-2", "rule-4"]
        )
    }

    func testMoveRulesDownUsesPostRemovalToOffset() throws {
        let store = try makeReorderStore()
        guard let profileIndex = activeProfileIndex(in: store) else {
            XCTFail("Active profile missing")
            return
        }

        // Settings UI offset for "move down one": index + direction + 1
        store.moveRules(from: IndexSet(integer: 2), to: 4)

        XCTAssertEqual(
            store.profiles[profileIndex].rules.map(\.id),
            ["rule-0", "rule-1", "rule-3", "rule-2", "rule-4"]
        )
    }

    func testMoveRulesDownWithWrongOffsetIsNoOp() throws {
        let store = try makeReorderStore()
        guard let profileIndex = activeProfileIndex(in: store) else {
            XCTFail("Active profile missing")
            return
        }

        // Using index + direction (3) as toOffset does nothing for a single-element move.
        store.moveRules(from: IndexSet(integer: 2), to: 3)

        XCTAssertEqual(
            store.profiles[profileIndex].rules.map(\.id),
            ["rule-0", "rule-1", "rule-2", "rule-3", "rule-4"]
        )
    }

    func testMoveRuleRemoveInsertWithOverShotDestinationMovesToEnd() throws {
        let store = try makeReorderStore()
        guard let profileIndex = activeProfileIndex(in: store) else {
            XCTFail("Active profile missing")
            return
        }

        // Naive remove-then-insert at source + 2 overshoots adjacent swap and appends.
        store.moveRule(from: 2, to: 4)

        XCTAssertEqual(
            store.profiles[profileIndex].rules.map(\.id),
            ["rule-0", "rule-1", "rule-3", "rule-4", "rule-2"]
        )
    }

    private func makeReorderStore() throws -> TextRuleStore {
        let store = TextRuleStore(configURL: configURL)
        store.addCustomProfile(name: "Reorder Test")
        store.setActiveProfile(id: store.activeProfileId)

        guard let profileIndex = activeProfileIndex(in: store) else {
            throw NSError(domain: "TextRuleStoreTests", code: 1)
        }

        store.profiles[profileIndex].rules = (0..<5).map {
            TextRule(
                id: "rule-\($0)",
                name: "rule-\($0)",
                enabled: true,
                isRegex: false,
                pattern: "",
                replacement: "",
                builtIn: false
            )
        }
        return store
    }

    private func activeProfileIndex(in store: TextRuleStore) -> Int? {
        store.profiles.firstIndex(where: { $0.id == store.activeProfileId })
    }
}
