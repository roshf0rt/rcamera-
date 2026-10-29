@testable import CameraCore
import XCTest

final class DepthMapTests: XCTestCase {
    func testEncodingRoundTrips() throws {
        let map = DepthMap(width: 3, height: 2, values: [0.5, 1, 2, 3, 4.25, -1])
        let decoded = try XCTUnwrap(DepthMap(encoded: map.encoded()))
        XCTAssertEqual(decoded, map)
    }

    func testGarbageIsRejected() {
        XCTAssertNil(DepthMap(encoded: Data("nope".utf8)))
        var truncated = DepthMap(width: 2, height: 2, values: [1, 2, 3, 4]).encoded()
        truncated.removeLast()
        XCTAssertNil(DepthMap(encoded: truncated))
    }

    func testPortraitTurnsTheMapClockwise() {
        // Landscape 8 × 6: value = row × 8 + column. Turned clockwise it is a 6 × 8 portrait picture, and a 4:3
        // crop of it is the whole picture, so each portrait pixel is one map pixel.
        let map = DepthMap(width: 8, height: 6, values: (0 ..< 48).map { Float($0) })
        let portrait = map.portrait(aspect: .ratio4x3, outWidth: 6, outHeight: 8)
        XCTAssertEqual(portrait.count, 48)
        XCTAssertEqual(portrait[0], 40, "top-left of the photo is bottom-left of the map")
        XCTAssertEqual(portrait[5], 0, "top-right of the photo is top-left of the map")
        XCTAssertEqual(portrait[7 * 6], 47, "bottom-left of the photo is bottom-right of the map")
    }

    func testMiddleDisparityReadsTheCentre() throws {
        let map = DepthMap(width: 10, height: 10, values: Array(repeating: 2, count: 100))
        XCTAssertEqual(try XCTUnwrap(map.middleDisparity), 2, accuracy: 1e-6)
        XCTAssertNil(DepthMap(width: 1, height: 1, values: [Float.nan]).middleDisparity)
    }
}

final class PortraitRecordTests: XCTestCase {
    func testPortraitSettingsSurviveARoundTrip() throws {
        let record = CaptureRecord(kind: .photo, presetID: "preset-1", portraitFNumber: 2.8, lensStyle: .lumar)
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.portraitFNumber, 2.8)
        XCTAssertEqual(decoded.lensStyle, .lumar)
    }

    func testOlderRecordsAreNotPortrait() throws {
        let record = CaptureRecord(kind: .photo, presetID: "preset-1")
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.lensStyle)
        XCTAssertNil(decoded.portraitFNumber)
    }
}

final class LensPreviewTests: XCTestCase {
    func testEveryLensDrawsItsOwnPreview() {
        let previews = LensStyle.allCases.map { LensPreviewScene.render(lens: $0, size: 64) }
        XCTAssertTrue(previews.allSatisfy { $0.count == 64 * 64 * 4 })
        XCTAssertEqual(Set(previews).count, LensStyle.allCases.count, "each lens has its own shapes")
    }

    func testThePreviewIsANightSceneWithLights() {
        let pixels = LensPreviewScene.render(lens: .solis, size: 96)
        let brightest = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) }.max() ?? 0
        XCTAssertGreaterThan(brightest, 200, "lights glow")
        let dark = stride(from: 0, to: pixels.count, by: 4).filter { Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) < 60 }.count
        XCTAssertGreaterThan(dark, pixels.count / 4 / 5, "between the lights the night stays dark")
    }
}
