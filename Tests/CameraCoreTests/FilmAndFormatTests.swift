@testable import CameraCore
import XCTest

final class FilmMathTests: XCTestCase {
    func testHalationMaskIsZeroBelowThresholdAndFullAtWhite() {
        XCTAssertEqual(FilmMath.halationMask(luma: 0.5), 0)
        XCTAssertEqual(FilmMath.halationMask(luma: 0.55), 0)
        XCTAssertEqual(FilmMath.halationMask(luma: 1), 1, accuracy: 1e-5)
        XCTAssertLessThan(FilmMath.halationMask(luma: 0.7), FilmMath.halationMask(luma: 0.9))
    }

    func testHalationLeavesHighlightsAloneAndTintsShadowsRed() {
        let white = FilmMath.applyHalation(r: 1, g: 1, b: 1, glow: 1, strength: 4.5)
        XCTAssertEqual(white.0, 1)
        XCTAssertEqual(white.1, 1)
        XCTAssertEqual(white.2, 1)

        let dark = FilmMath.applyHalation(r: 0.1, g: 0.1, b: 0.1, glow: 0.2, strength: 2.7)
        XCTAssertGreaterThan(dark.0, dark.1)
        XCTAssertGreaterThan(dark.1, dark.2)

        let none = FilmMath.applyHalation(r: 0.2, g: 0.3, b: 0.4, glow: 0, strength: 4.5)
        XCTAssertEqual(none.0, 0.2, accuracy: 1e-6)
        XCTAssertEqual(none.2, 0.4, accuracy: 1e-6)
    }

    func testGrainWeightPeaksInMidtones() {
        XCTAssertEqual(FilmMath.grainWeight(luma: 0), 0.18, accuracy: 1e-6)
        XCTAssertEqual(FilmMath.grainWeight(luma: 0.5), 0.68, accuracy: 1e-6)
        XCTAssertEqual(FilmMath.grainWeight(luma: 1), 0.12, accuracy: 1e-6)
    }

    func testGrainTextureIsCenteredSoftAndDeterministic() {
        let size = 64
        let texture = FilmMath.grainTexture(size: size, seed: 7)
        XCTAssertEqual(texture.count, size * size)
        XCTAssertEqual(texture, FilmMath.grainTexture(size: size, seed: 7))
        XCTAssertNotEqual(texture, FilmMath.grainTexture(size: size, seed: 8))

        let mean = texture.reduce(0, +) / Float(texture.count)
        let deviation = (texture.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(texture.count)).squareRoot()
        XCTAssertEqual(mean, 0.5, accuracy: 0.01)
        XCTAssertEqual(deviation, FilmMath.grainDeviation, accuracy: 0.01)

        // Neighbours are correlated after the blur, so the grain is not single-pixel sparkle.
        var correlation: Float = 0
        for y in 0 ..< size {
            for x in 0 ..< size {
                correlation += (texture[y * size + x] - 0.5) * (texture[y * size + (x + 1) % size] - 0.5)
            }
        }
        correlation /= Float(texture.count) * deviation * deviation
        XCTAssertGreaterThan(correlation, 0.3)
    }

    func testGrainAtDefaultAmountIsSubtle() {
        // A mid-grey pixel moved by two standard deviations of grain stays within a few code values.
        let intensity = FilmMath.grainIntensity(0.5)
        let shifted = FilmMath.applyGrain(0.5, luma: 0.5, noise: 0.5 + 2 * FilmMath.grainDeviation, intensity: intensity)
        XCTAssertLessThan((shifted - 0.5) * 255, 12)
        XCTAssertGreaterThan((shifted - 0.5) * 255, 2)
    }

    func testAppleLogDecodeOfVideoRangeCodes() {
        let black = FilmMath.appleLogRGB(y: 64, cb: 512, cr: 512)
        XCTAssertEqual(black.0, 0, accuracy: 1e-6)
        let white = FilmMath.appleLogRGB(y: 940, cb: 512, cr: 512)
        XCTAssertEqual(white.0, 1, accuracy: 1e-6)
        XCTAssertEqual(white.1, 1, accuracy: 1e-6)
        XCTAssertEqual(white.2, 1, accuracy: 1e-6)
        let reddish = FilmMath.appleLogRGB(y: 500, cb: 480, cr: 700)
        XCTAssertGreaterThan(reddish.0, reddish.1)
    }
}

