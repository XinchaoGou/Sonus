import Carbon
import XCTest
@testable import Sonus

final class AppSettingsHotkeyTests: XCTestCase {
    private var savedHotkeyData: Data?

    override func setUp() {
        super.setUp()
        savedHotkeyData = UserDefaults.standard.data(forKey: AppSettings.hotkeyConfigKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.hotkeyConfigKey)
    }

    override func tearDown() {
        if let savedHotkeyData {
            UserDefaults.standard.set(savedHotkeyData, forKey: AppSettings.hotkeyConfigKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettings.hotkeyConfigKey)
        }
        super.tearDown()
    }

    func testHotkeyConfigurationDefaultsWhenMissing() {
        XCTAssertEqual(AppSettings.hotkeyConfiguration, .default)
    }

    func testHotkeyConfigurationPersistsCustomValue() {
        let custom = HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_R),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        AppSettings.hotkeyConfiguration = custom
        XCTAssertEqual(AppSettings.hotkeyConfiguration, custom)
    }

    func testMigrateHotkeyFromLegacyDefaultIfNeeded() {
        AppSettings.hotkeyConfiguration = .legacyDefault
        AppSettings.migrateHotkeyFromLegacyDefaultIfNeeded()
        XCTAssertEqual(AppSettings.hotkeyConfiguration, .default)
    }

    func testMigrateHotkeyDoesNotOverwriteCustomHotkey() {
        let custom = HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey)
        )
        AppSettings.hotkeyConfiguration = custom
        AppSettings.migrateHotkeyFromLegacyDefaultIfNeeded()
        XCTAssertEqual(AppSettings.hotkeyConfiguration, custom)
    }

    func testMigrateHotkeyNoOpWhenNeverPersisted() {
        AppSettings.migrateHotkeyFromLegacyDefaultIfNeeded()
        XCTAssertEqual(AppSettings.hotkeyConfiguration, .default)
    }
}
