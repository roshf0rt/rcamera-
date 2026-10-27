import XCTest
import CameraCore

final class LUT3DTests: XCTestCase {
    func testIdentityLookupReturnsInput() throws {
        let lut = try LUT3D.identity(size: 17)
        let out = lut.apply(r: 0.25, g: 0.5, b: 0.8)
        XCTAssertEqual(out.r, 0.25, accuracy: 0.001)
        XCTAssertEqual(out.g, 0.5, accuracy: 0.001)
        XCTAssertEqual(out.b, 0.8, accuracy: 0.001)
    }

    func testParsesCubeText() throws {
        var text = "# comment\nTITLE \"test\"\nLUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
        for b in 0 ... 1 { for g in 0 ... 1 { for r in 0 ... 1 { text += "\(r) \(g) \(b)\n" } } }
        let lut = try LUT3D.parse(data: Data(text.utf8), fileExtension: "CUBE")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.rgba.count, 32)
        // second entry is red = 1, green = 0, blue = 0
        XCTAssertEqual(Array(lut.rgba[4 ..< 8]), [1, 0, 0, 1])
    }

    func testCubeWithInvertedValuesLooksUpInverted() throws {
        var text = "LUT_3D_SIZE 2\n"
        for b in 0 ... 1 { for g in 0 ... 1 { for r in 0 ... 1 { text += "\(1 - r) \(1 - g) \(1 - b)\n" } } }
        let lut = try LUT3D.parse(data: Data(text.utf8), fileExtension: "cube")
        let out = lut.apply(r: 0.2, g: 0.2, b: 1.0)
        XCTAssertEqual(out.r, 0.8, accuracy: 0.001)
        XCTAssertEqual(out.b, 0.0, accuracy: 0.001)
    }

    func testRejectsWrongEntryCount() {
        let text = "LUT_3D_SIZE 2\n0 0 0\n1 1 1\n"
        XCTAssertThrowsError(try LUT3D.parse(data: Data(text.utf8), fileExtension: "cube"))
    }

    func testRejects1DAndCustomDomain() {
        XCTAssertThrowsError(try LUT3D.parse(data: Data("LUT_1D_SIZE 4\n".utf8), fileExtension: "cube")) {
            XCTAssertEqual($0 as? LUTError, .unsupported1DLUT)
        }
        XCTAssertThrowsError(try LUT3D.parse(data: Data("DOMAIN_MAX 2 2 2\nLUT_3D_SIZE 2\n".utf8), fileExtension: "cube")) {
            XCTAssertEqual($0 as? LUTError, .unsupportedDomain)
        }
    }

    func testParsesBinaryLUT() throws {
        let size = 3
        var bytes: [UInt8] = [UInt8(size)]
        for b in 0 ..< size { for g in 0 ..< size { for r in 0 ..< size {
            bytes += [UInt8(r * 127), UInt8(g * 127), UInt8(b * 127), 1]
        } } }
        let lut = try LUT3D.parse(data: Data(bytes), fileExtension: "lut")
        XCTAssertEqual(lut.size, 3)
        XCTAssertEqual(lut.apply(r: 1, g: 0, b: 0).r, 254.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(lut.rgba[3], 1)
    }

    func testRejectsTruncatedBinaryLUT() {
        XCTAssertThrowsError(try LUT3D.parse(data: Data([35, 0, 0, 0, 1]), fileExtension: "lut"))
    }

    func testRejectsUnknownExtension() {
        XCTAssertThrowsError(try LUT3D.parse(data: Data(), fileExtension: "png")) {
            XCTAssertEqual($0 as? LUTError, .unsupportedFormat("png"))
        }
    }

    func testFloat32DataLength() throws {
        let lut = try LUT3D.identity(size: 4)
        XCTAssertEqual(lut.float32Data.count, 4 * 4 * 4 * 4 * MemoryLayout<Float>.size)
    }
}

final class PresetLibraryTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeCube(size: Int, to url: URL) throws {
        var text = "LUT_3D_SIZE \(size)\n"
        let scale = Float(size - 1)
        for b in 0 ..< size { for g in 0 ..< size { for r in 0 ..< size {
            text += "\(Float(r) / scale) \(Float(g) / scale) \(Float(b) / scale)\n"
        } } }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testDefaultsHaveTenNamedPresets() throws {
        let library = try PresetLibrary(storageDirectory: makeTempDirectory())
        XCTAssertEqual(library.presets.count, 10)
        XCTAssertEqual(library.presets.map(\.name), ["JaneSu", "Solstice", "Velvet", "Rise", "Carbon", "Clear", "Mosaic", "Silver", "Sienna", "Drift"])
        XCTAssertEqual(library.presets.last?.id, "preset-4")
        XCTAssertFalse(library.presets.contains(where: \.isHidden))
        XCTAssertTrue(library.presets.allSatisfy { $0.grain > 0 }, "presets start with film grain")
        XCTAssertFalse(library.hasLUT(for: "preset-1"))
    }

