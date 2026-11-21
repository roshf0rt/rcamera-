@testable import CameraCore
import XCTest

final class MotionExposureTests: XCTestCase {
    private let limits = CineExposure.Limits(minISO: 50, maxISO: 6400, minDuration: 1.0 / 20000, maxDuration: 1.0 / 3)

    /// `strikes` defaults to one short of `patience`, so a mode switch due on this step happens.
    private func step(
        _ mode: MotionExposure.Mode, iso: Double, duration: Double, offset: Double, fps: Int = 24,
        strikes: Int = MotionExposure.patience - 1
    ) -> MotionExposure.Decision {
        MotionExposure.step(mode: mode, current: .init(iso: iso, duration: duration), offset: offset, fps: fps, limits: limits, mainsHz: 50, strikes: strikes)
    }

    func testTakesOverAt180KeepingTheCamerasBrightness() throws {
        // The camera had picked 1/200 at ISO 400; at 24 fps in Europe the shutter goes to 1/50 and ISO drops.
        let decision = step(.native, iso: 400, duration: 1.0 / 200, offset: 0)
        XCTAssertEqual(decision.mode, .motion)
        XCTAssertEqual(decision.status, .cinematic)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertEqual(setting.duration, 1.0 / 50, accuracy: 1e-12)
        XCTAssertEqual(setting.iso * setting.duration, 400.0 / 200, accuracy: 1e-9)
    }

    func testRampsAFifthOfTheErrorPerStep() throws {
        let decision = step(.motion, iso: 400, duration: 1.0 / 50, offset: -1)
        XCTAssertEqual(decision.status, .settling)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertEqual(setting.duration, 1.0 / 50, accuracy: 1e-12)
        XCTAssertEqual(setting.iso, 400 * pow(2, 0.2), accuracy: 1e-6)
    }

    func testGreenOnceThePictureIsNearTarget() throws {
        XCTAssertEqual(step(.motion, iso: 400, duration: 1.0 / 50, offset: 0.4).status, .cinematic)
        XCTAssertEqual(step(.motion, iso: 400, duration: 1.0 / 50, offset: 0.6).status, .settling)
    }

    func testSmallErrorsAreLeftAlone() throws {
        let decision = step(.motion, iso: 400, duration: 1.0 / 50, offset: 0.05)
        XCTAssertEqual(decision.setting, .init(iso: 400, duration: 1.0 / 50))
        XCTAssertEqual(decision.status, .cinematic)
    }

    func testBendsTheShutterUpToAStopInBrightLight() throws {
        // At ISO 50 the picture is still half a stop too bright: the shutter gets faster.
        let decision = step(.motion, iso: 50, duration: 1.0 / 50, offset: 0.5)
        XCTAssertEqual(decision.mode, .motion)
        guard case .bent(let stops) = decision.status else { return XCTFail("expected bent, got \(decision.status)") }
        XCTAssertGreaterThan(stops, 0)
        XCTAssertLessThan(try XCTUnwrap(decision.setting).duration, 1.0 / 50)
    }

    func testHandsOverWhenTheLightIsOutOfReachAndTakesBackWithHysteresis() throws {
        // Two stops too bright at ISO 50: out of reach of 180°.
        let out = step(.motion, iso: 50, duration: 1.0 / 50, offset: 2)
        XCTAssertEqual(out.mode, .native)
        XCTAssertNil(out.setting)
        XCTAssertEqual(out.status, .handedOver(tooBright: true))

        // The camera runs 0.8 stops past ISO 50 at 1/50: not back yet (needs 0.7).
        let close = step(.native, iso: 50, duration: 1.0 / 50 / pow(2, 0.8), offset: 0)
        XCTAssertEqual(close.mode, .native)
        // At 0.5 stops it takes back, with the shutter bent by half a stop.
        let back = step(.native, iso: 50, duration: 1.0 / 50 / pow(2, 0.5), offset: 0)
        XCTAssertEqual(back.mode, .motion)
        guard case .bent(let stops) = back.status else { return XCTFail("expected bent, got \(back.status)") }
        XCTAssertEqual(stops, 0.5, accuracy: 1e-6)
    }

