import XCTest
@testable import CameraCore

final class ArriLookTests: XCTestCase {
    private func solid(_ value: (Float, Float, Float), size: Int = 5) throws -> LUT3D {
        var values: [Float] = []
        for _ in 0 ..< size * size * size { values += [value.0, value.1, value.2, 1] }
        return try LUT3D(size: size, rgba: values)
    }

    func testCrossoverWeightFollowsYCam() {
        // yCam: weight of the first LUT = (value + 1) / 2, clamped.
        XCTAssertEqual(ArriLook.weight(forCrossover: -1), 0)
        XCTAssertEqual(ArriLook.weight(forCrossover: 0), 0.5)
        XCTAssertEqual(ArriLook.weight(forCrossover: 1), 1)
        XCTAssertEqual(ArriLook.weight(forCrossover: 3), 1)
        XCTAssertEqual(ArriLook.weight(forCrossover: -3), 0)
    }

    func testLogC3PutsMiddleGreyWhereARRIDoes() {
        XCTAssertEqual(ArriLook.logC3(0.18), 0.391, accuracy: 0.002)
        XCTAssertEqual(ArriLook.logC3(0), 0.0928, accuracy: 0.001)
        // The two segments meet at the cut.
        XCTAssertEqual(ArriLook.logC3(0.010591), ArriLook.logC3(0.010592), accuracy: 0.0005)
    }

    func testWhiteStaysWhiteInArriWideGamut() {
        for matrix in [ArriLook.rec709ToAWG, ArriLook.rec2020ToAWG] {
            let white = ArriLook.apply(matrix, [1, 1, 1])
            for channel in white { XCTAssertEqual(channel, 1, accuracy: 0.002) }
        }
    }

    func testEachKindOfInputKeepsGreyNeutralAndPlacesMiddleGrey() {
        for slot in LUTSlot.allCases {
            let grey: Float
            switch slot {
            case .photo: grey = 0.4614 // sRGB code of 18% linear
            case .video: grey = 0.4091 // Rec.709 code of 18% linear
            case .appleLog: grey = AppleLog.encode(0.18)
            }
            let code = ArriLook.logCCode(for: slot, r: grey, g: grey, b: grey)
            XCTAssertEqual(code.0, 0.391, accuracy: 0.004, "\(slot)")
            XCTAssertEqual(code.0, code.1, accuracy: 0.003, "\(slot)")
            XCTAssertEqual(code.1, code.2, accuracy: 0.003, "\(slot)")
        }
    }

