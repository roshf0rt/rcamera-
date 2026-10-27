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
        XCTAssertEqual(library.presets.first?.name, "Пресет 1")
        XCTAssertEqual(library.presets.last?.id, "preset-10")
        XCTAssertFalse(library.hasLUT(for: "preset-1"))
    }

    func testUpdateSurvivesReload() throws {
        let dir = try makeTempDirectory()
        let library = try PresetLibrary(storageDirectory: dir)
        var preset = library.presets[2]
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
}
