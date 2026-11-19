@testable import CameraCore
import XCTest

final class AppleLog2Tests: XCTestCase {
    func testGreysStayGrey() {
        for value: Float in [0, 0.1, 0.25, 0.41, 0.6, 0.9] {
            let out = AppleLog.log2ToLog1(r: value, g: value, b: value)
            XCTAssertEqual(out.0, value, accuracy: 0.002)
            XCTAssertEqual(out.1, value, accuracy: 0.002)
            XCTAssertEqual(out.2, value, accuracy: 0.002)
        }
    }

    func testApplePrimariesAreWiderThanRec2020() {
        // The same code values mean a more saturated colour in Apple Wide Gamut, so in Apple Log they move apart.
        let log2 = (r: Float(0.6), g: Float(0.45), b: Float(0.4))
        let log1 = AppleLog.log2ToLog1(r: log2.r, g: log2.g, b: log2.b)
        XCTAssertGreaterThan(log1.0 - log1.2, log2.r - log2.b)
    }

    func testMatrixKeepsWhite() {
        for row in AppleLog.appleWideGamutTo2020 {
            XCTAssertEqual(row.reduce(0, +), 1, accuracy: 1e-5)
        }
    }

    func testForLog2BakesTheConversionInFront() throws {
        let identity = try LUT3D.identity(size: 33)
        let baked = AppleLog.forLog2(identity)
        XCTAssertEqual(baked.size, 33)
        let probe = baked.apply(r: 0.6, g: 0.45, b: 0.4)
        let direct = AppleLog.log2ToLog1(r: 0.6, g: 0.45, b: 0.4)
        XCTAssertEqual(probe.r, direct.0, accuracy: 0.01)
        XCTAssertEqual(probe.g, direct.1, accuracy: 0.01)
        XCTAssertEqual(probe.b, direct.2, accuracy: 0.01)
    }

    func testOldFilesLoadAsAppleLog1() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.appleLog2)
        var on = AppSettings()
        on.appleLog2 = true
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).appleLog2)

        let record = CaptureRecord(kind: .video, presetID: "preset-1", logVideo: true, logVersion2: true)
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        XCTAssertTrue(decoded.logVersion2)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json["logVersion2"] = nil
        let old = try JSONDecoder().decode(CaptureRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(old.logVersion2)
    }
}
