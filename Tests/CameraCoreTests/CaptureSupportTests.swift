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

    func testPinchReadsTheLiveValueBetweenStopsAndSnapsOnThem() {
        let focals: [LensID: Double] = [.ultraWide: 13, .wide: 24, .telephoto: 100]
        let stops = ZoomStop.photoStops(focalLengths: focals, digital: .x1_5)
        let wide = stops.first { $0.lens == .wide && $0.digitalZoom == 1 }!

        XCTAssertEqual(ZoomStop.reading(zoom: 1, stops: stops, focalLengths: focals).stop, wide)
        XCTAssertNil(ZoomStop.reading(zoom: 1, stops: stops, focalLengths: focals).live, "on the stop: no live value")

        let between = ZoomStop.reading(zoom: 1.2, stops: stops, focalLengths: focals)
        XCTAssertEqual(between.stop, wide, "between 1 and 1.5 the wide chip shows the value")
        XCTAssertEqual(between.live ?? 0, 1.2, accuracy: 1e-9)

        let snapped = ZoomStop.reading(zoom: 1.5, stops: stops, focalLengths: focals)
        XCTAssertEqual(snapped.stop?.digitalZoom, 1.5, "at 1.5 the crop stop takes over")
        XCTAssertNil(snapped.live)

        let past = ZoomStop.reading(zoom: 2.3, stops: stops, focalLengths: focals)
        XCTAssertEqual(past.stop?.digitalZoom, 1.5, "past 1.5 and short of the telephoto, the crop chip shows 2.3")
        XCTAssertEqual(past.live ?? 0, 2.3, accuracy: 1e-9)
    }

    func testTheTelephotoStopIsItsFocalOverTheWide() throws {
        let focals: [LensID: Double] = [.ultraWide: 13, .wide: 24, .telephoto: 100]
        let telephoto = try XCTUnwrap(ZoomStop.photoStops(focalLengths: focals).first { $0.lens == .telephoto })
        XCTAssertEqual(telephoto.factor(focalLengths: focals), 100.0 / 24, accuracy: 0.01)
        XCTAssertEqual(ZoomStop.reading(zoom: 4.1, stops: [telephoto], focalLengths: focals).live ?? 0, 4.1, accuracy: 1e-9)
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

    func testRAWFilesAreListedWithSizesAndCanBeCleared() throws {
        let (store, _) = try makeStore()
        let first = CaptureRecord(date: Date(timeIntervalSinceNow: -10), kind: .photo, presetID: "preset-1", hasRAW: true)
        let second = CaptureRecord(date: Date(), kind: .photo, presetID: "preset-1", hasRAW: true)
        let plain = CaptureRecord(kind: .photo, presetID: "preset-1")
        try store.write(Data(count: 1_000), as: .rawDNG, for: first.id)
        try store.write(Data(count: 3_000), as: .rawDNG, for: second.id)
        for record in [first, second, plain] {
            try store.write(Data([2]), as: .processed, for: record.id)
            try store.add(record)
        }

        XCTAssertEqual(store.rawFiles().map(\.id), [second.id, first.id], "newest first, only captures with RAW")
        XCTAssertEqual(store.rawFiles().map(\.bytes), [3_000, 1_000])

        XCTAssertEqual(try store.removeRAW(ids: [first.id]), 1_000)
        XCTAssertFalse(store.fileExists(.rawDNG, for: first.id))
        XCTAssertEqual(store.record(id: first.id)?.hasRAW, false)
        XCTAssertTrue(store.fileExists(.processed, for: first.id), "the photo stays")
        XCTAssertTrue(store.fileExists(.rawDNG, for: second.id))

        XCTAssertEqual(try store.removeRAW(), 3_000)
        XCTAssertTrue(store.rawFiles().isEmpty)
    }

    func testLogVideoFlagSurvivesAReloadAndOldRecordsAreNotLog() throws {
        let record = CaptureRecord(kind: .video, presetID: "preset-1", logVideo: true)
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        XCTAssertTrue(decoded.logVideo)
        let old = try JSONDecoder().decode(CaptureRecord.self, from: Data(#"{"id":"\#(UUID().uuidString)","date":0,"kind":"video","presetID":"preset-1","evPushPull":0,"aspect":"16:9","hasRAW":false,"isFavorite":false,"rawExposureOffset":0,"mirrored":false,"frame":"off","grainLevel":"medium","halationLevel":"medium","orientation":"portrait"}"#.utf8))
        XCTAssertFalse(old.logVideo)
    }

    func testShadowsLiftedInRedevelopSurviveAReload() throws {
        let (store, url) = try makeStore()
        try store.add(CaptureRecord(kind: .photo, presetID: "preset-1", shadowLift: 0.4))
        XCTAssertEqual(try CaptureStore(directory: url).records.first?.shadowLift, 0.4)
        XCTAssertEqual(ShadowLift.dynamicRange(for: 0), 1)
        XCTAssertEqual(ShadowLift.dynamicRange(for: 1), 1.5)
        XCTAssertEqual(ShadowLift.dynamicRange(for: 7), 1.5, "clamped")
        XCTAssertEqual(ShadowLift.dynamicRange(for: -1), 0.25, accuracy: 1e-9, "shadows down bends towards an S-curve")
        XCTAssertEqual(ShadowLift.dynamicRange(for: -7), 0.25, accuracy: 1e-9, "clamped")
        XCTAssertLessThan(DynamicRangeCurve(ShadowLift.dynamicRange(for: -1)).apply(0.2), 0.2, "down darkens the shadows")
        XCTAssertGreaterThan(DynamicRangeCurve(ShadowLift.dynamicRange(for: 1)).apply(0.2), 0.2, "up lifts them")
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
    func testGrainLevelStepsAndOldSwitchStillLoads() throws {
        XCTAssertEqual(GrainLevel.off.next, .low)
        XCTAssertEqual(GrainLevel.high.next, .off)
        XCTAssertEqual(GrainLevel.medium.multiplier, 1)
        var settings = AppSettings()
        XCTAssertEqual(settings.grainLevel, .medium)
        settings.grainEnabled = false
        XCTAssertEqual(settings.grainLevel, .off)
        settings.grainEnabled = true
        XCTAssertEqual(settings.grainLevel, .medium)

        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"grainEnabled":false}"#.utf8))
        XCTAssertEqual(old.grainLevel, .off)
        var high = AppSettings()
        high.grainLevel = .high
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(high))
        XCTAssertEqual(roundTrip.grainLevel, .high)
    }

    func testHalationLevelAndOldSwitchStillLoads() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"halationEnabled":false}"#.utf8))
        XCTAssertEqual(old.halationLevel, .off)
        XCTAssertFalse(old.halationEnabled)
        var low = AppSettings()
        low.halationLevel = .low
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(low))
        XCTAssertEqual(roundTrip.halationLevel, .low)
        XCTAssertEqual(AppSettings().halationLevel, .medium)
        XCTAssertGreaterThan(FilmMath.halationStrength(1.7), FilmMath.halationStrength(1))
    }

    func testStoredFortyEightMegapixelsFallsBackToTwelve() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"photoResolution":"mp48"}"#.utf8))
        XCTAssertEqual(settings.photoResolution, .mp12)
    }

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