final class FormatChooserTests: XCTestCase {
    /// Roughly what a recent iPhone wide camera lists.
    private let formats = [
        FormatDescriptor(index: 0, width: 1280, height: 720, maxFPS: 240),
        FormatDescriptor(index: 1, width: 1920, height: 1080, maxFPS: 60, isFullRange8Bit: false),
        FormatDescriptor(index: 2, width: 1920, height: 1080, maxFPS: 60),
        FormatDescriptor(index: 3, width: 1920, height: 1080, maxFPS: 240),
        FormatDescriptor(index: 4, width: 1920, height: 1440, maxFPS: 60, maxPhotoPixels: 48_000_000),
        FormatDescriptor(index: 5, width: 1920, height: 1080, maxFPS: 60, supportsAppleLog: true, isFullRange8Bit: false),
        FormatDescriptor(index: 6, width: 3840, height: 2160, maxFPS: 60),
        FormatDescriptor(index: 7, width: 3840, height: 2160, maxFPS: 60, supportsAppleLog: true, isFullRange8Bit: false),
        FormatDescriptor(index: 8, width: 4032, height: 3024, maxFPS: 30, maxPhotoPixels: 48_000_000),
        FormatDescriptor(index: 9, width: 1440, height: 1080, maxFPS: 60, maxPhotoPixels: 12_000_000),
    ]

    func testPhotoUsesThe1920x1440Stream() {
        XCTAssertEqual(FormatChooser.photoFormat(formats)?.index, 4)
    }

    func testSDR1080VideoSharesThePhotoFormat() {
        let photo = FormatChooser.photoFormat(formats)
        let choice = FormatChooser.videoFormat(formats, width: 1920, fps: 30, appleLog: false, photo: photo)
        XCTAssertEqual(choice, VideoFormatChoice(format: formats[4], sharedWithPhoto: true, appleLog: false))
        XCTAssertEqual(FormatChooser.videoFormat(formats, width: 1920, fps: 60, appleLog: false, photo: photo)?.sharedWithPhoto, true)
    }

    func testFrameRatesThePhotoFormatLacksGetTheirOwnFormat() {
        let photo = FormatDescriptor(index: 4, width: 1920, height: 1440, maxFPS: 30)
        let choice = FormatChooser.videoFormat(formats, width: 1920, fps: 60, appleLog: false, photo: photo)
        XCTAssertEqual(choice?.format.index, 2, "full range, and not the 240 fps binned format")
        XCTAssertEqual(choice?.sharedWithPhoto, false)
    }

    func testAppleLogAnd4K() {
        let photo = FormatChooser.photoFormat(formats)
        XCTAssertEqual(FormatChooser.videoFormat(formats, width: 1920, fps: 30, appleLog: true, photo: photo),
                       VideoFormatChoice(format: formats[5], sharedWithPhoto: false, appleLog: true))
        XCTAssertEqual(FormatChooser.videoFormat(formats, width: 3840, fps: 30, appleLog: true, photo: photo)?.format.index, 7)
        XCTAssertEqual(FormatChooser.videoFormat(formats, width: 3840, fps: 30, appleLog: false, photo: photo)?.format.index, 6)
    }

    func testAppleLogFallsBackToSDRWhenUnsupported() {
        let front = [
            FormatDescriptor(index: 0, width: 1920, height: 1440, maxFPS: 30, maxPhotoPixels: 12_000_000),
            FormatDescriptor(index: 1, width: 1920, height: 1080, maxFPS: 60),
        ]
        let photo = FormatChooser.photoFormat(front)
        let choice = FormatChooser.videoFormat(front, width: 1920, fps: 30, appleLog: true, photo: photo)
        XCTAssertEqual(choice, VideoFormatChoice(format: front[0], sharedWithPhoto: true, appleLog: false))
        XCTAssertNil(FormatChooser.videoFormat(front, width: 3840, fps: 30, appleLog: false, photo: photo))
    }
}

final class CaptureRecordDecodingTests: XCTestCase {
    func testRecordsWithoutMirroredKeyStillDecode() throws {
        let json = #"{"id":"8D2C1E3A-7A64-4C4E-9E7E-3C1B2A0F5D11","date":0,"kind":"photo","presetID":"preset-1"}"#
        let record = try JSONDecoder().decode(CaptureRecord.self, from: Data(json.utf8))
        XCTAssertFalse(record.mirrored)
        XCTAssertTrue(record.grainEnabled)
        XCTAssertTrue(record.halationEnabled)
    }
}

final class LUTProfileTests: XCTestCase {
    private func makeLUT(size: Int = 17, _ transform: (Float, Float, Float) -> (Float, Float, Float)) throws -> LUT3D {
        var values: [Float] = []
        let scale = Float(size - 1)
        for b in 0 ..< size {
            for g in 0 ..< size {
                for r in 0 ..< size {
                    let out = transform(Float(r) / scale, Float(g) / scale, Float(b) / scale)
                    values += [min(max(out.0, 0), 1), min(max(out.1, 0), 1), min(max(out.2, 0), 1), 1]
                }
            }
        }
        return try LUT3D(size: size, rgba: values)
    }