    func testWaitsBeforeSwitchingSoTheModesDoNotThrash() throws {
        // Within reach, but only for the first step: the camera keeps running, amber.
        let first = step(.native, iso: 130, duration: 1.0 / 40, offset: 0, strikes: 0)
        XCTAssertEqual(first.mode, .native)
        XCTAssertNil(first.setting)
        XCTAssertEqual(first.status, .settling)
        XCTAssertEqual(first.strikes, 1)
        // Out of reach for a moment only: the loop holds 180° with the shutter bent and counts.
        let flash = step(.motion, iso: 50, duration: 1.0 / 50, offset: 2, strikes: 0)
        XCTAssertEqual(flash.mode, .motion)
        XCTAssertEqual(flash.strikes, 1)
        guard case .bent = flash.status else { return XCTFail("expected bent, got \(flash.status)") }
        // Back within reach: the count starts again.
        XCTAssertEqual(step(.motion, iso: 400, duration: 1.0 / 50, offset: 0, strikes: 3).strikes, 0)
        // Leaving the reach resets the count of a camera waiting to take back.
        XCTAssertEqual(step(.native, iso: 50, duration: 1.0 / 400, offset: 0, strikes: 4).strikes, 0)
    }

    func testRoomLightAt24FpsGoesTo180() throws {
        // The camera's own choice in a lit room, 1/40 at ISO 130, is well within reach of 1/50.
        let decision = step(.native, iso: 130, duration: 1.0 / 40, offset: 0)
        XCTAssertEqual(decision.mode, .motion)
        XCTAssertEqual(decision.status, .cinematic)
        XCTAssertEqual(try XCTUnwrap(decision.setting).duration, 1.0 / 50, accuracy: 1e-12)
    }

    func testDarkNeverExposesLongerThanAFrame() throws {
        let decision = step(.motion, iso: 6400, duration: 1.0 / 50, offset: -0.9)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertLessThanOrEqual(setting.duration, 1.0 / 24 + 1e-12)
        XCTAssertLessThanOrEqual(setting.iso, 6400)
        let night = step(.motion, iso: 6400, duration: 1.0 / 24, offset: -3)
        XCTAssertEqual(night.status, .handedOver(tooBright: false))
    }
}

final class HoldShutterTests: XCTestCase {
    private let limits = CineExposure.Limits(minISO: 50, maxISO: 6400, minDuration: 1.0 / 20000, maxDuration: 1.0 / 3)

    private func step(
        _ mode: MotionExposure.Mode = .motion, iso: Double, duration: Double, offset: Double = 0, fps: Int = 24, mainsHz: Int? = 50, bias: Double = 0
    ) -> MotionExposure.Decision {
        MotionExposure.step(mode: mode, current: .init(iso: iso, duration: duration), offset: offset, fps: fps, limits: limits, mainsHz: mainsHz, policy: .holdShutter, bias: bias)
    }

    func testDimLightRaisesTheISONotTheShutter() throws {
        for iso in [800.0, 1600, 5000] {
            let decision = step(iso: iso, duration: 1.0 / 48, mainsHz: nil)
            let setting = try XCTUnwrap(decision.setting)
            XCTAssertEqual(setting.duration, 1.0 / 48, accuracy: 1e-12)
            XCTAssertEqual(setting.iso, iso, accuracy: 1e-6)
            XCTAssertEqual(decision.status, .cinematic)
        }
    }

    func testTheShutterSlowsOnlyPastTheHighestISOAndNeverPastAFrame() throws {
        let decision = step(iso: 12800, duration: 1.0 / 48, mainsHz: nil)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertEqual(setting.iso, 6400, accuracy: 1e-6)
        XCTAssertEqual(setting.duration, 1.0 / 24, accuracy: 1e-12)
        guard case .bent(let stops) = decision.status else { return XCTFail("expected bent, got \(decision.status)") }
        XCTAssertLessThan(stops, 0)
        let thirty = step(iso: 25600, duration: 1.0 / 60, fps: 30, mainsHz: nil)
        XCTAssertEqual(try XCTUnwrap(thirty.setting).duration, 1.0 / 30, accuracy: 1e-12)
        let night = step(iso: 6400, duration: 1.0 / 24, offset: -3)
        XCTAssertEqual(night.status, .handedOver(tooBright: false), "out of reach, said so")
        XCTAssertEqual(try XCTUnwrap(night.setting).duration, 1.0 / 24, accuracy: 1e-12)
    }

    func testThereIsNoJumpWhereTheISORunsOut() throws {
        let below = try XCTUnwrap(step(iso: 6399, duration: 1.0 / 48, mainsHz: nil).setting)
        let above = try XCTUnwrap(step(iso: 6401, duration: 1.0 / 48, mainsHz: nil).setting)
        XCTAssertEqual(below.duration, above.duration, accuracy: 1e-4)
        XCTAssertEqual(below.iso, above.iso, accuracy: 1)
    }

