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