    func testUpdateSurvivesReload() throws {
        let dir = try makeTempDirectory()
        let library = try PresetLibrary(storageDirectory: dir)
        var preset = try library.addCustom(copying: library.presets[2])
        preset.name = "Тёплый"
        preset.grain = 4
        try library.update(preset)

        let reloaded = try PresetLibrary(storageDirectory: dir)
        XCTAssertEqual(reloaded.preset(id: preset.id)?.name, "Тёплый")
        XCTAssertEqual(reloaded.preset(id: preset.id)?.grain, 1, "grain is clamped to 0...1")
    }

    func testImportLUTCopiesAndLoads() throws {
        let dir = try makeTempDirectory()
        let source = dir.appendingPathComponent("my look.cube")
        try writeCube(size: 5, to: source)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))

        let lut = try library.importLUT(from: source, for: "preset-3")
        XCTAssertEqual(lut.size, 5)
        XCTAssertTrue(library.hasLUT(for: "preset-3"))
        XCTAssertEqual(try library.loadLUT(for: "preset-3")?.size, 5)
        XCTAssertNil(try library.loadLUT(for: "preset-4"))

        let reloaded = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        XCTAssertEqual(try reloaded.loadLUT(for: "preset-3")?.size, 5)
    }

    func testImportingInvalidLUTLeavesExistingOne() throws {
        let dir = try makeTempDirectory()
        let good = dir.appendingPathComponent("good.cube")
        try writeCube(size: 3, to: good)
        let bad = dir.appendingPathComponent("bad.cube")
        try "LUT_3D_SIZE 2\n1 1 1\n".write(to: bad, atomically: true, encoding: .utf8)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        try library.importLUT(from: good, for: "preset-1")

        XCTAssertThrowsError(try library.importLUT(from: bad, for: "preset-1"))
        XCTAssertEqual(try library.loadLUT(for: "preset-1")?.size, 3)
    }

    func testReplacingLUTWithOtherExtensionRemovesOld() throws {
        let dir = try makeTempDirectory()
        let cube = dir.appendingPathComponent("a.cube")
        try writeCube(size: 3, to: cube)
        var bytes: [UInt8] = [2]
        for _ in 0 ..< 8 { bytes += [10, 20, 30, 1] }
        let binary = dir.appendingPathComponent("b.lut")
        try Data(bytes).write(to: binary)

        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        try library.importLUT(from: cube, for: "preset-1")
        try library.importLUT(from: binary, for: "preset-1")

        XCTAssertEqual(library.lutURL(for: "preset-1")?.pathExtension, "lut")
        XCTAssertEqual(try library.loadLUT(for: "preset-1")?.size, 2)
    }

    func testRemoveLUT() throws {
        let dir = try makeTempDirectory()
        let cube = dir.appendingPathComponent("a.cube")
        try writeCube(size: 3, to: cube)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        try library.importLUT(from: cube, for: "preset-1")
        try library.removeLUT(for: "preset-1")
        XCTAssertFalse(library.hasLUT(for: "preset-1"))
        XCTAssertNil(try library.loadLUT(for: "preset-1"))
    }

    func testBundledLUTIsFoundButUserLUTWins() throws {
        let dir = try makeTempDirectory()
        let bundled = dir.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try writeCube(size: 4, to: bundled.appendingPathComponent("preset-2.cube"))
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"), bundledLUTDirectory: bundled)
        XCTAssertEqual(try library.loadLUT(for: "preset-2")?.size, 4)

        let mine = dir.appendingPathComponent("mine.cube")
        try writeCube(size: 6, to: mine)
        try library.importLUT(from: mine, for: "preset-2")
        XCTAssertEqual(try library.loadLUT(for: "preset-2")?.size, 6)
    }

    func testSlotsAreStoredSeparately() throws {
        let dir = try makeTempDirectory()
        let small = dir.appendingPathComponent("a.cube")
        let large = dir.appendingPathComponent("b.cube")
        try writeCube(size: 3, to: small)
        try writeCube(size: 5, to: large)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))

        try library.importLUT(from: small, for: "preset-1", slot: .photo)
        try library.importLUT(from: large, for: "preset-1", slot: .appleLog)

        XCTAssertTrue(library.hasLUT(for: "preset-1", slot: .photo))
        XCTAssertFalse(library.hasLUT(for: "preset-1", slot: .video))
        XCTAssertTrue(library.hasLUT(for: "preset-1", slot: .appleLog))
        XCTAssertEqual(try library.loadLUT(for: "preset-1", slot: .photo)?.size, 3)
        XCTAssertEqual(try library.loadLUT(for: "preset-1", slot: .appleLog)?.size, 5)
    }

    func testVideoFallsBackToPhotoButAppleLogDoesNot() throws {
        let dir = try makeTempDirectory()
        let cube = dir.appendingPathComponent("a.cube")
        try writeCube(size: 3, to: cube)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        try library.importLUT(from: cube, for: "preset-1", slot: .photo)

        XCTAssertEqual(try library.loadLUT(for: "preset-1", slot: .video)?.size, 3)
        XCTAssertNil(try library.loadLUT(for: "preset-1", slot: .appleLog))
        XCTAssertFalse(library.hasLUT(for: "preset-1", slot: .video), "fallback does not count as an own LUT")
        XCTAssertTrue(library.hasAnyLUT(for: "preset-1"))
    }

    func testRemovingOneSlotKeepsTheOthers() throws {
        let dir = try makeTempDirectory()
        let cube = dir.appendingPathComponent("a.cube")
        try writeCube(size: 3, to: cube)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        try library.importLUT(from: cube, for: "preset-1", slot: .photo)
        try library.importLUT(from: cube, for: "preset-1", slot: .video)
        try library.removeLUT(for: "preset-1", slot: .video)
        XCTAssertTrue(library.hasLUT(for: "preset-1", slot: .photo))
        XCTAssertFalse(library.hasLUT(for: "preset-1", slot: .video))
    }

    func testPreparedLUTCanBeCommittedLater() throws {
        let dir = try makeTempDirectory()
        let cube = dir.appendingPathComponent("a.cube")
        try writeCube(size: 4, to: cube)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))
        let prepared = try LUTImport.prepare(url: cube)
        XCTAssertFalse(library.hasAnyLUT(for: "preset-2"))
        try library.commit(prepared, for: "preset-2", slot: .photo)
        XCTAssertEqual(try library.loadLUT(for: "preset-2")?.size, 4)
    }

    func testOldInstallAdoptsNewNamesAndDefaultLooksButKeepsEdits() throws {
        let dir = try makeTempDirectory()
        let storage = dir.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        // What the first releases wrote: placeholder names, no grain, one preset renamed by the user.
        var old = (1 ... 10).map { Preset(id: "preset-\($0)", name: "Пресет \($0)", accentIndex: $0 - 1) }
        old[1].name = "JaneSu 2"
        old[3].name = "Мой пресет"
        old[5].grain = 0.8
        try JSONEncoder().encode(old).write(to: storage.appendingPathComponent("presets.json"))

        let library = try PresetLibrary(storageDirectory: storage)
        XCTAssertEqual(library.presets[0].name, "JaneSu")
        XCTAssertEqual(library.preset(id: "preset-2")?.name, "Carbon")
        XCTAssertEqual(library.preset(id: "preset-3")?.name, "Clear")
        XCTAssertEqual(library.preset(id: "preset-4")?.name, "Drift", "built-ins are locked; the renamed one lives on as a custom copy")
        XCTAssertEqual(library.presets.filter(\.isCustom).map(\.name), ["Мой пресет"])
        XCTAssertEqual(library.presets.filter(\.isCustom).map(\.isHidden), [true], "presets outside the new order are hidden")
        XCTAssertGreaterThan(library.presets[0].grain, 0)
        XCTAssertGreaterThan(library.presets[0].halation, 0)
        XCTAssertEqual(library.preset(id: "preset-6")?.grain, 0.45, "amounts from before the new renderer are replaced")

        // The migration runs once: a later edit back to zero grain is respected.
        var edited = library.presets[0]
        edited.grain = 0
        try library.update(edited)
        let reloaded = try PresetLibrary(storageDirectory: storage)
        XCTAssertEqual(reloaded.presets[0].grain, 0)
    }

    func testPresetFileWithoutHalationStillLoads() throws {
        let dir = try makeTempDirectory()
        let storage = dir.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try #"[{"id":"preset-1","name":"X","grain":0.2,"accentIndex":0}]"#.write(
            to: storage.appendingPathComponent("presets.json"), atomically: true, encoding: .utf8)
        try "\(PresetCatalog.revision)".write(to: storage.appendingPathComponent("catalog-revision"), atomically: true, encoding: .utf8)
        let library = try PresetLibrary(storageDirectory: storage)
        XCTAssertEqual(library.presets.first?.name, "X")
        XCTAssertEqual(library.presets.first?.halation, 0)
        XCTAssertEqual(library.presets.first?.grain, 0.2, "amounts set under the current renderer stay")
    }

    func testPhotoFallsBackToVideoLUTAndBack() throws {
        let dir = try makeTempDirectory()
        let cube = dir.appendingPathComponent("a.cube")
        try writeCube(size: 3, to: cube)
        let library = try PresetLibrary(storageDirectory: dir.appendingPathComponent("lib"))

        // A preset with only a Standard LUT (like Clear) still works for photos.
        try library.importLUT(from: cube, for: "preset-3", slot: .video)
        XCTAssertEqual(try library.loadLUT(for: "preset-3", slot: .photo)?.size, 3)
        XCTAssertFalse(library.hasLUT(for: "preset-3", slot: .photo))
        XCTAssertNil(try library.loadLUT(for: "preset-3", slot: .appleLog))
    }
}

