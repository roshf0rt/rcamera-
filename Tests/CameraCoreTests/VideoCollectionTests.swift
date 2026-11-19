@testable import CameraCore
import XCTest

final class VideoCollectionTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testVideoLooksSitBetweenTheClassicAndFilmLooks() {
        let ids = PresetCatalog.defaults().map(\.id)
        XCTAssertEqual(ids.count, PresetCatalog.defaultCount)
        XCTAssertEqual(Array(ids.dropFirst(PresetCatalog.classicCount).prefix(VideoCollection.ids.count)), VideoCollection.ids)
        XCTAssertEqual(Array(ids.suffix(FilmCollection.ids.count)), FilmCollection.ids)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryVideoEntryHasAtLeastOneLUT() {
        for entry in VideoCollection.entries {
            XCTAssertTrue(entry.hasVideo || entry.hasAppleLog, entry.id)
        }
        let pairs = Set(VideoCollection.entries.filter { $0.hasVideo && $0.hasAppleLog }.map(\.key))
        XCTAssertTrue(pairs.isSuperset(of: ["glost", "kodiac", "lectar", "sanda", "ivakin-cabinet", "ivakin-vision3"]))
        XCTAssertEqual(VideoCollection.entry(id: "video-ivakin-skin")?.subtitle, "Video • LUT")
    }

    func testNewVideoLooksJoinAfterTheOnesAlreadyInstalled() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // An install from before the IvakinColor looks: classics, the first video looks, film looks.
        let older = PresetCatalog.defaults().filter { !$0.id.hasPrefix("video-ivakin-") }
        try JSONEncoder().encode(older).write(to: directory.appendingPathComponent("presets.json"))
        try "5".write(to: directory.appendingPathComponent("catalog-revision"), atomically: true, encoding: .utf8)
        let library = try PresetLibrary(storageDirectory: directory)
        XCTAssertEqual(library.presets.map(\.id), PresetCatalog.defaults().map(\.id))
    }

    func testBundledVideoLUTsArePresentAndParse() throws {
        // Tests run from the package root: App/Resources/LUTs holds the shipped files.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/LUTs", isDirectory: true)
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try PresetLibrary(storageDirectory: directory, bundledLUTDirectory: root)
        for entry in VideoCollection.entries {
            if entry.hasVideo {
                let lut = try library.loadLUT(for: entry.id, slot: .video)
                XCTAssertNotNil(lut, entry.id)
            }
            if entry.hasAppleLog {
                let lut = try library.loadLUT(for: entry.id, slot: .appleLog)
                XCTAssertNotNil(lut, entry.id)
            }
        }
    }

    func testAppleLogOnlyLooksHaveNoRec709LUT() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try PresetLibrary(storageDirectory: directory, bundledLUTDirectory: nil)
        XCTAssertEqual(VideoCollection.entry(id: "video-anji")?.subtitle, "Apple Log only")
        XCTAssertEqual(VideoCollection.entry(id: "video-glost")?.subtitle, "Video • Apple Log")
        XCTAssertEqual(VideoCollection.entry(id: "video-alpina")?.subtitle, "Video • LUT")
        XCTAssertNil(library.lutURL(for: "video-anji", slot: .video))
    }
}