    func testIdentityIsNatural() throws {
        let profile = LUTProfile(lut: try LUT3D.identity(size: 17))
        XCTAssertEqual(profile.tags, ["Natural"])
        XCTAssertEqual(profile.contrast, 1, accuracy: 0.01)
        XCTAssertEqual(profile.saturation, 1, accuracy: 0.01)
        XCTAssertEqual(profile.skinHueShift, 0, accuracy: 0.5)
    }

    func testWarmLUT() throws {
        let profile = LUTProfile(lut: try makeLUT { r, g, b in (r + 0.06, g, b - 0.06) })
        XCTAssertEqual(profile.tags.first, "Warm")
    }

    func testBlackAndWhite() throws {
        let profile = LUTProfile(lut: try makeLUT { r, g, b in
            let y = 0.3 * r + 0.59 * g + 0.11 * b
            return (y, y, y)
        })
        XCTAssertEqual(profile.tags, ["Black & White"])
    }

    func testFadedSoftLook() throws {
        let profile = LUTProfile(lut: try makeLUT { r, g, b in (0.12 + 0.75 * r, 0.12 + 0.75 * g, 0.12 + 0.75 * b) })
        XCTAssertTrue(profile.tags.contains("Faded"))
        XCTAssertTrue(profile.tags.contains("Soft"))
    }

    func testTealAndOrange() throws {
        let profile = LUTProfile(lut: try makeLUT { r, g, b in
            let y = (r + g + b) / 3
            let shift: Float = (y - 0.5) * 0.3
            return (r + shift, g, b - shift)
        })
        XCTAssertEqual(profile.tags.first, "Teal & Orange")
    }

    func testCardArtFollowsTheLUT() throws {
        let plain = LUTCardArt.render(lut: nil, width: 24, height: 16)
        XCTAssertEqual(plain.count, 24 * 16 * 4)
        XCTAssertEqual(plain, LUTCardArt.render(lut: try LUT3D.identity(size: 17), width: 24, height: 16).enumerated().map { index, value in
            // Identity can differ by a rounding step.
            abs(Int(value) - Int(plain[index])) <= 1 ? plain[index] : value
        })
        let mono = LUTCardArt.render(lut: try makeLUT { r, g, b in
            let y = (r + g + b) / 3
            return (y, y, y)
        }, width: 24, height: 16)
        for index in stride(from: 0, to: mono.count, by: 4) {
            XCTAssertLessThanOrEqual(abs(Int(mono[index]) - Int(mono[index + 2])), 1)
        }
    }
}

final class AppleLogTests: XCTestCase {
    func testCurveRoundTrips() {
        for r: Float in [-0.05, 0, 0.005, 0.01, 0.18, 0.9, 4, 20] {
            XCTAssertEqual(AppleLog.decode(AppleLog.encode(r)), r, accuracy: max(1e-4, r * 1e-4))
        }
        XCTAssertEqual(AppleLog.encode(0.18), 0.488, accuracy: 0.002)
    }

    func testMidGreyIsNeutralAndWhereRec709PutsIt() {
        let grey = AppleLog.encode(0.18)
        let out = AppleLog.toRec709(r: grey, g: grey, b: grey)
        XCTAssertEqual(out.0, 0.409, accuracy: 0.01)
        XCTAssertEqual(out.0, out.1, accuracy: 0.005)
        XCTAssertEqual(out.1, out.2, accuracy: 0.005)
    }

    func testHighlightsRollOffInsteadOfClipping() {
        let one = AppleLog.encode(1)
        let two = AppleLog.encode(2)
        let a = AppleLog.toRec709(r: one, g: one, b: one).0
        let b = AppleLog.toRec709(r: two, g: two, b: two).0
        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, 1.0001)
        XCTAssertGreaterThan(a, 0.85)
    }

    func testNeutralLUTFollowedByAnotherLUT() throws {
        let neutral = AppleLog.neutralRec709LUT(size: 17)
        let grey = AppleLog.encode(0.18)
        let direct = neutral.apply(r: grey, g: grey, b: grey)
        XCTAssertEqual(direct.r, 0.409, accuracy: 0.02)

        let invert = try LUT3D(size: 2, rgba: [1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1])
        let chained = neutral.followed(by: invert).apply(r: grey, g: grey, b: grey)
        XCTAssertEqual(chained.r, 1 - direct.r, accuracy: 0.01)
    }
}

final class CineExposureTests: XCTestCase {
    private let limits = CineExposure.Limits(minISO: 50, maxISO: 3200, minDuration: 1.0 / 20000, maxDuration: 1.0 / 3)

    func testShutterFollowsTheHundredEightyDegreeRule() {
        XCTAssertEqual(CineExposure.shutter(fps: 24), 1.0 / 48, accuracy: 1e-12)
        XCTAssertEqual(CineExposure.shutter(fps: 30), 1.0 / 60, accuracy: 1e-12)
        XCTAssertEqual(CineExposure.shutter(fps: 120), 1.0 / 240, accuracy: 1e-12)
    }