    func testBrightLightGlidesTheShutterInsteadOfHandingOver() throws {
        let out = step(iso: 50, duration: 1.0 / 50, offset: 2)
        XCTAssertEqual(out.mode, .motion)
        let setting = try XCTUnwrap(out.setting)
        XCTAssertEqual(setting.iso, 50, accuracy: 1e-9)
        XCTAssertEqual(log2((1.0 / 50) / setting.duration), MotionExposure.maxStep, accuracy: 1e-6, "one capped step")
        let first = step(.native, iso: 130, duration: 1.0 / 40)
        XCTAssertEqual(first.mode, .motion, "the camera's exposure is taken over on the first step")
        XCTAssertEqual(try XCTUnwrap(first.setting).duration, 1.0 / 50, accuracy: 1e-12)
    }

    func testBigChangesOfLightGlide() throws {
        let setting = try XCTUnwrap(step(iso: 400, duration: 1.0 / 50, offset: -3).setting)
        XCTAssertEqual(setting.iso, 400 * pow(2, MotionExposure.maxStep), accuracy: 1e-6)
        XCTAssertEqual(setting.duration, 1.0 / 50, accuracy: 1e-12)
    }

    func testETTRBiasExposesToTheRight() throws {
        let setting = try XCTUnwrap(step(iso: 400, duration: 1.0 / 50, bias: 0.7).setting)
        XCTAssertEqual(setting.duration, 1.0 / 50, accuracy: 1e-12)
        XCTAssertEqual(setting.iso, 400 * pow(2, 0.7 * MotionExposure.rate), accuracy: 1e-6)
        let held = step(iso: 400, duration: 1.0 / 50, offset: 0.7, bias: 0.7)
        XCTAssertEqual(held.setting, .init(iso: 400, duration: 1.0 / 50))
        XCTAssertEqual(held.status, .cinematic)
    }

    func testTheClassicLoopIsUnchanged() throws {
        // RCamera's loop still slows the shutter past the comfortable ISO.
        let classic = MotionExposure.step(mode: .motion, current: .init(iso: 1600, duration: 1.0 / 48), offset: 0, fps: 24, limits: limits)
        XCTAssertGreaterThan(try XCTUnwrap(classic.setting).duration, 1.0 / 48)
    }
}

final class MeterWatchTests: XCTestCase {
    func testADarkSceneIsLeftAlone() {
        var watch = MeterWatch()
        // Deep water: the loop is at its brightest, the meter says far too dark and the picture is dark.
        for _ in 0 ..< 200 {
            XCTAssertFalse(watch.check(offset: -4, pictureLuma: 0.05))
        }
    }

    func testChangingLightIsLeftAlone() {
        var watch = MeterWatch()
        for step in 0 ..< 200 {
            let offset = -3.5 * sin(Double(step) / 20)
            // Brighter picture when the meter says too bright, darker when too dark: they agree.
            XCTAssertFalse(watch.check(offset: offset, pictureLuma: 0.45 + offset / 10))
        }
    }

    func testBlackPictureWithAMeterSayingTooBrightTestsAgain() {
        var watch = MeterWatch()
        for _ in 1 ..< MeterWatch.stuckSteps {
            XCTAssertFalse(watch.check(offset: 4, pictureLuma: 0.02))
        }
        XCTAssertTrue(watch.check(offset: 4, pictureLuma: 0.02))
    }

    func testWhitePictureWithAMeterSayingTooDarkTestsAgain() {
        var watch = MeterWatch()
        var fired = false
        for _ in 0 ..< MeterWatch.stuckSteps { fired = watch.check(offset: -4, pictureLuma: 0.95) || fired }
        XCTAssertTrue(fired)
    }

    func testNoPictureReadingJudgesNothing() {
        var watch = MeterWatch()
        for _ in 0 ..< 100 { XCTAssertFalse(watch.check(offset: 4, pictureLuma: nil)) }
    }
}