final class LUTToolsTests: XCTestCase {
    func testBinaryExportRoundTrips() throws {
        let lut = try LUT3D.identity(size: 9)
        let data = try lut.binaryLUTData()
        XCTAssertEqual(data.count, 1 + 9 * 9 * 9 * 4)
        let back = try LUT3D.parse(data: data, fileExtension: "lut")
        XCTAssertEqual(back.size, 9)
        for (a, b) in zip(lut.rgba, back.rgba) { XCTAssertEqual(a, b, accuracy: 1.0 / 255.0) }
    }

    func testIdentityHasLinearNeutralCurve() throws {
        let curve = try LUT3D.identity(size: 5).neutralCurve()
        XCTAssertEqual(curve, [0, 0.25, 0.5, 0.75, 1])
    }

    func testComposingWithIdentityCurveChangesNothing() throws {
        var text = "LUT_3D_SIZE 3\n"
        for b in 0 ... 2 { for g in 0 ... 2 { for r in 0 ... 2 { text += "\(Float(2 - r) / 2) \(Float(g) / 2) \(Float(b) / 2)\n" } } }
        let lut = try LUT3D.parse(data: Data(text.utf8), fileExtension: "cube")
        let composed = try lut.composing(preCurve: [0, 0.5, 1])
        for (a, b) in zip(lut.rgba, composed.rgba) { XCTAssertEqual(a, b, accuracy: 1e-5) }
    }

