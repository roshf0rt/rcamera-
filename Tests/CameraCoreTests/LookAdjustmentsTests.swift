@testable import CameraCore
import XCTest

final class LookAdjustmentsTests: XCTestCase {
    func testNeutralRegulatorsLeaveEveryColourAlone() {
        let samples: [SIMD3<Double>] = [
            SIMD3(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.2, 0.5, 0.8), SIMD3(0.9, 0.1, 0.4), SIMD3(0.5, 0.5, 0.5),
        ]
        for color in samples {
            let out = ToneMath.regulate(color, .neutral)
            XCTAssertEqual(out.x, color.x, accuracy: 1e-9)
            XCTAssertEqual(out.y, color.y, accuracy: 1e-9)
            XCTAssertEqual(out.z, color.z, accuracy: 1e-9)
        }
        XCTAssertTrue(LookAdjustments.neutral.isNeutral)
    }

    func testExposureDoublesAtOneStopBeforeClamping() {
        var look = LookAdjustments.neutral
        look.postExposure = 1
        let out = ToneMath.regulate(SIMD3(0.25, 0.25, 0.25), look)
        XCTAssertEqual(out.x, 0.5, accuracy: 1e-9)
    }

    func testZeroSaturationGivesGrey() {
        var look = LookAdjustments.neutral
        look.saturation = 0
        let out = ToneMath.regulate(SIMD3(0.9, 0.2, 0.1), look)
        XCTAssertEqual(out.x, out.y, accuracy: 1e-9)
        XCTAssertEqual(out.y, out.z, accuracy: 1e-9)
    }

    func testHighContrastSpreadsValuesAroundMiddleGrey() {
        var look = LookAdjustments.neutral
        look.contrast = 1.5
        XCTAssertLessThan(ToneMath.regulate(SIMD3(0.4, 0.4, 0.4), look).x, 0.4)
        XCTAssertGreaterThan(ToneMath.regulate(SIMD3(0.6, 0.6, 0.6), look).x, 0.6)
    }

    func testRollOffKeepsHighlightsBelowOneAndMonotonic() {
        var look = LookAdjustments.neutral
        look.dynamicRange = 0.5
        var previous = -1.0
        for step in 0 ... 20 {
            let value = ToneMath.regulate(SIMD3(Double(step) / 20, 0, 0), look).x
            XCTAssertLessThanOrEqual(value, 1)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
        XCTAssertLessThan(ToneMath.regulate(SIMD3(1, 1, 1), look).x, 1)
    }

    func testRegulatedOutputStaysInRange() {
        var look = LookAdjustments.neutral
        look.postExposure = 1
        look.contrast = 1.5
        look.saturation = 2
        look.temp = 1
        look.hue = 30
        look.shadows = 1
        look.highlights = 1
        let out = ToneMath.regulate(SIMD3(0.95, 0.1, 0.6), look)
        for channel in [out.x, out.y, out.z] {
            XCTAssertGreaterThanOrEqual(channel, 0)
            XCTAssertLessThanOrEqual(channel, 1)
        }
    }

    func testClampPullsValuesIntoRange() {
        var look = LookAdjustments.neutral
        look.contrast = 9
        look.grainSize = 0
        look.saturation = .nan
        look.clamp()
        XCTAssertEqual(look.contrast, 1.5)
        XCTAssertEqual(look.grainSize, 1)
        XCTAssertEqual(look.saturation, 0)
    }

    func testOlderFilesDecodeWithNeutralRegulators() throws {
        let json = #"{"contrast": 1.2}"#.data(using: .utf8)!
        let look = try JSONDecoder().decode(LookAdjustments.self, from: json)
        XCTAssertEqual(look.contrast, 1.2)
        XCTAssertEqual(look.saturation, 1)
        XCTAssertNil(look.curve)
    }

    func testPresetWithoutAdjustmentsGetsNeutral() throws {
        let json = #"{"id":"preset-1","name":"JaneSu","grain":0.5,"halation":0.6,"accentIndex":0}"#.data(using: .utf8)!
        let preset = try JSONDecoder().decode(Preset.self, from: json)
        XCTAssertEqual(preset.adjustments, .neutral)
    }

    func testRoundTripKeepsCurveAndValues() throws {
        var look = LookAdjustments.neutral
        ContrastCurve.crush.apply(to: &look)
        look.bloom = 0.4
        let data = try JSONEncoder().encode(look)
        let back = try JSONDecoder().decode(LookAdjustments.self, from: data)
        XCTAssertEqual(back, look)
        XCTAssertEqual(back.curve, .crush)
    }
}

final class FilmSpeedAndCurveTests: XCTestCase {
    func testSpeedTableMatchesMoodValues() {
        XCTAssertEqual(FilmSpeed.digi.grain, 0)
        XCTAssertEqual(FilmSpeed.iso800.grain, 0.5)
        XCTAssertEqual(FilmSpeed.iso800.sharpness, -0.1)
        XCTAssertEqual(FilmSpeed.iso3200.grainSize, 4)
        XCTAssertEqual(FilmSpeed.iso3200.chromaticAberration, 4)
        XCTAssertEqual(FilmSpeed.allCases.count, 7)
    }

