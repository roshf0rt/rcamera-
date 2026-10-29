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
        XCTAssertEqual(setting.iso, 6400)
        let night = step(.motion, iso: 6400, duration: 1.0 / 24, offset: -3)
        XCTAssertEqual(night.status, .handedOver(tooBright: false))
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
        XCTAssertFalse(settings.zebra || settings.focusPeaking || settings.falseColor || settings.waveform)
        XCTAssertNil(settings.whiteBalanceKelvin)
        XCTAssertEqual(settings.videoFPS, 24)
    }

    func testProSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.zebra = true
        settings.waveform = true
        settings.lockWhiteBalanceWhileRecording = true
        settings.whiteBalanceKelvin = 5600
        settings.whiteBalanceTint = -15
        settings.autoMotion = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}