final class HighlightGuardTests: XCTestCase {
    func testClippingTakesTheBiasBackAndClearSkiesReturnIt() {
        var guardrail = HighlightGuard(bias: 0.7)
        XCTAssertEqual(guardrail.update(target: 0.7, clippedShare: 0), 0.7)
        XCTAssertEqual(guardrail.update(target: 0.7, clippedShare: 0.05), 0.55, accuracy: 1e-9)
        for _ in 0 ..< 20 { guardrail.update(target: 0.7, clippedShare: 0.05) }
        XCTAssertEqual(guardrail.bias, HighlightGuard.floor, "never under the floor")
        // In between the limits it holds.
        XCTAssertEqual(guardrail.update(target: 0.7, clippedShare: 0.005), HighlightGuard.floor)
        guardrail.update(target: 0.7, clippedShare: 0)
        XCTAssertEqual(guardrail.bias, HighlightGuard.floor + HighlightGuard.risePerUpdate, accuracy: 1e-9)
        for _ in 0 ..< 200 { guardrail.update(target: 0.7, clippedShare: 0) }
        XCTAssertEqual(guardrail.bias, 0.7, accuracy: 1e-9, "back to the target, not past it")
        XCTAssertEqual(guardrail.update(target: 0.3, clippedShare: 0), 0.3, "a lower target applies at once")
        XCTAssertEqual(guardrail.update(target: 1, clippedShare: nil), 1, "nothing measured: the target")
    }

    func testOnlyAPileUpNearTheTopCountsAsClipping() {
        let spread = (0 ..< 100).map { 0.1 + Double($0) * 0.008 } // 0.1 ... 0.892, no pile-up
        XCTAssertEqual(HighlightMeter.clippedShare(levels: spread), 0.01, accuracy: 1e-9, "only the brightest sample")
        let clipped = Array(repeating: 0.4, count: 90) + Array(repeating: 0.9, count: 10)
        XCTAssertEqual(HighlightMeter.clippedShare(levels: clipped), 0.1, accuracy: 1e-9)
        let dim = Array(repeating: 0.3, count: 90) + Array(repeating: 0.6, count: 10)
        XCTAssertEqual(HighlightMeter.clippedShare(levels: dim), 0, "a low peak is no clip point")
        XCTAssertEqual(HighlightMeter.clippedShare(levels: []), 0)
        XCTAssertEqual(HighlightMeter.level(videoRangeCode: 64), 0)
        XCTAssertEqual(HighlightMeter.level(videoRangeCode: 940), 1)
        XCTAssertEqual(HighlightMeter.level(videoRangeCode: 1023), 1)
    }
}

final class HousingRemoteTests: XCTestCase {
    func testTheHousingsKeysMapAsItsOwnAppReadsThem() {
        XCTAssertEqual(HousingRemote.action(for: "1"), .zoomIn)
        XCTAssertEqual(HousingRemote.action(for: "2"), .zoomOut)
        XCTAssertEqual(HousingRemote.action(for: "3"), .flipCamera)
        XCTAssertEqual(HousingRemote.action(for: "4"), .photoMode)
        XCTAssertEqual(HousingRemote.action(for: "\r"), .videoMode)
        XCTAssertEqual(HousingRemote.action(for: "\n"), .videoMode)
        XCTAssertEqual(HousingRemote.action(for: " "), .shutter)
        XCTAssertNil(HousingRemote.action(for: "a"))
        XCTAssertNil(HousingRemote.action(for: ""))
    }

    func testZoomStepsStayInRange() {
        XCTAssertEqual(HousingRemote.zoom(1, .zoomIn, range: 0.5 ... 10), 1.25, accuracy: 1e-9)
        XCTAssertEqual(HousingRemote.zoom(1, .zoomOut, range: 0.5 ... 10), 0.8, accuracy: 1e-9)
        XCTAssertEqual(HousingRemote.zoom(0.55, .zoomOut, range: 0.5 ... 10), 0.5)
        XCTAssertEqual(HousingRemote.zoom(9.5, .zoomIn, range: 0.5 ... 10), 10)
        XCTAssertEqual(HousingRemote.zoom(2, .flipCamera, range: 0.5 ... 10), 2)
    }

    func testSettingsKeepTheHousingAndETTRChoices() throws {
        let fresh = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(fresh.housingKeys)
        XCTAssertEqual(fresh.logETTR, 0.7)
        XCTAssertFalse(fresh.motionHoldsShutter, "RCamera keeps the classic AutoMotion")
        var settings = AppSettings()
        settings.housingKeys = false
        settings.logETTR = 0.3
        settings.motionHoldsShutter = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.housingKeys)
        XCTAssertEqual(decoded.logETTR, 0.3)
        XCTAssertTrue(decoded.motionHoldsShutter)
        let wild = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"logETTR":9}"#.utf8))
        XCTAssertEqual(wild.logETTR, 1.5, "clamped")
    }
}