    func testComposingAppliesTheCurveFirst() throws {
        // A curve that pushes mid-gray to white, followed by an inverting LUT, must give black at 0.5.
        var text = "LUT_3D_SIZE 3\n"
        for b in 0 ... 2 { for g in 0 ... 2 { for r in 0 ... 2 {
            text += "\(1 - Float(r) / 2) \(1 - Float(g) / 2) \(1 - Float(b) / 2)\n"
        } } }
        let invert = try LUT3D.parse(data: Data(text.utf8), fileExtension: "cube")
        let composed = try invert.composing(preCurve: [0, 1, 1])
        let out = composed.apply(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(out.r, 0, accuracy: 1e-4)
        XCTAssertEqual(out.g, 0, accuracy: 1e-4)
        XCTAssertEqual(out.b, 0, accuracy: 1e-4)
        XCTAssertEqual(composed.apply(r: 0, g: 0, b: 0).r, 1, accuracy: 1e-4)
    }

    func testCurveEvaluationInterpolates() {
        XCTAssertEqual(LUT3D.evaluate(curve: [0, 1, 0], at: 0.25), 0.5, accuracy: 1e-6)
        XCTAssertEqual(LUT3D.evaluate(curve: [0, 1, 0], at: 1.5), 0, accuracy: 1e-6)
    }

    func testParserHandlesCRLFExponentsAndSignedValues() throws {
        let text = "TITLE \"x\"\r\nLUT_3D_SIZE 2\r\n# note\r\n"
            + "0 0 0\r\n1.0e0 0 0\r\n0 1 0\r\n1 1 0\r\n0 0 1\r\n1 0 1\r\n+0 1 1\r\n1 1 -0.0\r\n"
        let lut = try LUT3D.parse(data: Data(text.utf8), fileExtension: "cube")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.rgba[4], 1)
        XCTAssertEqual(lut.rgba[6 * 4 + 2], 1)
    }

