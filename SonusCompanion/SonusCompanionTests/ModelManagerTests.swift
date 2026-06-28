import XCTest
@testable import Sonus

final class ModelManagerTests: XCTestCase {
    func testDirectoryIsReadyRequiresAllAssets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertFalse(ModelManager.directoryIsReady(directory))
        XCTAssertEqual(ModelManager.missingAssets(in: directory).count, ModelManager.requiredAssets.count)

        for asset in ModelManager.requiredAssets {
            try Data([0x01]).write(to: asset.destination(in: directory))
        }

        XCTAssertTrue(ModelManager.directoryIsReady(directory))
        XCTAssertTrue(ModelManager.missingAssets(in: directory).isEmpty)
    }

    func testResolvePrefersCustomPathWhenReady() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for asset in ModelManager.requiredAssets {
            try Data([0x01]).write(to: asset.destination(in: directory))
        }

        let resolved = ModelManager.resolveModelsDirectory(customPath: directory.path)
        XCTAssertEqual(resolved?.path, directory.path)
    }
}
