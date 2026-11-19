@testable import CameraCore
import XCTest

final class ColorMixTests: XCTestCase {
    private func assertClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ accuracy: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, file: file, line: line)
    }

    private let samples: [SIMD3<Double>] = [
        SIMD3(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.5, 0.5, 0.5), SIMD3(1, 0, 0), SIMD3(0.2, 0.6, 0.3),
        SIMD3(0.1, 0.2, 0.9), SIMD3(0.8, 0.4, 0.1), SIMD3(0.95, 0.9, 0.85),
    ]

    func testNeutralChangesNothing() {
        let look = LookAdjustments.neutral
        for c in samples {
            XCTAssertEqual(ColorMixMath.apply(c, look: look), c)
            XCTAssertEqual(ColorMixMath.mix(c, .neutral), c)
            XCTAssertEqual(ColorMixMath.vibrance(c, 0), c)
        }
        XCTAssertNil(ColorMixMath.rollOffThreshold(0))
    }

    func testHSVMatchesTheDefinition() {
        let red = ColorMixMath.hsv(SIMD3(1, 0, 0))
        XCTAssertEqual(red.h, 0, accuracy: 1e-6)
        XCTAssertEqual(red.s, 1, accuracy: 1e-6)
        XCTAssertEqual(red.v, 1, accuracy: 1e-6)
        XCTAssertEqual(ColorMixMath.hsv(SIMD3(0, 1, 0)).h, 1.0 / 3, accuracy: 1e-6)
        XCTAssertEqual(ColorMixMath.hsv(SIMD3(0, 0, 1)).h, 2.0 / 3, accuracy: 1e-6)
        XCTAssertEqual(ColorMixMath.hsv(SIMD3(0.5, 0.5, 0.5)).s, 0, accuracy: 1e-6)
    }

    func testCurveHitsBandsAndWrapsFromMagentaToRed() {
        var values = Array(repeating: 0.0, count: ColorMix.bandCount)
        values[ColorMix.Band.red.rawValue] = 1
        XCTAssertEqual(ColorMixMath.curve(values, at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(ColorMixMath.curve(values, at: 30.0 / 360), 0, accuracy: 1e-9)
        // Halfway between magenta (300°) and red (360°).
        XCTAssertEqual(ColorMixMath.curve(values, at: 330.0 / 360), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ColorMixMath.curve(values, at: 15.0 / 360), 0.5, accuracy: 1e-9)
    }

    func testHueShiftTurnsRedTowardsOrange() {
        var mix = ColorMix()
        mix[hue: .red] = 1
        // +30° from pure red is (1, 0.5, 0).
        assertClose(ColorMixMath.mix(SIMD3(1, 0, 0), mix), SIMD3(1, 0.5, 0))
        // Blue sits far from red and is left alone.
        assertClose(ColorMixMath.mix(SIMD3(0, 0, 1), mix), SIMD3(0, 0, 1))
    }

    func testSaturationMinusOneTakesOnlyThatBandOut() {
        var mix = ColorMix()
        mix[saturation: .green] = -1
        let green = ColorMixMath.mix(SIMD3(0.2, 0.8, 0.2), mix)
        XCTAssertEqual(green.x, green.y, accuracy: 1e-6, "green becomes grey")
        XCTAssertEqual(green.y, green.z, accuracy: 1e-6)
        assertClose(ColorMixMath.mix(SIMD3(0.9, 0.1, 0.1), mix), SIMD3(0.9, 0.1, 0.1))
    }

    func testLightLeavesGreysAlone() {
        var mix = ColorMix()
        for band in ColorMix.Band.allCases { mix[light: band] = 1 }
        assertClose(ColorMixMath.mix(SIMD3(0.4, 0.4, 0.4), mix), SIMD3(0.4, 0.4, 0.4))
        let red = ColorMixMath.mix(SIMD3(0.6, 0.1, 0.1), mix)
        XCTAssertGreaterThan(red.x, 0.6, "saturated colours get brighter")
    }

    func testVibranceFollowsTheFormula() {
        let c = SIMD3(0.6, 0.5, 0.4)
        let luma = 0.6 * 0.2126 + 0.5 * 0.7152 + 0.4 * 0.0722
        let t = 1 + (1 - 0.6 + 0.4) * 0.5
        assertClose(ColorMixMath.vibrance(c, 0.5), SIMD3(repeating: luma) + (c - SIMD3(repeating: luma)) * t)
    }

    func testRollOffKeepsLowValuesAndSoftensTheTop() throws {
        let threshold = try XCTUnwrap(ColorMixMath.rollOffThreshold(1))
        XCTAssertEqual(threshold, 0.4, accuracy: 1e-9)
        assertClose(ColorMixMath.rollOff(SIMD3(0.3, 0.2, 0.1), threshold: threshold), SIMD3(0.3, 0.2, 0.1))
        let bright = ColorMixMath.rollOff(SIMD3(1, 0.8, 0.5), threshold: threshold)
        XCTAssertLessThan(bright.x, 1)
        XCTAssertEqual(bright.y / bright.x, 0.8, accuracy: 1e-6, "channel ratios stay")
        let negative = ColorMixMath.rollOff(SIMD3(0.3, -0.1, 0.2), threshold: 0.9)
        XCTAssertGreaterThanOrEqual(negative.y, 0)
    }

    func testShaderValuesAreScaled() {
        var mix = ColorMix()
        mix[hue: .blue] = 1
        mix[saturation: .blue] = -0.5
        mix[light: .blue] = 1
        let values = mix.shaderValues
        XCTAssertEqual(values.count, 24)
        XCTAssertEqual(values[ColorMix.Band.blue.rawValue], Float(1.0 / 12), accuracy: 1e-7)
        XCTAssertEqual(values[8 + ColorMix.Band.blue.rawValue], -0.5)
        XCTAssertEqual(values[16 + ColorMix.Band.blue.rawValue], Float(ColorMixMath.lightScale))
    }

    func testOldFilesLoadNeutralAndNewValuesSurviveEncoding() throws {
        let old = try JSONDecoder().decode(LookAdjustments.self, from: Data(#"{"contrast":1.2}"#.utf8))
        XCTAssertEqual(old.vibrance, 0)
        XCTAssertEqual(old.highlightRolloff, 0)
        XCTAssertTrue(old.colorMix.isNeutral)

        var look = LookAdjustments()
        look.vibrance = 0.4
        look.highlightRolloff = 0.7
        look.colorMix[saturation: .orange] = -0.3
        let decoded = try JSONDecoder().decode(LookAdjustments.self, from: JSONEncoder().encode(look))
        XCTAssertEqual(decoded, look)

        let short = try JSONDecoder().decode(ColorMix.self, from: Data(#"{"hue":[5]}"#.utf8))
        XCTAssertEqual(short.hue.count, ColorMix.bandCount)
        XCTAssertEqual(short.hue[0], 1, "values are clamped")
    }

    func testBuiltInPresetsKeepColourMixerEdits() throws {
        let stored = try XCTUnwrap(PresetCatalog.defaults().first)
        var edited = stored
        edited.adjustments.vibrance = 0.3
        edited.adjustments.highlightRolloff = 0.5
        edited.adjustments.colorMix[hue: .aqua] = -0.4
        let locked = PresetLibrary.lockedEdit(stored: stored, edited: edited)
        XCTAssertEqual(locked.adjustments.vibrance, 0.3)
        XCTAssertEqual(locked.adjustments.highlightRolloff, 0.5)
        XCTAssertEqual(locked.adjustments.colorMix, edited.adjustments.colorMix)
    }
}
