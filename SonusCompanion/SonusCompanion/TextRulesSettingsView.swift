import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TextRulesSettingsView: View {
    @Bindable var store: TextRuleStore
    @Binding var lastSelection: String?

    @State private var sampleText = ""
    @State private var importExportMessage: String?
    @State private var importExportIsError = false
    @State private var newProfileName = ""
    @State private var showAddProfile = false
    @State private var isEditingRules = false
    @Environment(\.dismiss) private var dismiss

    private var previewText: String {
        TextPreprocessor.preview(
            text: sampleText,
            profile: store.activeProfile,
            rulesEnabled: store.rulesEnabled
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Enable text rules", isOn: $store.rulesEnabled)
                        .onChange(of: store.rulesEnabled) { _, _ in
                            store.save()
                        }

                    Picker("Active profile", selection: $store.activeProfileId) {
                        ForEach(store.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .onChange(of: store.activeProfileId) { _, _ in
                        store.save()
                    }

                    HStack {
                        Button("Add Profile…") {
                            showAddProfile = true
                        }
                        if let active = store.profiles.first(where: { $0.id == store.activeProfileId }),
                           !active.builtIn {
                            Button("Delete Profile", role: .destructive) {
                                deleteActiveCustomProfile()
                            }
                        }
                    }
                }

                Section("Rules") {
                    if store.activeProfile.rules.isEmpty {
                        Text("No rules in this profile.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeRuleIndices, id: \.self) { index in
                            ruleEditor(at: index)
                        }
                    }

                    HStack {
                        Button("Add Rule") {
                            store.addRule()
                        }
                        if store.activeProfile.builtIn {
                            Button("Restore Built-in Defaults") {
                                restoreDefaults()
                            }
                        }
                        if !store.activeProfile.rules.isEmpty {
                            Button(isEditingRules ? "Done Editing" : "Edit Order") {
                                isEditingRules.toggle()
                            }
                        }
                    }
                }

                Section("Preview") {
                    TextEditor(text: $sampleText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80, maxHeight: 120)

                    HStack {
                        Button("Use Last Selection") {
                            if let lastSelection {
                                sampleText = lastSelection
                            }
                        }
                        .disabled(lastSelection == nil || lastSelection?.isEmpty == true)
                        Button("Preview") {}
                            .hidden()
                    }

                    LabeledContent("Result") {
                        Text(previewText.isEmpty ? "—" : previewText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("Import / Export") {
                    HStack {
                        Button("Import…") {
                            importRules()
                        }
                        Button("Export…") {
                            exportRules()
                        }
                    }
                    Text("Import replaces the entire rules file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let importExportMessage {
                        Text(importExportMessage)
                            .font(.caption)
                            .foregroundStyle(importExportIsError ? .red : .secondary)
                            .lineLimit(3)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Text Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("New Profile", isPresented: $showAddProfile) {
                TextField("Profile name", text: $newProfileName)
                Button("Cancel", role: .cancel) {
                    newProfileName = ""
                }
                Button("Add") {
                    store.addCustomProfile(name: newProfileName)
                    newProfileName = ""
                }
            } message: {
                Text("Create a custom profile with no rules.")
            }
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    private var activeRuleIndices: [Int] {
        guard let index = store.profiles.firstIndex(where: { $0.id == store.activeProfileId }) else {
            return []
        }
        return store.profiles[index].rules.indices.map { $0 }
    }

    @ViewBuilder
    private func ruleEditor(at ruleIndex: Int) -> some View {
        if let profileIndex = store.profiles.firstIndex(where: { $0.id == store.activeProfileId }) {
            let rule = store.profiles[profileIndex].rules[ruleIndex]

            DisclosureGroup {
                TextField("Name", text: ruleBinding(profileIndex: profileIndex, ruleIndex: ruleIndex, keyPath: \.name))
                TextField("Pattern", text: ruleBinding(profileIndex: profileIndex, ruleIndex: ruleIndex, keyPath: \.pattern))
                    .font(.body.monospaced())
                TextField("Replacement", text: ruleBinding(profileIndex: profileIndex, ruleIndex: ruleIndex, keyPath: \.replacement))
                    .font(.body.monospaced())
                Toggle("Regular expression", isOn: ruleBinding(profileIndex: profileIndex, ruleIndex: ruleIndex, keyPath: \.isRegex))
                Toggle("Enabled", isOn: ruleBinding(profileIndex: profileIndex, ruleIndex: ruleIndex, keyPath: \.enabled))
                if isEditingRules {
                    HStack {
                        Button("Move Up") {
                            moveRule(at: ruleIndex, direction: -1)
                        }
                        .disabled(ruleIndex == 0)
                        Button("Move Down") {
                            moveRule(at: ruleIndex, direction: 1)
                        }
                        .disabled(ruleIndex >= store.profiles[profileIndex].rules.count - 1)
                        if !rule.builtIn {
                            Button("Delete", role: .destructive) {
                                store.deleteRules(at: IndexSet(integer: ruleIndex))
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Toggle("", isOn: ruleBinding(profileIndex: profileIndex, ruleIndex: ruleIndex, keyPath: \.enabled))
                        .labelsHidden()
                    Text(rule.name)
                    if rule.builtIn {
                        Text("built-in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func moveRule(at index: Int, direction: Int) {
        // Swift Collection.move(toOffset:) inserts before the offset in the post-removal
        // array. Moving down one row requires toOffset = index + 2, not index + 1.
        let toOffset = direction > 0 ? index + direction + 1 : index + direction
        store.moveRules(from: IndexSet(integer: index), to: toOffset)
    }

    private func ruleBinding<T>(
        profileIndex: Int,
        ruleIndex: Int,
        keyPath: WritableKeyPath<TextRule, T>
    ) -> Binding<T> {
        Binding(
            get: { store.profiles[profileIndex].rules[ruleIndex][keyPath: keyPath] },
            set: { newValue in
                store.profiles[profileIndex].rules[ruleIndex][keyPath: keyPath] = newValue
                store.save()
            }
        )
    }

    private func restoreDefaults() {
        do {
            try store.restoreBuiltInDefaults(for: store.activeProfileId)
            importExportMessage = "Built-in defaults restored."
            importExportIsError = false
        } catch {
            importExportMessage = error.localizedDescription
            importExportIsError = true
        }
    }

    private func deleteActiveCustomProfile() {
        do {
            try store.deleteProfile(id: store.activeProfileId)
            importExportMessage = "Profile deleted."
            importExportIsError = false
        } catch {
            importExportMessage = error.localizedDescription
            importExportIsError = true
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "text-rules.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportDocument(to: url)
            importExportMessage = "Exported to \(url.lastPathComponent)."
            importExportIsError = false
        } catch {
            importExportMessage = error.localizedDescription
            importExportIsError = true
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importDocument(from: url)
            importExportMessage = "Imported from \(url.lastPathComponent)."
            importExportIsError = false
        } catch {
            importExportMessage = error.localizedDescription
            importExportIsError = true
        }
    }
}
