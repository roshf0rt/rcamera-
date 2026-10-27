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
    func testPhotoStopsOnlyShowRealLensesByDefault() {
        let stops = ZoomStop.photoStops(focalLengths: [.ultraWide: 13, .wide: 24, .telephoto: 100])
        XCTAssertEqual(stops.map(\.label), ["0.5", "1", "4"])
        XCTAssertEqual(stops.map(\.lens), [.ultraWide, .wide, .telephoto])
    }

    func testOptionalCropStopSitsBetweenLenses() {
        let focals: [LensID: Double] = [.ultraWide: 13, .wide: 24, .telephoto: 100]
        let onePointFive = ZoomStop.photoStops(focalLengths: focals, digital: .x1_5)
        XCTAssertEqual(onePointFive.map(\.label), ["0.5", "1", "1.5", "4"])
        XCTAssertEqual(onePointFive[2].lens, .wide)
        XCTAssertEqual(onePointFive[2].digitalZoom, 1.5)

        let two = ZoomStop.photoStops(focalLengths: focals, digital: .x2)
        XCTAssertEqual(two.map(\.label), ["0.5", "1", "2", "4"])
    }

    func testPhoneWithOnlyAWideLensGetsOnlyOneStop() {
        XCTAssertEqual(ZoomStop.photoStops(focalLengths: [.wide: 24]).map(\.label), ["1"])
        XCTAssertEqual(ZoomStop.photoStops(focalLengths: [.wide: 24], digital: .x2).map(\.label), ["1", "2"])
    }

    func testCropStopIsSkippedWhenARealLensCoversIt() {
        // A 48 mm telephoto is already a 2x lens.
        let stops = ZoomStop.photoStops(focalLengths: [.wide: 24, .telephoto: 48], digital: .x2)
        XCTAssertEqual(stops.map(\.label), ["1", "2"])
        XCTAssertEqual(stops.last?.lens, .telephoto)
    }

    func testDetectedFocalLengthsSnapToStandardValues() {
        let video = ZoomStop.videoStops(focalLengths: [.ultraWide: 14.2, .wide: 24.9, .telephoto: 104])
        XCTAssertEqual(video.map(\.label), ["13", "24", "100"])
        let photo = ZoomStop.photoStops(focalLengths: [.ultraWide: 14.2, .wide: 24.9, .telephoto: 104])
        XCTAssertEqual(photo.map(\.label), ["0.5", "1", "4"])
    }

    func testVideoStopsUseFocalLengths() {
        let stops = ZoomStop.videoStops(focalLengths: [.ultraWide: 13.4, .wide: 24, .telephoto: 99.6])
        XCTAssertEqual(stops.map(\.label), ["13", "24", "100"])
    }

    func testStopIDsAreUnique() {
        let stops = ZoomStop.photoStops(focalLengths: ZoomStop.defaultFocalLengths, digital: .x1_5)
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

final class VideoGapFillerTests: XCTestCase {
    func testSmallGapIsLeftAlone() {
        // 30 fps at timescale 600: one frame is 20 ticks, four frames is 80.
        XCTAssertEqual(VideoGapFiller.fillTimes(last: 0, current: 20, timescale: 600, fps: 30), [])
        XCTAssertEqual(VideoGapFiller.fillTimes(last: 0, current: 80, timescale: 600, fps: 30), [])
    }

    func testGapJustOverThresholdRepeatsFrames() {
        let times = VideoGapFiller.fillTimes(last: 0, current: 100, timescale: 600, fps: 30)
        XCTAssertEqual(times, [20, 40, 60, 80])
    }

    func testRepeatedFramesStayBeforeTheRealOne() {
        let times = VideoGapFiller.fillTimes(last: 1000, current: 1200, timescale: 600, fps: 30)
        XCTAssertTrue(times.allSatisfy { $0 > 1000 && $0 < 1200 })
        XCTAssertEqual(times, Array(stride(from: 1020, through: 1180, by: 20)))
    }

    func testVeryLongGapIsCapped() {
        let times = VideoGapFiller.fillTimes(last: 0, current: 600 * 60, timescale: 600, fps: 30)
        XCTAssertEqual(times.count, VideoGapFiller.maxInsertedFrames)
    }

    func testInvalidInputsGiveNoFrames() {
        XCTAssertEqual(VideoGapFiller.fillTimes(last: 0, current: 1000, timescale: 600, fps: 0), [])
        XCTAssertEqual(VideoGapFiller.fillTimes(last: 0, current: 1000, timescale: 0, fps: 30), [])
        XCTAssertEqual(VideoGapFiller.fillTimes(last: 0, current: 1000, timescale: 10, fps: 30), [])
    }
}

final class SettingsMigrationTests: XCTestCase {
    func testOldSettingsFileKeepsValuesAndGainsDefaults() throws {
        // Written by the first release: boolean stabilization, no crop stop, no Apple Log.
        let json = """
        {"selectedPresetID":"preset-4","lastCaptureMode":"video","aspect":"16:9","flash":"off","timer":"off",
         "isGridEnabled":false,"isLevelEnabled":false,"mirrorFrontCamera":true,"capturesRAW":true,"savesLocation":true,
         "videoResolution":"uhd4K","videoFPS":60,"videoStabilization":false}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.selectedPresetID, "preset-4")
        XCTAssertEqual(settings.lastCaptureMode, .video)
        XCTAssertEqual(settings.videoFPS, 60)
        XCTAssertFalse(settings.isGridEnabled)
        XCTAssertEqual(settings.videoStabilization, .off)
        XCTAssertEqual(settings.digitalZoomStop, .none)
        XCTAssertTrue(settings.appleLogVideo, "Apple Log became the default in revision 2")
    }

    func testRevisionTwoKeepsAnExplicitAppleLogChoice() throws {
        let json = #"{"appleLogVideo":false,"revision":2}"#
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).appleLogVideo)
    }

    func testCaptureIndexFromEarlierReleaseStillLoads() throws {
        let json = """
        [{"id":"8F1A5C0E-2B7D-4C41-9E64-3D2F6B1A7C90","date":"2026-10-27T05:00:00Z","kind":"photo",
          "presetID":"preset-1","evPushPull":0,"aspect":"4:3","hasRAW":true,"isFavorite":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([CaptureRecord].self, from: Data(json.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].rawExposureOffset, 0)
        XCTAssertNil(records[0].placeName)
    }

    func testLegacyTrueStabilizationBecomesStandard() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"videoStabilization":true}"#.utf8))
        XCTAssertEqual(settings.videoStabilization, .standard)
    }

    func testNewSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.videoStabilization = .cinematic
        settings.digitalZoomStop = .x2
        settings.appleLogVideo = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testStabilizationCycles() {
        XCTAssertEqual(VideoStabilization.off.next, .standard)
        XCTAssertEqual(VideoStabilization.cinematic.next, .off)
    }
}
