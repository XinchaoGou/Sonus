import AppKit
import Carbon
import XCTest
@testable import Sonus

final class HotkeyConfigurationTests: XCTestCase {
    // MARK: - Display names

    func testDefaultConfigurationDisplayName() {
        XCTAssertEqual(HotkeyConfiguration.default.displayName, "⌘Esc")
    }

    func testLegacyDefaultConfigurationDisplayName() {
        XCTAssertEqual(HotkeyConfiguration.legacyDefault.displayName, "⌥Esc")
    }

    func testDisplayNameAllModifiers() {
        let config = HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(config.displayName, "⌃⌥⇧⌘A")
    }

    func testDisplayNameSpecialKeys() {
        XCTAssertEqual(
            HotkeyConfiguration(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey)).displayName,
            "⌘Space"
        )
        XCTAssertEqual(
            HotkeyConfiguration(keyCode: UInt32(kVK_Return), carbonModifiers: UInt32(cmdKey)).displayName,
            "⌘Return"
        )
        XCTAssertEqual(
            HotkeyConfiguration(keyCode: UInt32(kVK_Tab), carbonModifiers: UInt32(cmdKey)).displayName,
            "⌘Tab"
        )
    }

    func testDisplayNameUnknownKeyCode() {
        let config = HotkeyConfiguration(keyCode: 999, carbonModifiers: UInt32(cmdKey))
        XCTAssertEqual(config.displayName, "⌘Key 999")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = HotkeyConfiguration(
            keyCode: UInt32(kVK_Escape),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Modifier key filtering

    func testModifierKeyCodesAreIgnored() {
        let modifierCodes = [
            kVK_Command, kVK_RightCommand,
            kVK_Shift, kVK_RightShift,
            kVK_Option, kVK_RightOption,
            kVK_Control, kVK_RightControl,
            kVK_CapsLock, kVK_Function,
        ]
        for code in modifierCodes {
            XCTAssertTrue(
                HotkeyConfiguration.isModifierKeyCode(UInt32(code)),
                "Expected modifier for keyCode \(code)"
            )
        }
        XCTAssertFalse(HotkeyConfiguration.isModifierKeyCode(UInt32(kVK_Escape)))
        XCTAssertFalse(HotkeyConfiguration.isModifierKeyCode(UInt32(kVK_ANSI_C)))
        XCTAssertFalse(HotkeyConfiguration.isModifierKeyCode(UInt32(kVK_Space)))
    }

    // MARK: - Carbon modifiers

    func testCarbonModifiersSingleModifiers() {
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: [.command]), UInt32(cmdKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: [.option]), UInt32(optionKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: [.control]), UInt32(controlKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: [.shift]), UInt32(shiftKey))
    }

    func testCarbonModifiersCombined() {
        let mods = HotkeyConfiguration.carbonModifiers(from: [.command, .option, .shift, .control])
        XCTAssertEqual(mods, UInt32(cmdKey | optionKey | shiftKey | controlKey))
    }

    func testCarbonModifiersIgnoresCapsLockAndFunctionFlags() {
        let mods = HotkeyConfiguration.carbonModifiers(from: [.command, .capsLock, .function])
        XCTAssertEqual(mods, UInt32(cmdKey))
    }

    // MARK: - Capture rejection

    func testCapturedRejectsUnmodifiedKeys() {
        for keyCode in [kVK_Escape, kVK_ANSI_A, kVK_Space] {
            let event = makeKeyEvent(
                keyCode: keyCode,
                modifierFlags: [],
                charactersIgnoringModifiers: keyCode == kVK_ANSI_A ? "a" : ""
            )
            XCTAssertNil(HotkeyConfiguration.captured(from: event), "Expected reject for key \(keyCode) without modifiers")
        }
    }

    func testCapturedRejectsModifierOnlyPresses() {
        let modifierOnlyCodes = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_Option, kVK_Control, kVK_Function]
        for keyCode in modifierOnlyCodes {
            let event = makeKeyEvent(keyCode: keyCode, modifierFlags: [.command])
            XCTAssertNil(HotkeyConfiguration.captured(from: event), "Expected reject for modifier key \(keyCode)")
        }
    }

    // MARK: - Capture acceptance

    func testCapturedAcceptsCommandEscapeFromKeyEvent() {
        let event = makeKeyEvent(
            keyCode: kVK_Escape,
            modifierFlags: [.command],
            charactersIgnoringModifiers: "\u{1b}"
        )
        assertCaptured(event, keyCode: kVK_Escape, carbonModifiers: cmdKey, displayName: "⌘Esc")
    }

    func testCapturedAcceptsLegacyOptionEscape() {
        let event = makeKeyEvent(
            keyCode: kVK_Escape,
            modifierFlags: [.option],
            charactersIgnoringModifiers: "\u{1b}"
        )
        assertCaptured(event, keyCode: kVK_Escape, carbonModifiers: optionKey, displayName: "⌥Esc")
    }

    func testCapturedAcceptsCommandLetterKeys() {
        for keyCode in [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_Z] {
            let event = makeKeyEvent(
                keyCode: keyCode,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "x"
            )
            XCTAssertNotNil(HotkeyConfiguration.captured(from: event))
            XCTAssertEqual(HotkeyConfiguration.captured(from: event)?.keyCode, UInt32(keyCode))
        }
    }

    func testCapturedAcceptsMultiModifierCombinations() {
        let event = makeKeyEvent(
            keyCode: kVK_Escape,
            modifierFlags: [.command, .shift],
            charactersIgnoringModifiers: "\u{1b}"
        )
        assertCaptured(event, keyCode: kVK_Escape, carbonModifiers: cmdKey | shiftKey, displayName: "⇧⌘Esc")
    }

    // MARK: - CGEvent path (local monitor bug regression)

    func testResolvedKeyCodePrefersCGEventOverWrongNSEventKeyCode() {
        let cgEvent = makeCGEscapeKeyEvent(down: true, flags: .maskCommand)
        let resolved = HotkeyConfiguration.resolvedKeyCode(
            fallbackKeyCode: UInt16(kVK_ANSI_C),
            cgEvent: cgEvent
        )
        XCTAssertEqual(resolved, UInt32(kVK_Escape))
    }

    func testCapturedUsesCGEventWhenNSEventKeyCodeIsWrong() {
        let cgEvent = makeCGEscapeKeyEvent(down: true, flags: .maskCommand)
        let nsEvent = NSEvent(cgEvent: cgEvent)
        XCTAssertNotNil(nsEvent)

        // Simulate the local-monitor mismatch: NSEvent reports C, CGEvent still has Escape.
        let resolved = HotkeyConfiguration.resolvedKeyCode(
            fallbackKeyCode: UInt16(kVK_ANSI_C),
            cgEvent: cgEvent
        )
        XCTAssertEqual(resolved, UInt32(kVK_Escape))

        let config = HotkeyConfiguration(
            keyCode: resolved,
            carbonModifiers: HotkeyConfiguration.carbonModifiers(from: nsEvent!.modifierFlags)
        )
        XCTAssertEqual(config.displayName, "⌘Esc")
    }

    func testCapturedFromCGEventCommandEscape() {
        let cgEvent = makeCGEscapeKeyEvent(down: true, flags: .maskCommand)
        let event = NSEvent(cgEvent: cgEvent)
        XCTAssertNotNil(event)
        assertCaptured(event!, keyCode: kVK_Escape, carbonModifiers: cmdKey, displayName: "⌘Esc")
        XCTAssertEqual(HotkeyConfiguration.resolvedKeyCode(from: event!), UInt32(kVK_Escape))
    }

    func testCapturedFromCGEventOptionEscape() {
        let cgEvent = makeCGEscapeKeyEvent(down: true, flags: .maskAlternate)
        let event = NSEvent(cgEvent: cgEvent)
        XCTAssertNotNil(event)
        assertCaptured(event!, keyCode: kVK_Escape, carbonModifiers: optionKey, displayName: "⌥Esc")
    }

    func testCapturedFromCGEventControlShiftLetter() {
        let cgEvent = makeCGKeyEvent(
            virtualKey: CGKeyCode(kVK_ANSI_S),
            down: true,
            flags: [.maskControl, .maskShift]
        )
        let event = NSEvent(cgEvent: cgEvent)
        XCTAssertNotNil(event)
        assertCaptured(event!, keyCode: kVK_ANSI_S, carbonModifiers: controlKey | shiftKey, displayName: "⌃⇧S")
    }

    func testResolvedKeyCodeFallsBackWhenCGEventMissing() {
        XCTAssertEqual(
            HotkeyConfiguration.resolvedKeyCode(fallbackKeyCode: UInt16(kVK_Escape), cgEvent: nil),
            UInt32(kVK_Escape)
        )
    }

    // MARK: - Helpers

    private func assertCaptured(
        _ event: NSEvent,
        keyCode: Int,
        carbonModifiers: Int,
        displayName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let config = HotkeyConfiguration.captured(from: event) else {
            XCTFail("Expected capture for keyCode \(keyCode)", file: file, line: line)
            return
        }
        XCTAssertEqual(config.keyCode, UInt32(keyCode), file: file, line: line)
        XCTAssertEqual(config.carbonModifiers, UInt32(carbonModifiers), file: file, line: line)
        XCTAssertEqual(config.displayName, displayName, file: file, line: line)
    }

    private func makeKeyEvent(
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String = ""
    ) -> NSEvent {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: charactersIgnoringModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
        XCTAssertNotNil(event, "Failed to synthesize key event for keyCode \(keyCode)")
        return event!
    }

    private func makeCGEscapeKeyEvent(down: Bool, flags: CGEventFlags) -> CGEvent {
        makeCGKeyEvent(virtualKey: CGKeyCode(kVK_Escape), down: down, flags: flags)
    }

    private func makeCGKeyEvent(virtualKey: CGKeyCode, down: Bool, flags: CGEventFlags) -> CGEvent {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else {
            XCTFail("Failed to create CGEvent for virtualKey \(virtualKey)")
            return CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)!
        }
        event.flags = flags
        return event
    }
}