    func testISOCarriesTheExposureAtTheCineShutter() {
        // Auto exposure had picked 1/120 at ISO 400; at 24 fps the shutter moves to 1/48 and ISO drops to keep the light.
        let start = CineExposure.Setting(iso: 400, duration: 1.0 / 120)
        let next = CineExposure.next(current: start, offset: 0, fps: 24, limits: limits)
        XCTAssertEqual(next.duration, 1.0 / 48, accuracy: 1e-12)
        XCTAssertEqual(next.iso * next.duration, start.iso * start.duration, accuracy: 1e-9)
    }

    func testTooBrightLowersISOAndOnlyThenShortensTheShutter() {
        let start = CineExposure.Setting(iso: 100, duration: 1.0 / 48)
        let darker = CineExposure.next(current: start, offset: 1, fps: 24, limits: limits)
        XCTAssertEqual(darker.duration, 1.0 / 48, accuracy: 1e-12)
        XCTAssertLessThan(darker.iso, 100)

        let sunny = CineExposure.Setting(iso: 50, duration: 1.0 / 48)
        let faster = CineExposure.next(current: sunny, offset: 3, fps: 24, limits: limits)
        XCTAssertEqual(faster.iso, 50)
        XCTAssertLessThan(faster.duration, 1.0 / 48, "no ND filter: the shutter has to give way")
    }

    func testTooDarkRaisesISOAndNeverExposesLongerThanAFrame() {
        let night = CineExposure.Setting(iso: 3200, duration: 1.0 / 48)
        let slower = CineExposure.next(current: night, offset: -4, fps: 24, limits: limits)
        XCTAssertEqual(slower.iso, 3200)
        XCTAssertGreaterThan(slower.duration, 1.0 / 48)
        XCTAssertLessThanOrEqual(slower.duration, 1.0 / 24 + 1e-12)
    }

    func testSmallOffsetsAreLeftAlone() {
        let start = CineExposure.Setting(iso: 200, duration: 1.0 / 48)
        XCTAssertEqual(CineExposure.next(current: start, offset: 0.03, fps: 24, limits: limits), start)
        XCTAssertEqual(CineExposure.readout(start), "1/48 · ISO 200")
    }

    func testFrameRatesOnlyListWhatTheCameraRuns() {
        let formats = [
            FormatDescriptor(index: 0, width: 1920, height: 1440, maxFPS: 60, maxPhotoPixels: 12_000_000),
            FormatDescriptor(index: 1, width: 1920, height: 1080, maxFPS: 240),
            FormatDescriptor(index: 2, width: 3840, height: 2160, maxFPS: 60),
        ]
        XCTAssertEqual(FormatChooser.frameRates(formats, width: 1920), [24, 30, 60, 120, 240])
        XCTAssertEqual(FormatChooser.frameRates(formats, width: 3840), [24, 30, 60])
        let pro = formats + [FormatDescriptor(index: 3, width: 3840, height: 2160, maxFPS: 120)]
        XCTAssertEqual(FormatChooser.frameRates(pro, width: 3840), [24, 30, 60, 120])
    }
}

final class DeviceOrientationTests: XCTestCase {
    func testGravityPicksTheOrientationWithAMargin() {
        XCTAssertEqual(DeviceOrientation.from(gravityX: 0, gravityY: -1, previous: .landscapeLeft), .portrait)
        XCTAssertEqual(DeviceOrientation.from(gravityX: -1, gravityY: 0, previous: .portrait), .landscapeLeft)
        XCTAssertEqual(DeviceOrientation.from(gravityX: 1, gravityY: 0, previous: .portrait), .landscapeRight)
        // Near the diagonal nothing changes, so the icons do not flicker.
        XCTAssertEqual(DeviceOrientation.from(gravityX: -0.72, gravityY: -0.69, previous: .portrait), .portrait)
        XCTAssertEqual(DeviceOrientation.from(gravityX: -0.72, gravityY: -0.69, previous: .landscapeLeft), .landscapeLeft)
        // Flat on a table keeps the last one.
        XCTAssertEqual(DeviceOrientation.from(gravityX: 0.05, gravityY: 0.02, previous: .landscapeRight), .landscapeRight)
    }

    func testRotationsMirrorEachOther() {
        XCTAssertEqual(DeviceOrientation.landscapeLeft.iconRotation, -DeviceOrientation.landscapeRight.iconRotation)
        XCTAssertEqual(DeviceOrientation.portrait.quarterTurns, 0)
        XCTAssertEqual(DeviceOrientation.landscapeLeft.quarterTurns, 1)
    }
}
