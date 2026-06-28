import AppKit
import ApplicationServices
import Foundation

enum SelectedTextError: LocalizedError {
    case noText
    case accessibilityDenied
    case clipboardFallbackFailed

    var errorDescription: String? {
        switch self {
        case .noText:
            return "No selected text found. Please select text first."
        case .accessibilityDenied:
            return "Accessibility permission is required for reading selected text."
        case .clipboardFallbackFailed:
            return "Clipboard fallback failed to capture selected text."
        }
    }
}

struct SelectedTextReader {
    var clipboardFallbackEnabled: Bool

    func readSelectedText() -> Result<String, SelectedTextError> {
        if let text = readViaAccessibility(), !text.isEmpty {
            AppLogger.log("selected text via accessibility length=\(text.count)")
            return .success(text)
        }

        if clipboardFallbackEnabled {
            switch readViaClipboardFallback() {
            case .success(let text) where !text.isEmpty:
                AppLogger.log("selected text via clipboard fallback length=\(text.count)")
                return .success(text)
            case .success:
                break
            case .failure(let error):
                AppLogger.log("clipboard fallback error: \(error.localizedDescription)")
                return .failure(error)
            }
        }

        AppLogger.log("no selected text found")
        return .failure(.noText)
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func readViaAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appResult == .success, let appElement = focusedApp else { return nil }

        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(appElement as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard elementResult == .success, let element = focusedElement else { return nil }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textResult == .success, let text = selectedText as? String else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readViaClipboardFallback() -> Result<String, SelectedTextError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        guard simulateCopyCommand() else {
            snapshot.restore(to: pasteboard)
            return .failure(.clipboardFallbackFailed)
        }

        Thread.sleep(forTimeInterval: 0.15)

        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        snapshot.restore(to: pasteboard)

        if copied.isEmpty {
            return .failure(.noText)
        }
        return .success(copied)
    }

    private func simulateCopyCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            return false
        }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)

        return true
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                var dict: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        dict[type] = data
                    }
                }
                if !dict.isEmpty {
                    captured.append(dict)
                }
            }
        }
        return PasteboardSnapshot(items: captured)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        var pbItems: [NSPasteboardItem] = []
        for item in items {
            let pbItem = NSPasteboardItem()
            for (type, data) in item {
                pbItem.setData(data, forType: type)
            }
            pbItems.append(pbItem)
        }
        pasteboard.writeObjects(pbItems)
    }
}