final class CameraChoiceSettingsTests: XCTestCase {
    func testSeparateCamerasAndAutoMacroStartOffAndSurviveARoundTrip() throws {
        var settings = AppSettings()
        XCTAssertFalse(settings.separateCameras)
        XCTAssertFalse(settings.autoMacro)
        settings.separateCameras = true
        settings.autoMacro = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.separateCameras)
        XCTAssertTrue(decoded.autoMacro)
    }

    func testOldSettingsFilesGetBothOff() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(decoded.separateCameras)
        XCTAssertFalse(decoded.autoMacro)
    }
}

final class MotionComfortTests: XCTestCase {
    private let limits = CineExposure.Limits(minISO: 50, maxISO: 6400, minDuration: 1.0 / 20000, maxDuration: 1.0 / 3)

    private func step(iso: Double, duration: Double, fps: Int = 24) -> MotionExposure.Decision {
        MotionExposure.step(mode: .motion, current: .init(iso: iso, duration: duration), offset: 0, fps: fps, limits: limits, mainsHz: nil)
    }

    func testComfortISOIsTwentyFiveTimesTheLowest() {
        XCTAssertEqual(MotionExposure.comfortISO(limits: limits), 1250)
        XCTAssertEqual(MotionExposure.comfortISO(limits: .init(minISO: 32, maxISO: 3000, minDuration: 0.0001, maxDuration: 0.3)), 800)
        // Never past what the camera can do.
        XCTAssertEqual(MotionExposure.comfortISO(limits: .init(minISO: 100, maxISO: 1000, minDuration: 0.0001, maxDuration: 0.3)), 1000)
    }

    func testComfortableISOKeepsTheShutterOn180() throws {
        let decision = step(iso: 800, duration: 1.0 / 48)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertEqual(setting.duration, 1.0 / 48, accuracy: 1e-12)
        XCTAssertEqual(setting.iso, 800, accuracy: 1e-6)
        XCTAssertEqual(decision.status, .cinematic)
    }

    func testDimLightSlowsTheShutterBeforeTheISOClimbs() throws {
        // ISO 1600 at 1/48 would be 800 at 1/24 (a stop slower); the ISO stops at 1250 and the shutter makes up the rest.
        let decision = step(iso: 1600, duration: 1.0 / 48)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertEqual(setting.iso, 1250, accuracy: 1e-6)
        XCTAssertEqual(setting.iso * setting.duration, 1600.0 / 48, accuracy: 1e-9)
        XCTAssertGreaterThan(setting.duration, 1.0 / 48)
        guard case .bent(let stops) = decision.status else { return XCTFail("expected bent, got \(decision.status)") }
        XCTAssertLessThan(stops, 0)
    }

    func testTheShutterNeverGoesPastAStopOrAFrame() throws {
        let decision = step(iso: 5000, duration: 1.0 / 48)
        let setting = try XCTUnwrap(decision.setting)
        XCTAssertEqual(setting.duration, 1.0 / 24, accuracy: 1e-12)
        XCTAssertEqual(setting.iso, 2500, accuracy: 1e-6)
        // At 30 fps a frame is 1/30, which is under a stop past 1/60: the frame time is the limit.
        let thirty = step(iso: 5000, duration: 1.0 / 60, fps: 30)
        XCTAssertEqual(try XCTUnwrap(thirty.setting).duration, 1.0 / 30, accuracy: 1e-12)
    }

    func testThereIsNoJumpWhereTheComfortLimitIsCrossed() throws {
        let below = try XCTUnwrap(step(iso: 1249, duration: 1.0 / 48).setting)
        let above = try XCTUnwrap(step(iso: 1251, duration: 1.0 / 48).setting)
        XCTAssertEqual(below.duration, above.duration, accuracy: 1e-4)
    }
}

final class ExposureAssistTests: XCTestCase {
    func testFalseColourBands() throws {
        XCTAssertEqual(ExposureAssist.band(luma: 0.01), .crushed)
        XCTAssertEqual(ExposureAssist.band(luma: 0.05), .shadow)
        XCTAssertEqual(ExposureAssist.band(luma: 0.46), .middleGrey)
        XCTAssertEqual(ExposureAssist.band(luma: 0.64), .skin)
        XCTAssertEqual(ExposureAssist.band(luma: 0.95), .nearClip)
        XCTAssertEqual(ExposureAssist.band(luma: 1.0), .clipped)
        XCTAssertEqual(ExposureAssist.band(luma: 0.3), .other)
        XCTAssertEqual(ExposureAssist.falseColor(luma: 0.3), SIMD3(repeating: 0.3 * 0.85))
    }

