import XCTest
import CameraCore

final class AspectOptionTests: XCTestCase {
    func testPortraitSourceCropsTo4x3Portrait() {
        let crop = AspectOption.ratio4x3.cropRect(sourceWidth: 1080, sourceHeight: 1920)
        XCTAssertEqual(crop, CropRect(x: 0, y: 240, width: 1080, height: 1440))
    }

    func testPortraitSourceCropsToSquare() {
        let crop = AspectOption.ratio1x1.cropRect(sourceWidth: 3024, sourceHeight: 4032)
        XCTAssertEqual(crop, CropRect(x: 0, y: 504, width: 3024, height: 3024))
    }

    func testSourceAlreadyMatchingKeepsFullFrame() {
        let crop = AspectOption.ratio4x3.cropRect(sourceWidth: 3024, sourceHeight: 4032)
        XCTAssertEqual(crop, CropRect(x: 0, y: 0, width: 3024, height: 4032))
    }

    func testLandscapeSourceCrops16x9() {
        let crop = AspectOption.ratio16x9.cropRect(sourceWidth: 4032, sourceHeight: 3024)
        XCTAssertEqual(crop.width, 4032)
        XCTAssertEqual(crop.height, 2268)
        XCTAssertEqual(crop.y, 378)
    }

    func testCropDimensionsAreEven() {
        for option in AspectOption.allCases {
            let crop = option.cropRect(sourceWidth: 1081, sourceHeight: 1921)
            XCTAssertEqual(crop.width % 2, 0)
            XCTAssertEqual(crop.height % 2, 0)
        }
    }

    func testCyclingVisitsEveryOption() {
        var option = AspectOption.ratio4x3
        var seen: Set<AspectOption> = []
        for _ in 0 ..< AspectOption.allCases.count { seen.insert(option); option = option.next }
        XCTAssertEqual(seen.count, AspectOption.allCases.count)
        XCTAssertEqual(option, .ratio4x3)
    }
}

final class OptionTests: XCTestCase {
    func testFlashAndTimerCycle() {
        XCTAssertEqual(FlashMode.off.next, .auto)
        XCTAssertEqual(FlashMode.on.next, .off)
        XCTAssertEqual(TimerOption.off.next.seconds, 3)
        XCTAssertEqual(TimerOption.tenSeconds.next, .off)
    }

    func testEVSnapAndFormat() {
        XCTAssertEqual(EVScale.snapped(0.33), 0.3, accuracy: 1e-9)
        XCTAssertEqual(EVScale.snapped(9), 2.0)
        XCTAssertEqual(EVScale.snapped(-9), -2.0)
        XCTAssertEqual(EVScale.format(0), "0.0")
        XCTAssertEqual(EVScale.format(0.04), "0.0")
        XCTAssertEqual(EVScale.format(1.04), "+1.0")
        XCTAssertEqual(EVScale.format(-0.5), "-0.5")
    }
}

final class ZoomStopTests: XCTestCase {
    func testPhotoStopsWithTripleCamera() {
        let stops = ZoomStop.photoStops(focalLengths: [.ultraWide: 13, .wide: 24, .telephoto: 100])
        XCTAssertEqual(stops.map(\.label), ["0.5", "1", "1.5", "4"])
        XCTAssertEqual(stops.map(\.lens), [.ultraWide, .wide, .wide, .telephoto])
        XCTAssertEqual(stops[2].digitalZoom, 1.5)
    }

    func testPhotoStopsWithoutTelephotoFallBackToDigitalTwoX() {
        let stops = ZoomStop.photoStops(focalLengths: [.wide: 24])
        XCTAssertEqual(stops.map(\.label), ["1", "1.5", "2"])
        XCTAssertEqual(stops.last?.lens, .wide)
        XCTAssertEqual(stops.last?.digitalZoom, 2.0)
    }

