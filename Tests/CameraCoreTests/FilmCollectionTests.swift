@testable import CameraCore
import XCTest

final class FilmCollectionTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("film-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testFilmLooksAreBuiltInVisibleAndFollowTheClassics() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try PresetLibrary(storageDirectory: directory)
        let ids = library.presets.map(\.id)
        XCTAssertEqual(Array(ids.prefix(PresetCatalog.classicCount)), PresetCatalog.displayOrder)
        XCTAssertEqual(Array(ids.dropFirst(PresetCatalog.classicCount)), VideoCollection.ids + FilmCollection.ids)
        XCTAssertEqual(Set(ids).count, ids.count, "ids are unique")
        for preset in library.presets where FilmCollection.isFilm(preset.id) {
            XCTAssertFalse(preset.isCustom)
            XCTAssertFalse(preset.isHidden)
        }
    }

    func testOlderInstallsGetFilmLooksAtTheEnd() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // An install from before the film looks: the classic eleven in the user's own order, revision 5.
        var old = PresetCatalog.classics()
        old.swapAt(0, 3)
        try JSONEncoder().encode(old).write(to: directory.appendingPathComponent("presets.json"))
        try "5".write(to: directory.appendingPathComponent("catalog-revision"), atomically: true, encoding: .utf8)

        let library = try PresetLibrary(storageDirectory: directory)
        let ids = library.presets.map(\.id)
        XCTAssertEqual(Array(ids.prefix(old.count)), old.map(\.id), "the user's order stays")
        XCTAssertEqual(Array(ids.dropFirst(old.count)), VideoCollection.ids + FilmCollection.ids)
        XCTAssertTrue(library.presets.allSatisfy { !$0.isHidden })
        XCTAssertEqual(try PresetLibrary(storageDirectory: directory).presets.count, PresetCatalog.defaultCount)
    }

    func testMatchingGrainAndVignetteAreAttached() throws {
        let dexp = try XCTUnwrap(FilmCollection.entry(id: "film-dexp"))
        XCTAssertEqual(dexp.overlays.map(\.file), ["Grain/grain_dexp.jpg", "Masks/vignette_dexp.jpg"])
        XCTAssertEqual(dexp.overlays.map(\.blend), [.overlay, .multiply])
        XCTAssertTrue(dexp.overlays[0].tile)
        XCTAssertFalse(dexp.overlays[1].tile)
        let preset = try XCTUnwrap(PresetCatalog.defaults().first { $0.id == "film-dexp" })
        XCTAssertEqual(preset.grain, 0, "the grain scan replaces the generated grain")
        XCTAssertGreaterThan(try XCTUnwrap(PresetCatalog.defaults().first { $0.id == "film-07FF" }).grain, 0)
    }

    func testOverlaysAreEditableOnBuiltInsAndSurviveEncoding() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try PresetLibrary(storageDirectory: directory)
        var edited = try XCTUnwrap(library.preset(id: "film-kg100"))
        edited.overlays = [PresetOverlay(file: "Light/lightleaks3.jpg", opacity: 0.4)]
        try library.update(edited)
        let reopened = try PresetLibrary(storageDirectory: directory)
        let stored = try XCTUnwrap(reopened.preset(id: "film-kg100"))
        XCTAssertEqual(stored.overlays, edited.overlays)
        XCTAssertEqual(stored.overlays.first?.blend, .screen)

        try reopened.resetBuiltIn(id: "film-kg100")
        XCTAssertEqual(reopened.preset(id: "film-kg100")?.overlays, FilmCollection.entry(id: "film-kg100")?.overlays)
    }

    func testOldPresetFilesLoadWithoutOverlays() throws {
        let json = #"{"id":"preset-1","name":"JaneSu","grain":0.5,"halation":0.6,"accentIndex":0}"#
        let preset = try JSONDecoder().decode(Preset.self, from: Data(json.utf8))
        XCTAssertEqual(preset.overlays, [])
        let layer = try JSONDecoder().decode(PresetOverlay.self, from: Data(#"{"file":"Masks/mask_paf.jpg"}"#.utf8))
        XCTAssertEqual(layer.blend, .multiply)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertFalse(layer.tile)
    }

    func testAtMostThreeLayers() {
        let many = (0 ..< 5).map { PresetOverlay(file: "Dust/dust_black.png", opacity: Double($0) / 4) }
        XCTAssertEqual(Preset(id: "x", name: "x", accentIndex: 0, overlays: many).overlays.count, PresetOverlay.maxLayers)
    }
}