    func testZebraStripesAlternateDiagonally() throws {
        XCTAssertTrue(ExposureAssist.zebraStripe(x: 0, y: 0, phase: 0))
        XCTAssertFalse(ExposureAssist.zebraStripe(x: 8, y: 0, phase: 0))
        XCTAssertFalse(ExposureAssist.zebraStripe(x: 4, y: 4, phase: 0))
        XCTAssertTrue(ExposureAssist.zebraStripe(x: 4, y: 4, phase: 8))
    }

    func testWhiteBalanceLabels() throws {
        XCTAssertEqual(WhiteBalanceSteps.label(kelvin: nil), "AUTO")
        XCTAssertEqual(WhiteBalanceSteps.label(kelvin: 5600), "5600K")
        XCTAssertTrue(WhiteBalanceSteps.tints.contains(0))
    }
}

final class WaveformTests: XCTestCase {
    /// Left half black, right half white, `width` × `height` BGRA.
    private func halves(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in width / 2 ..< width {
                let i = (y * width + x) * 4
                pixels[i] = 255
                pixels[i + 1] = 255
                pixels[i + 2] = 255
                pixels[i + 3] = 255
            }
        }
        return pixels
    }

    func testColumnsFollowThePictureAndLevelsItsBrightness() throws {
        let width = 64, height = 8
        let waveform = halves(width: width, height: height).withUnsafeBytes {
            Waveform.measure(bgra: $0, width: width, height: height, bytesPerRow: width * 4, columns: 8, levels: 16, rows: 8)
        }
        XCTAssertEqual(waveform.samplesPerColumn, 16)
        XCTAssertEqual(waveform.counts[0 * 16 + 0], 16, "left column: black")
        XCTAssertEqual(waveform.counts[7 * 16 + 15], 16, "right column: white at the top")
        XCTAssertEqual(waveform.intensity(column: 7, level: 15), 1)
        XCTAssertEqual(waveform.intensity(column: 7, level: 3), 0)

        let image = waveform.render()
        XCTAssertEqual(image.count, 8 * 16 * 4)
        // Top row, right column: the dense trace is white; top row, left column: empty.
        let top = (0 * 8 + 7) * 4
        XCTAssertEqual(Array(image[top ..< top + 4]), [255, 255, 255, 255])
        XCTAssertEqual(Array(image[0 ..< 4]), [0, 0, 0, 0])
    }

    func testColumnsRunAcrossThePictureAsThePhoneIsHeld() throws {
        // Held portrait: across is x. Turned top-left (1): across is down the frame. Top-right (-1): up it.
        XCTAssertEqual(Waveform.column(x: 0, y: 0, width: 100, height: 200, columns: 10, quarterTurns: 0), 0)
        XCTAssertEqual(Waveform.column(x: 99, y: 0, width: 100, height: 200, columns: 10, quarterTurns: 0), 9)
        XCTAssertEqual(Waveform.column(x: 99, y: 0, width: 100, height: 200, columns: 10, quarterTurns: 1), 0)
        XCTAssertEqual(Waveform.column(x: 0, y: 199, width: 100, height: 200, columns: 10, quarterTurns: 1), 9)
        XCTAssertEqual(Waveform.column(x: 0, y: 199, width: 100, height: 200, columns: 10, quarterTurns: -1), 0)
        XCTAssertEqual(Waveform.column(x: 0, y: 0, width: 100, height: 200, columns: 10, quarterTurns: -1), 9)

        // Black left, white right, held sideways: every column sees both halves.
        let width = 64, height = 64
        let turned = halves(width: width, height: height).withUnsafeBytes {
            Waveform.measure(bgra: $0, width: width, height: height, bytesPerRow: width * 4, columns: 8, levels: 16, rows: 64, quarterTurns: 1)
        }
        XCTAssertGreaterThan(turned.counts[0 * 16 + 0], 0)
        XCTAssertGreaterThan(turned.counts[0 * 16 + 15], 0)
    }

    func testStrayPixelsStayFaint() throws {
        var flat = [UInt32](repeating: 0, count: 64)
        flat[10] = 2
        flat[40] = 398
        let waveform = Waveform(columns: 1, levels: 64, flat: flat, samplesPerColumn: 400)
        XCTAssertLessThan(waveform.intensity(column: 0, level: 10), 0.25)
        XCTAssertEqual(waveform.intensity(column: 0, level: 40), 1)
    }

    func testEmptyPictureMeasuresNothing() throws {
        let waveform = [UInt8]().withUnsafeBytes { Waveform.measure(bgra: $0, width: 0, height: 0, bytesPerRow: 0) }
        XCTAssertEqual(waveform.samplesPerColumn, 0)
        XCTAssertEqual(waveform.intensity(column: 0, level: 0), 0)
    }
}

