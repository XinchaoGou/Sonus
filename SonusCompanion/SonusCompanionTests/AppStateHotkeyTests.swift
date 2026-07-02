import Carbon
import XCTest
@testable import Sonus

@MainActor
final class AppStateHotkeyTests: XCTestCase {
    func testUpdateHotkeyRollsBackWhenRegistrationFails() {
        let appState = AppState()
        let original = appState.hotkeyConfiguration
        let reserved = HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_C),
            carbonModifiers: UInt32(cmdKey)
        )

        XCTAssertFalse(appState.updateHotkey(reserved))
        XCTAssertEqual(appState.hotkeyConfiguration, original)
    }

    func testUpdateHotkeyPersistsSuccessfulRegistration() {
        let appState = AppState()
        let custom = HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_R),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )

        XCTAssertTrue(appState.updateHotkey(custom))
        XCTAssertEqual(appState.hotkeyConfiguration, custom)
        XCTAssertEqual(AppSettings.hotkeyConfiguration, custom)

        _ = appState.updateHotkey(.default)
        AppSettings.hotkeyConfiguration = .default
    }
}