    func testSpeedWritesGrainAndLookValues() {
        var grain = 0.0
        var look = LookAdjustments.neutral
        FilmSpeed.iso400.apply(grain: &grain, to: &look)
        XCTAssertEqual(grain, 0.3)
        XCTAssertEqual(look.grainSize, 3)
        XCTAssertEqual(look.sharpness, -0.05)
        XCTAssertEqual(look.chromaticAberration, 1)
    }

    func testEverySpeedStaysInsideRegulatorRanges() {
        for speed in FilmSpeed.allCases {
            var grain = 0.0
            var look = LookAdjustments.neutral
            speed.apply(grain: &grain, to: &look)
            let before = look
            look.clamp()
            XCTAssertEqual(look, before, "\(speed) is outside the regulator ranges")
            XCTAssertLessThanOrEqual(grain, 1)
        }
    }

    func testCurveWritesItsSettingsAndName() {
        var look = LookAdjustments.neutral
        ContrastCurve.ultra.apply(to: &look)
        XCTAssertEqual(look.contrast, 1.2)
        XCTAssertEqual(look.saturation, 1.075)
        XCTAssertEqual(look.fade, 0.06)
        XCTAssertEqual(look.curve, .ultra)
        XCTAssertEqual(ContrastCurve.allCases.count, 10)
    }

    func testEveryCurveStaysInsideRegulatorRanges() {
        for curve in ContrastCurve.allCases {
            var look = LookAdjustments.neutral
            curve.apply(to: &look)
            let before = look
            look.clamp()
            XCTAssertEqual(look, before, "\(curve) is outside the regulator ranges")
        }
    }
}

final class RegulatorUniformsTests: XCTestCase {
    func testNeutralLookMapsToNoOpUniforms() {
        let u = RegulatorUniforms(.neutral)
        XCTAssertEqual(u.exposure, 1)
        XCTAssertEqual(u.contrast, 1)
        XCTAssertEqual(u.shoulderKnee, 1)
        XCTAssertEqual(u.saturation, 1)
        XCTAssertFalse(u.hasHue)
        XCTAssertEqual(u.filmStrength, 1)
        XCTAssertEqual(u.grainSizeScale, 1)
    }

    func testMuteFoldsIntoSaturationAndGrainSizeScalesUp() {
        var look = LookAdjustments.neutral
        look.saturation = 1.5
        look.mute = 0.5
        look.grainSize = 4
        let u = RegulatorUniforms(look)
        XCTAssertEqual(u.saturation, 1.5 * 0.7, accuracy: 1e-9)
        XCTAssertEqual(u.grainSizeScale, 1 + 0.67 * 3, accuracy: 1e-9)
    }

    func testHueSetsRotationOnlyWhenNonZero() {
        var look = LookAdjustments.neutral
        look.hue = 90
        let u = RegulatorUniforms(look)
        XCTAssertTrue(u.hasHue)
        XCTAssertEqual(u.hueCos, 0, accuracy: 1e-9)
        XCTAssertEqual(u.hueSin, 1, accuracy: 1e-9)
    }
}