final class HistogramTests: XCTestCase {
    /// `width` × `height` BGRA pixels of one colour.
    private func solid(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = blue
            pixels[i + 1] = green
            pixels[i + 2] = red
        }
        return pixels
    }

    func testEachChannelIsCountedInItsOwnBins() {
        let pixels = solid(width: 16, height: 16, red: 255, green: 128, blue: 0)
        let histogram = pixels.withUnsafeBytes {
            Histogram.measure(pixels: $0, width: 16, height: 16, bytesPerRow: 64, bins: 16)
        }
        XCTAssertEqual(histogram.samples, 256)
        XCTAssertEqual(histogram.count(.red, bin: 15), 256)
        XCTAssertEqual(histogram.count(.green, bin: 8), 256)
        XCTAssertEqual(histogram.count(.blue, bin: 0), 256)
        // Luma of (1, 0.5, 0) is 0.59.
        XCTAssertEqual(histogram.count(.luma, bin: histogram.bin(of: 0.299 + 0.587 * 128 / 255)), 256)
        // The same bytes read as RGBA swap red and blue.
        let swapped = pixels.withUnsafeBytes {
            Histogram.measure(pixels: $0, width: 16, height: 16, bytesPerRow: 64, redFirst: true, bins: 16)
        }
        XCTAssertEqual(swapped.count(.blue, bin: 15), 256)
        XCTAssertEqual(swapped.count(.red, bin: 0), 256)
    }

    func testLargePicturesAreSampledNotCountedWhole() {
        let pixels = solid(width: 400, height: 300, red: 90, green: 90, blue: 90)
        let histogram = pixels.withUnsafeBytes {
            Histogram.measure(pixels: $0, width: 400, height: 300, bytesPerRow: 1600, maxSamples: 3000)
        }
        XCTAssertLessThanOrEqual(histogram.samples, 3000)
        XCTAssertGreaterThan(histogram.samples, 1500)
    }

    func testHeightsAreAgainstTheTallestInnerBin() {
        // 100 samples at mid grey, 50 a little brighter, 400 clipped white.
        var flat = [UInt32](repeating: 0, count: 64)
        for channel in 0 ..< 4 {
            flat[channel * 16 + 8] = 100
            flat[channel * 16 + 10] = 50
            flat[channel * 16 + 15] = 400
        }
        let histogram = Histogram(bins: 16, flat: flat)
        XCTAssertEqual(histogram.samples, 550)
        XCTAssertEqual(histogram.peak, 100, "the clipped end does not set the scale")
        let heights = histogram.heights(.luma)
        XCTAssertEqual(heights[8], 1)
        XCTAssertEqual(heights[10], 0.5)
        XCTAssertEqual(heights[15], 1, "and stops at the top")
        XCTAssertEqual(heights[3], 0)
    }

    func testClippedAndCrushedSharesReadTheEnds() {
        var flat = [UInt32](repeating: 0, count: 128 * 4)
        for channel in 0 ..< 4 { flat[channel * 128 + 60] = 900 }
        flat[3 * 128 + 60] = 800
        flat[3 * 128 + 0] = 100 // a tenth of the luma is black
        flat[0 * 128 + 60] = 700
        flat[0 * 128 + 127] = 200 // red clips in a fifth of the picture
        let histogram = Histogram(bins: 128, flat: flat)
        XCTAssertEqual(histogram.samples, 900)
        XCTAssertEqual(histogram.crushedShare, 100.0 / 900, accuracy: 1e-9)
        XCTAssertEqual(histogram.clippedShare, 200.0 / 900, accuracy: 1e-9)
    }

    func testNothingMeasuredDrawsNothing() {
        let empty = [UInt8]().withUnsafeBytes { Histogram.measure(pixels: $0, width: 0, height: 0, bytesPerRow: 0) }
        XCTAssertEqual(empty.samples, 0)
        XCTAssertEqual(empty.peak, 0)
        XCTAssertEqual(empty.heights(.red).max(), 0)
        XCTAssertEqual(empty.clippedShare, 0)
        XCTAssertEqual(Histogram(bins: 8, flat: [1, 2]).samples, 0, "too few counts are ignored")
    }
}