    func testPairMixesByTheCrossoverSlider() throws {
        let a = try solid((0.8, 0.4, 0.2))
        let b = try solid((0.2, 0.4, 0.8))
        let pair = ArriLook.Pair(a: a, b: b, slot: .appleLog, size: 5)

        let middle = pair.mixed(crossover: 0).apply(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(middle.r, 0.5, accuracy: 0.001)
        XCTAssertEqual(middle.g, 0.4, accuracy: 0.001)
        XCTAssertEqual(middle.b, 0.5, accuracy: 0.001)

        let warm = pair.mixed(crossover: 1).apply(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(warm.r, 0.8, accuracy: 0.001)
        let cool = pair.mixed(crossover: -1).apply(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(cool.b, 0.8, accuracy: 0.001)

        let quarter = pair.mixed(crossover: 0.5).apply(r: 0.5, g: 0.5, b: 0.5) // weight of a = 0.75
        XCTAssertEqual(quarter.r, 0.8 * 0.75 + 0.2 * 0.25, accuracy: 0.001)
    }

    func testMixingBakedLUTsEqualsBakingTheMix() throws {
        // The input transform comes first, so averaging after baking is the same as averaging before.
        let a = try solid((0.9, 0.5, 0.1))
        let b = try solid((0.1, 0.5, 0.9))
        let pair = ArriLook.Pair(a: a, b: b, slot: .video, size: 5)
        let direct = ArriLook.baked(try solid((0.5, 0.5, 0.5)), for: .video, size: 5)
        let mixed = pair.mixed(crossover: 0).apply(r: 0.3, g: 0.6, b: 0.9)
        let expected = direct.apply(r: 0.3, g: 0.6, b: 0.9)
        XCTAssertEqual(mixed.r, expected.r, accuracy: 0.001)
        XCTAssertEqual(mixed.g, expected.g, accuracy: 0.001)
        XCTAssertEqual(mixed.b, expected.b, accuracy: 0.001)
    }

    func testShippedLUTsAreAMirroredPairWithANeutralMiddle() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/LUTs")
        let a = try LUT3D.parse(data: Data(contentsOf: directory.appendingPathComponent("arri-a.lut")), fileExtension: "lut")
        let b = try LUT3D.parse(data: Data(contentsOf: directory.appendingPathComponent("arri-b.lut")), fileExtension: "lut")
        XCTAssertEqual(a.size, 65)
        XCTAssertEqual(b.size, 65)
        // LogC3 code 0.75 is bright: a is warm there (red over blue), b cool, the mean close to neutral.
        let warm = a.apply(r: 0.75, g: 0.75, b: 0.75)
        let cool = b.apply(r: 0.75, g: 0.75, b: 0.75)
        XCTAssertGreaterThan(warm.r - warm.b, 0.08)
        XCTAssertGreaterThan(cool.b - cool.r, 0.08)
        XCTAssertEqual((warm.r + cool.r) / 2 - (warm.b + cool.b) / 2, 0, accuracy: 0.03)
        // Deep shadows are the other way round: a cool, b warm.
        let darkA = a.apply(r: 0.3, g: 0.3, b: 0.3)
        let darkB = b.apply(r: 0.3, g: 0.3, b: 0.3)
        XCTAssertLessThan(darkA.r, darkA.b + 0.01)
        XCTAssertGreaterThan(darkB.r, darkB.b - 0.01)
    }

    func testARRIPresetIsBuiltInAndOlderInstallsGetIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // An install from before ARRI: the old ten, with the user's own order, and revision 5.
        let old = PresetCatalog.defaults().filter { $0.id != ArriLook.presetID }
        try JSONEncoder().encode(old).write(to: directory.appendingPathComponent("presets.json"))
        try "5".write(to: directory.appendingPathComponent("catalog-revision"), atomically: true, encoding: .utf8)

        let library = try PresetLibrary(storageDirectory: directory)
        XCTAssertEqual(library.presets.count, 11)
        let arri = try XCTUnwrap(library.preset(id: ArriLook.presetID))
        XCTAssertEqual(arri.name, "ARRI")
        XCTAssertFalse(arri.isHidden)
        XCTAssertFalse(arri.isCustom)
        XCTAssertEqual(library.presets[1].id, ArriLook.presetID, "next to the first preset")
        // It stays after a second launch.
        XCTAssertEqual(try PresetLibrary(storageDirectory: directory).presets.count, 11)
    }

    func testCrossoverIsTheOnlyEditARRIKeepsAndItSurvivesEncoding() throws {
        var look = LookAdjustments()
        look.crossover = 0.4
        let decoded = try JSONDecoder().decode(LookAdjustments.self, from: JSONEncoder().encode(look))
        XCTAssertEqual(decoded.crossover, 0.4)
        XCTAssertFalse(decoded.isNeutral)
        // Files from before the slider load as neutral.
        XCTAssertEqual(try JSONDecoder().decode(LookAdjustments.self, from: Data("{}".utf8)).crossover, 0)
        look.crossover = 9
        look.clamp()
        XCTAssertEqual(look.crossover, 1)

        let stored = try XCTUnwrap(PresetCatalog.defaults().first { $0.id == ArriLook.presetID })
        var edited = stored
        edited.adjustments.crossover = -0.5
        XCTAssertEqual(PresetLibrary.lockedEdit(stored: stored, edited: edited).adjustments.crossover, -0.5)
    }
}