    func testVideoStopsUseFocalLengths() {
        let stops = ZoomStop.videoStops(focalLengths: [.ultraWide: 13.4, .wide: 24, .telephoto: 99.6])
        XCTAssertEqual(stops.map(\.label), ["13", "24", "100"])
    }

    func testStopIDsAreUnique() {
        let stops = ZoomStop.photoStops(focalLengths: ZoomStop.defaultFocalLengths)
        XCTAssertEqual(Set(stops.map(\.id)).count, stops.count)
    }
}

final class CaptureStoreTests: XCTestCase {
    private func makeStore() throws -> (CaptureStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return (try CaptureStore(directory: url), url)
    }

    func testAddWritesFilesAndSurvivesReload() throws {
        let (store, url) = try makeStore()
        let record = CaptureRecord(kind: .photo, presetID: "preset-1", hasRAW: true, placeName: "Test")
        try store.write(Data([1, 2, 3]), as: .rawDNG, for: record.id)
        try store.add(record)

        XCTAssertTrue(store.fileExists(.rawDNG, for: record.id))
        let reloaded = try CaptureStore(directory: url)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.placeName, "Test")
    }

    func testRecordsAreNewestFirst() throws {
        let (store, _) = try makeStore()
        let old = CaptureRecord(date: Date(timeIntervalSinceNow: -100), kind: .photo, presetID: "preset-1")
        let new = CaptureRecord(date: Date(), kind: .video, presetID: "preset-2")
        try store.add(old)
        try store.add(new)
        XCTAssertEqual(store.records.map(\.id), [new.id, old.id])
    }

    func testRemoveDeletesFolder() throws {
        let (store, _) = try makeStore()
        let record = CaptureRecord(kind: .photo, presetID: "preset-1")
        try store.write(Data([1]), as: .processed, for: record.id)
        try store.add(record)
        try store.remove(id: record.id)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: record.id).path))
    }

    func testPurgeRemovesOnlyExpiredRAW() throws {
        let (store, _) = try makeStore()
        let expired = CaptureRecord(date: Date(timeIntervalSinceNow: -31 * 86_400), kind: .photo, presetID: "preset-1", hasRAW: true)
        let fresh = CaptureRecord(date: Date(timeIntervalSinceNow: -2 * 86_400), kind: .photo, presetID: "preset-1", hasRAW: true)
        for record in [expired, fresh] {
            try store.write(Data([1]), as: .rawDNG, for: record.id)
            try store.write(Data([2]), as: .processed, for: record.id)
            try store.add(record)
        }

        let purged = try store.purgeExpiredRAW()
        XCTAssertEqual(purged, [expired.id])
        XCTAssertFalse(store.fileExists(.rawDNG, for: expired.id))
        XCTAssertTrue(store.fileExists(.processed, for: expired.id), "processed image stays")
        XCTAssertTrue(store.fileExists(.rawDNG, for: fresh.id))
        XCTAssertEqual(store.record(id: expired.id)?.hasRAW, false)
    }

    func testDaysUntilRAWExpires() throws {
        let (store, _) = try makeStore()
        let now = Date()
        XCTAssertEqual(store.daysUntilRAWExpires(CaptureRecord(date: now, kind: .photo, presetID: "x"), now: now), 30)
        XCTAssertEqual(store.daysUntilRAWExpires(CaptureRecord(date: now.addingTimeInterval(-29.5 * 86_400), kind: .photo, presetID: "x"), now: now), 1)
    }
}

final class SettingsTests: XCTestCase {
    func testRoundTripAndDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(url: url)
        XCTAssertEqual(store.load(), AppSettings())

        var settings = AppSettings()
        settings.lastCaptureMode = .video
        settings.videoFPS = 60
        settings.aspect = .ratio16x9
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(settings.videoFormat, VideoFormat(width: 1920, height: 1080, fps: 60))
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(SettingsStore(url: url).load(), AppSettings())
    }
}
