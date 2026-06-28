import Foundation
import Observation

enum TextRuleStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidDocument(String)
    case profileNotFound(String)
    case cannotDeleteBuiltInProfile
    case cannotDeleteLastProfile

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported text rules version: \(version)."
        case .invalidDocument(let reason):
            return "Invalid text rules file: \(reason)"
        case .profileNotFound(let id):
            return "Profile not found: \(id)"
        case .cannotDeleteBuiltInProfile:
            return "Built-in profiles cannot be deleted."
        case .cannotDeleteLastProfile:
            return "At least one profile must remain."
        }
    }
}

@MainActor
@Observable
final class TextRuleStore {
    var rulesEnabled: Bool
    var activeProfileId: String
    var profiles: [TextRuleProfile]

    var activeProfile: TextRuleProfile {
        profiles.first(where: { $0.id == activeProfileId }) ?? profiles[0]
    }

    var activeProfileName: String {
        activeProfile.name
    }

    var statusSummary: String {
        rulesEnabled ? "On · \(activeProfile.name)" : "Off"
    }

    var canDeleteActiveProfile: Bool {
        guard profiles.count > 1,
              let active = profiles.first(where: { $0.id == activeProfileId }) else {
            return false
        }
        return !active.builtIn
    }

    private let fileManager: FileManager
    private let configURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, configURL: URL? = nil) {
        self.fileManager = fileManager
        if let configURL {
            self.configURL = configURL
            let supportDir = configURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)
        } else {
            let supportDir = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/SonusCompanion", isDirectory: true)
            try? fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)
            self.configURL = supportDir.appendingPathComponent("text-rules.json")
        }

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        let loaded = Self.loadDocument(from: self.configURL, decoder: decoder, fileManager: fileManager)
        rulesEnabled = loaded.rulesEnabled
        activeProfileId = loaded.activeProfileId
        profiles = loaded.profiles
    }

    func save() {
        let document = TextRulesDocument(
            version: TextRulesDocument.currentVersion,
            rulesEnabled: rulesEnabled,
            activeProfileId: activeProfileId,
            profiles: profiles
        )
        do {
            let data = try encoder.encode(document)
            try data.write(to: configURL, options: .atomic)
        } catch {
            AppLogger.log("text rules save failed: \(error.localizedDescription)")
        }
    }

    func setRulesEnabled(_ enabled: Bool) {
        rulesEnabled = enabled
        save()
    }

    func setActiveProfile(id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        save()
    }

    func updateActiveProfile(_ profile: TextRuleProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        save()
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        var profile = profiles[index]
        profile.rules.move(fromOffsets: source, toOffset: destination)
        profiles[index] = profile
        save()
    }

    func moveRule(from sourceIndex: Int, to destinationIndex: Int) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        var profile = profiles[profileIndex]
        guard sourceIndex >= 0,
              sourceIndex < profile.rules.count,
              destinationIndex >= 0,
              destinationIndex < profile.rules.count,
              sourceIndex != destinationIndex else { return }

        if abs(destinationIndex - sourceIndex) == 1 {
            profile.rules.swapAt(sourceIndex, destinationIndex)
        } else {
            let rule = profile.rules.remove(at: sourceIndex)
            // destinationIndex is the rule's desired final index in the original array.
            profile.rules.insert(rule, at: destinationIndex)
        }
        profiles[profileIndex] = profile
        save()
    }

    func deleteRules(at offsets: IndexSet) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        var profile = profiles[index]
        profile.rules.remove(atOffsets: offsets)
        profiles[index] = profile
        save()
    }

    func addRule() {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        var profile = profiles[index]
        let rule = TextRule(
            id: UUID().uuidString,
            name: "New Rule",
            enabled: true,
            isRegex: false,
            pattern: "",
            replacement: "",
            builtIn: false
        )
        profile.rules.append(rule)
        profiles[index] = profile
        save()
    }

    func restoreBuiltInDefaults(for profileID: String) throws {
        guard let defaults = TextRuleDefaults.paperRules(for: profileID) else {
            throw TextRuleStoreError.invalidDocument("Only Paper profile has built-in defaults.")
        }
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw TextRuleStoreError.profileNotFound(profileID)
        }
        var profile = profiles[index]
        profile.rules = defaults
        profiles[index] = profile
        save()
    }

    func addCustomProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        let profile = TextRuleProfile(id: id, name: trimmed, builtIn: false, rules: [])
        profiles.append(profile)
        activeProfileId = id
        save()
    }

    func deleteProfile(id: String) throws {
        guard profiles.count > 1 else {
            throw TextRuleStoreError.cannotDeleteLastProfile
        }
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw TextRuleStoreError.profileNotFound(id)
        }
        guard !profile.builtIn else {
            throw TextRuleStoreError.cannotDeleteBuiltInProfile
        }
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles[0].id
        }
        save()
    }

    func exportDocument(to url: URL) throws {
        let document = TextRulesDocument(
            version: TextRulesDocument.currentVersion,
            rulesEnabled: rulesEnabled,
            activeProfileId: activeProfileId,
            profiles: profiles
        )
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    /// Replaces the entire in-memory document with imported JSON (full file replace).
    func importDocument(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let document = try decoder.decode(TextRulesDocument.self, from: data)
        try validate(document)
        rulesEnabled = document.rulesEnabled
        activeProfileId = document.activeProfileId
        profiles = document.profiles
        save()
    }

    private func validate(_ document: TextRulesDocument) throws {
        guard document.version == TextRulesDocument.currentVersion else {
            throw TextRuleStoreError.unsupportedVersion(document.version)
        }
        guard !document.profiles.isEmpty else {
            throw TextRuleStoreError.invalidDocument("profiles must not be empty")
        }
        guard document.profiles.contains(where: { $0.id == document.activeProfileId }) else {
            throw TextRuleStoreError.invalidDocument("activeProfileId not found in profiles")
        }
    }

    private static func loadDocument(
        from url: URL,
        decoder: JSONDecoder,
        fileManager: FileManager
    ) -> TextRulesDocument {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let document = try? decoder.decode(TextRulesDocument.self, from: data),
              document.version == TextRulesDocument.currentVersion,
              !document.profiles.isEmpty,
              document.profiles.contains(where: { $0.id == document.activeProfileId }) else {
            let defaults = TextRulesDocument.defaults()
            try? writeDefaults(defaults, to: url, fileManager: fileManager)
            return defaults
        }
        return migrate(document, url: url, fileManager: fileManager)
    }

    private static func migrate(
        _ document: TextRulesDocument,
        url: URL,
        fileManager: FileManager
    ) -> TextRulesDocument {
        var profiles = document.profiles.filter { $0.id != TextRuleDefaults.legacyPlainProfileID }
        let existingIDs = Set(profiles.map(\.id))

        for builtIn in TextRuleDefaults.builtInProfiles() where !existingIDs.contains(builtIn.id) {
            profiles.append(builtIn)
        }

        var activeProfileId = document.activeProfileId
        if activeProfileId == TextRuleDefaults.legacyPlainProfileID {
            activeProfileId = TextRuleDefaults.generalProfileID
        }
        if !profiles.contains(where: { $0.id == activeProfileId }) {
            activeProfileId = TextRuleDefaults.paperProfileID
        }

        let migrated = TextRulesDocument(
            version: document.version,
            rulesEnabled: document.rulesEnabled,
            activeProfileId: activeProfileId,
            profiles: profiles
        )
        if migrated != document {
            try? writeDefaults(migrated, to: url, fileManager: fileManager)
        }
        return migrated
    }

    private static func writeDefaults(
        _ document: TextRulesDocument,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }
}