    func testParserRejectsGarbageNumbers() {
        XCTAssertThrowsError(try LUT3D.parse(data: Data("LUT_3D_SIZE 2\n0 0\n".utf8), fileExtension: "cube"))
    }
}

final class CustomPresetTests: XCTestCase {
    private func makeLibrary() throws -> (PresetLibrary, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("custom-presets-\(UUID().uuidString)")
        return (try PresetLibrary(storageDirectory: directory), directory)
    }

    func testAddingCopiesTheSourceLookUnderANewCustomID() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = library.presets[0]
        let added = try library.addCustom(copying: source)
        XCTAssertTrue(added.isCustom)
        XCTAssertNotEqual(added.id, source.id)
        XCTAssertEqual(added.adjustments, source.adjustments)
        XCTAssertEqual(library.presets.count, PresetCatalog.defaultCount + 1)
    }

    func testOnlyCustomPresetsCanBeRemoved() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        try library.removeCustom(id: "preset-1")
        XCTAssertEqual(library.presets.count, PresetCatalog.defaultCount)

        let added = try library.addCustom(copying: library.presets[0])
        try library.removeCustom(id: added.id)
        XCTAssertNil(library.preset(id: added.id))
        XCTAssertEqual(library.presets.count, PresetCatalog.defaultCount)
    }

    func testCustomPresetsSurviveReopening() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let added = try library.addCustom(copying: library.presets[2], name: "Mine")
        let reopened = try PresetLibrary(storageDirectory: directory)
        XCTAssertEqual(reopened.preset(id: added.id)?.name, "Mine")
    }

    func testBuiltInPresetsOnlyTakeSpeedCurveAndRange() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        var edited = library.presets[0]
        let original = edited
        edited.name = "Renamed"
        edited.halation = 0
        edited.adjustments.temp = 0.8
        edited.adjustments.hue = 20
        ContrastCurve.crush.apply(to: &edited.adjustments)
        FilmSpeed.iso800.apply(grain: &edited.grain, to: &edited.adjustments)
        edited.adjustments.dynamicRange = 1.5
        try library.update(edited)

        let stored = try XCTUnwrap(library.preset(id: original.id))
        XCTAssertEqual(stored.name, original.name)
        XCTAssertEqual(stored.halation, original.halation)
        XCTAssertEqual(stored.adjustments.temp, 0)
        XCTAssertEqual(stored.adjustments.hue, 0)
        XCTAssertEqual(stored.adjustments.curve, .crush)
        XCTAssertEqual(stored.adjustments.contrast, edited.adjustments.contrast)
        XCTAssertEqual(stored.grain, FilmSpeed.iso800.grain)
        XCTAssertEqual(stored.adjustments.dynamicRange, 1.5)

        try library.resetBuiltIn(id: original.id)
        XCTAssertEqual(library.preset(id: original.id), original)

        var recoloured = original
        recoloured.accentIndex = 7
        try library.update(recoloured)
        XCTAssertEqual(library.preset(id: original.id)?.accentIndex, 7, "card colours are not part of the look")
    }

    func testReorderingKeepsEveryPresetAndSurvivesReopening() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let added = try library.addCustom(copying: nil, name: "Mine")
        try library.reorder([added.id, "preset-3", "preset-1"])
        let ids = library.presets.map(\.id)
        XCTAssertEqual(Array(ids.prefix(3)), [added.id, "preset-3", "preset-1"])
        XCTAssertEqual(ids[3], "preset-9", "unlisted presets follow in their old order")
        XCTAssertEqual(Set(ids).count, PresetCatalog.defaultCount + 1)
        let reopened = try PresetLibrary(storageDirectory: directory)
        XCTAssertEqual(reopened.presets.map(\.id), ids)
    }

    func testOlderInstallsAdoptTheNewOrderAndHideTheRest() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mine = try library.addCustom(copying: nil, name: "Mine")
        XCTAssertFalse(mine.isHidden, "new presets show on the camera")
        // An install from revision 4, in the old order.
        var presets = PresetCatalog.defaults()
        presets.append(mine)
        try JSONEncoder().encode(presets).write(to: directory.appendingPathComponent("presets.json"))
        try "4".write(to: directory.appendingPathComponent("catalog-revision"), atomically: true, encoding: .utf8)

        let reopened = try PresetLibrary(storageDirectory: directory)
        XCTAssertEqual(Array(reopened.presets.map(\.id).prefix(10)), PresetCatalog.displayOrder)
        XCTAssertEqual(reopened.preset(id: mine.id)?.isHidden, true)
        XCTAssertEqual(reopened.presets.filter { !$0.isHidden }.count, 10)

        try reopened.setHidden(false, id: mine.id)
        XCTAssertEqual(try PresetLibrary(storageDirectory: directory).preset(id: mine.id)?.isHidden, false, "the order is adopted once")
        for id in PresetCatalog.displayOrder { try reopened.setHidden(true, id: id) }
        XCTAssertEqual(reopened.presets.filter { !$0.isHidden }.count, 1, "one preset always stays visible")
    }

    func testCustomPresetsTakeEveryChange() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        var added = try library.addCustom(copying: library.presets[0], name: "Mine")
        added.name = "Mine 2"
        added.adjustments.temp = 0.8
        try library.update(added)
        XCTAssertEqual(library.preset(id: added.id)?.name, "Mine 2")
        XCTAssertEqual(library.preset(id: added.id)?.adjustments.temp, 0.8)
    }

    func testFromScratchStartsNeutralWithoutLUT() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scratch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = directory.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
            .write(to: bundled.appendingPathComponent("preset-1.cube"), atomically: true, encoding: .utf8)
        let library = try PresetLibrary(storageDirectory: directory.appendingPathComponent("lib"), bundledLUTDirectory: bundled)

        let blank = try library.addCustom(copying: nil, name: "Blank", accentIndex: 4)
        XCTAssertEqual(blank.adjustments, .neutral)
        XCTAssertEqual(blank.grain, 0)
        XCTAssertEqual(blank.accentIndex, 4)
        XCTAssertFalse(library.hasAnyLUT(for: blank.id))

        let based = try library.addCustom(copying: library.presets[0], name: "Based")
        XCTAssertTrue(library.hasLUT(for: based.id, slot: .photo), "the source's LUT comes along")
        XCTAssertEqual(try library.loadLUT(for: based.id)?.size, 2)
        try library.removeCustom(id: based.id)
        XCTAssertTrue(library.hasLUT(for: "preset-1"), "the bundled original stays")
    }

    func testCoversAreStoredAndRemovedWithThePreset() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        try library.setCover(Data([1, 2, 3]), for: "preset-1")
        XCTAssertNotNil(library.coverURL(for: "preset-1"), "built-in cards take a photo too")
        try library.setCover(nil, for: "preset-1")
        XCTAssertNil(library.coverURL(for: "preset-1"))
        try library.setCover(Data([1]), for: "no-such-preset")
        XCTAssertNil(library.coverURL(for: "no-such-preset"))
        let added = try library.addCustom(copying: nil, name: "Mine")
        try library.setCover(Data([1, 2, 3]), for: added.id)
        let url = try XCTUnwrap(library.coverURL(for: added.id))
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
        try library.removeCustom(id: added.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testEditedBuiltInsMoveIntoCustomCopiesWhenLocking() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        // An install from before the lock, with a built-in the user had tuned and renamed.
        var presets = library.presets
        presets[1].name = "My Carbon"
        presets[1].adjustments.temp = 0.5
        try JSONEncoder().encode(presets).write(to: directory.appendingPathComponent("presets.json"))
        try "3".write(to: directory.appendingPathComponent("catalog-revision"), atomically: true, encoding: .utf8)

        let reopened = try PresetLibrary(storageDirectory: directory)
        XCTAssertEqual(reopened.preset(id: "preset-2"), PresetCatalog.defaults()[1])
        let copy = try XCTUnwrap(reopened.presets.first { $0.isCustom })
        XCTAssertEqual(copy.name, "My Carbon")
        XCTAssertEqual(copy.adjustments.temp, 0.5)
        XCTAssertEqual(reopened.presets.count, PresetCatalog.defaultCount + 1)

        // Opening again does not copy twice.
        XCTAssertEqual(try PresetLibrary(storageDirectory: directory).presets.count, PresetCatalog.defaultCount + 1)
    }

    func testExportWritesReadableJSON() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try library.exportData(for: library.presets[0].id)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"name\""))
        XCTAssertTrue(text.contains(library.presets[0].name))
    }
}
