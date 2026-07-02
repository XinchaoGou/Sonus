import Carbon
import XCTest
@testable import Sonus

@MainActor
final class HotkeyManagerTests: XCTestCase {
    private var manager: HotkeyManager!

    override func setUp() {
        super.setUp()
        manager = HotkeyManager()
    }

    override func tearDown() {
        manager.unregister()
        manager = nil
        super.tearDown()
    }

    func testRegisterDefaultHotkeySucceeds() {
        XCTAssertTrue(manager.register(configuration: .default))
    }

    func testRegisterLegacyHotkeySucceeds() {
        XCTAssertTrue(manager.register(configuration: .legacyDefault))
    }

    func testRegisterCommonHotkeyCombinations() {
        let configs = [
            HotkeyConfiguration(keyCode: UInt32(kVK_Escape), carbonModifiers: UInt32(cmdKey)),
            HotkeyConfiguration(keyCode: UInt32(kVK_Escape), carbonModifiers: UInt32(optionKey)),
            HotkeyConfiguration(keyCode: UInt32(kVK_Escape), carbonModifiers: UInt32(cmdKey | shiftKey)),
            HotkeyConfiguration(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey | optionKey)),
            HotkeyConfiguration(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey)),
        ]
        for config in configs {
            manager.unregister()
            XCTAssertTrue(
                manager.register(configuration: config),
                "Expected register success for \(config.displayName)"
            )
        }
    }

    func testRegisterCommandCopyFailsBecauseReservedBySystem() {
        manager.unregister()
        XCTAssertFalse(
            manager.register(
                configuration: HotkeyConfiguration(
                    keyCode: UInt32(kVK_ANSI_C),
                    carbonModifiers: UInt32(cmdKey)
                )
            )
        )
    }

    func testRegisterReplacePreviousHotkey() {
        XCTAssertTrue(manager.register(configuration: .default))
        XCTAssertTrue(
            manager.register(
                configuration: HotkeyConfiguration(
                    keyCode: UInt32(kVK_ANSI_T),
                    carbonModifiers: UInt32(cmdKey | shiftKey)
                )
            )
        )
    }

    func testUnregisterAllowsReregistration() {
        XCTAssertTrue(manager.register(configuration: .default))
        manager.unregister()
        XCTAssertTrue(manager.register(configuration: .legacyDefault))
    }
}