final class HardwareBudgetTests: XCTestCase {
    func testLighterFormatsStepDownFrameRateFirst() throws {
        let uhd120 = VideoFormat(width: 3840, height: 2160, fps: 120)
        XCTAssertEqual(FormatChooser.lighter(than: uhd120), VideoFormat(width: 3840, height: 2160, fps: 60))
        XCTAssertEqual(FormatChooser.lighter(than: VideoFormat(width: 3840, height: 2160, fps: 60)), VideoFormat(width: 3840, height: 2160, fps: 30))
        XCTAssertEqual(FormatChooser.lighter(than: VideoFormat(width: 3840, height: 2160, fps: 24)), VideoFormat(width: 1920, height: 1080, fps: 24))
        XCTAssertNil(FormatChooser.lighter(than: .hd1080p30))
    }
}

final class ProSettingsTests: XCTestCase {
    func testOldSettingsGetAutoMotionOnAndToolsOff() throws {
        let old = #"{"cineExposure": false, "videoFPS": 24}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertTrue(settings.autoMotion)
        XCTAssertFalse(settings.zebra || settings.focusPeaking || settings.falseColor || settings.histogram || settings.waveform)
        XCTAssertNil(settings.whiteBalanceKelvin)
        XCTAssertEqual(settings.videoFPS, 24)
    }

    func testProSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.zebra = true
        settings.histogram = true
        settings.waveform = true
        settings.lockWhiteBalanceWhileRecording = true
        settings.whiteBalanceKelvin = 5600
        settings.whiteBalanceTint = -15
        settings.autoMotion = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}

final class MeterTests: XCTestCase {
    func testABrighterPictureReadingHigherIsPositive() {
        XCTAssertEqual(MotionExposure.Meter.sign(before: 0, after: 0.55, stops: 0.6), 1)
        XCTAssertEqual(MotionExposure.Meter.sign(before: 0.1, after: -0.45, stops: -0.6), 1)
    }

    func testABrighterPictureReadingLowerIsNegative() {
        XCTAssertEqual(MotionExposure.Meter.sign(before: 0, after: -0.5, stops: 0.6), -1)
        XCTAssertEqual(MotionExposure.Meter.sign(before: 0, after: 0.5, stops: -0.6), -1)
    }

    func testAMeterThatDoesNotMoveIsCaught() {
        XCTAssertEqual(MotionExposure.Meter.sign(before: 0.02, after: 0.08, stops: 0.6), 0)
        XCTAssertEqual(MotionExposure.Meter.sign(before: 0, after: 0, stops: 0), 0)
    }

    func testTheTestGoesBrighterWhenThereIsRoomAndDarkerWhenThereIsNot() throws {
        let limits = CineExposure.Limits(minISO: 25, maxISO: 3000, minDuration: 1.0 / 8000, maxDuration: 1.0 / 3)
        let room = try XCTUnwrap(MotionExposure.Meter.probe(current: .init(iso: 400, duration: 1.0 / 48), limits: limits))
        XCTAssertEqual(room.stops, MotionExposure.Meter.probeStops)
        XCTAssertEqual(room.setting.iso, 400 * pow(2, MotionExposure.Meter.probeStops), accuracy: 1e-6)
        XCTAssertEqual(room.setting.duration, 1.0 / 48, "the shutter stays")

        let night = try XCTUnwrap(MotionExposure.Meter.probe(current: .init(iso: 2800, duration: 1.0 / 24), limits: limits))
        XCTAssertEqual(night.stops, -MotionExposure.Meter.probeStops)
        XCTAssertLessThan(night.setting.iso, 2800)
    }

    func testNoTestWhereTheISORangeHasNoRoom() {
        let limits = CineExposure.Limits(minISO: 100, maxISO: 120, minDuration: 1.0 / 8000, maxDuration: 1.0 / 3)
        XCTAssertNil(MotionExposure.Meter.probe(current: .init(iso: 110, duration: 1.0 / 48), limits: limits))
    }
}
