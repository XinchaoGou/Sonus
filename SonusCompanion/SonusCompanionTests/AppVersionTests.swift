import XCTest
@testable import Sonus

final class AppVersionTests: XCTestCase {
    func testParsesVersionWithoutPrefix() {
        XCTAssertEqual(AppVersion("0.2.0")?.displayString, "0.2.0")
    }

    func testParsesVersionWithVPrefix() {
        XCTAssertEqual(AppVersion("v1.2.3")?.displayString, "1.2.3")
    }

    func testComparesSemverNumerically() {
        let v020 = AppVersion("0.2.0")!
        let v010 = AppVersion("0.10.0")!
        XCTAssertTrue(v020 < v010)
    }

    func testEqualVersions() {
        XCTAssertFalse(AppVersion("1.0.0")! < AppVersion("1.0.0")!)
    }

    func testInvalidVersionReturnsNil() {
        XCTAssertNil(AppVersion("beta"))
    }
}
