@testable import CameraCore
import XCTest

/// Portrait mode is gone; what it left in stored files must not break loading them.
final class RemovedPortraitTests: XCTestCase {
    func testRecordsOfPortraitPhotosStillLoad() throws {
        let json = #"{"id":"8D2C1E3A-7A64-4C4E-9E7E-3C1B2A0F5D11","date":0,"kind":"photo","presetID":"preset-1","portraitFNumber":2.8,"lensStyle":"lumar","grainLevel":"low"}"#
        let record = try JSONDecoder().decode(CaptureRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.kind, .photo)
        XCTAssertEqual(record.grainLevel, .low)
        // Saved again, the keys of the removed mode are dropped.
        let saved = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(saved.contains("lensStyle"))
        XCTAssertFalse(saved.contains("portraitFNumber"))
    }

    func testSettingsFromAPortraitBuildStillLoad() throws {
        let json = #"{"aspect":"ratio4x3","portrait":true,"portraitFNumber":1.4,"lensStyle":"petzval","zebra":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.zebra)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("portrait"))
    }
}
