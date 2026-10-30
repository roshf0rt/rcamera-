import AVFoundation
import CameraCore
import Foundation
import Observation
import SwiftUI
import UIKit

/// App-wide state: settings, presets, captures, and the plumbing that turns camera output into saved files.
@MainActor
@Observable
final class AppModel {
    let engine: CameraEngine
    @ObservationIgnored let volumeShutter = VolumeShutter()
    let location = LocationProvider()
    let level = LevelMonitor()
    let orientation = OrientationMonitor()

    private(set) var settings: AppSettings
    private(set) var presets: [Preset]
    private(set) var captures: [CaptureRecord]
    private(set) var processingCount = 0
    /// Log videos being graded, 0 to 1, by record id.
    var videoProgress: [UUID: Double] = [:]
    var alert: String?

    @ObservationIgnored private let presetLibrary: PresetLibrary
    @ObservationIgnored private let captureStore: CaptureStore
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private var lookCache: [String: FilmLook] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RCamera", isDirectory: true)
        do {
            presetLibrary = try PresetLibrary(
                storageDirectory: base.appendingPathComponent("Presets", isDirectory: true),
                bundledLUTDirectory: Bundle.main.url(forResource: "LUTs", withExtension: nil)
            )
            captureStore = try CaptureStore(directory: base.appendingPathComponent("Captures", isDirectory: true))
        } catch {
            fatalError("Could not create app storage: \(error)")
        }
        settingsStore = SettingsStore(url: base.appendingPathComponent("settings.json"))

        let loaded = settingsStore.load()
        settings = loaded
        presets = presetLibrary.presets
        captures = captureStore.records
        engine = CameraEngine(settings: loaded)

        _ = try? captureStore.purgeExpiredRAW()
        captures = captureStore.records

        engine.onPhoto = { [weak self] result in self?.ingest(photo: result) }
        engine.onVideo = { [weak self] url, keepsLog in self?.ingest(videoAt: url, keepsLog: keepsLog) }
        engine.onModeChanged = { [weak self] mode in self?.updateSettings { $0.lastCaptureMode = mode } }
        engine.onFormatFallback = { [weak self] format in
            self?.updateSettings {
                $0.videoFPS = format.fps
                $0.videoResolution = format.width >= 3840 ? .uhd4K : .hd1080
            }
        }
        volumeShutter.onPress = { [weak self] in self?.engine.shutterTapped() }
        NotificationCenter.default.addObserver(forName: .takePhotoRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.engine.shutterTapped() }
        }
        pushLooks()
        syncCameraControls()
    }

    /// The Camera Control button's lists: presets, grain and halation, plus aperture and lens in portrait mode.
    func syncCameraControls() {
        let presets = visiblePresets
        let selected = presets.firstIndex { $0.id == settings.selectedPresetID } ?? 0
        let levels = GrainLevel.allCases
        let stops = PortraitAperture.stops
        let lenses = LensStyle.allCases.sorted { $0.order < $1.order }
        var pickers: [CaptureSessionController.ControlPicker] = [
            .init(title: "Preset", symbol: "camera.filters", titles: presets.map(\.name), selected: selected) { [weak self] index in
                Task { @MainActor in
                    guard let self, self.visiblePresets.indices.contains(index) else { return }
                    self.selectPreset(self.visiblePresets[index].id)
                }
            },
            .init(title: "Grain", symbol: "circle.grid.3x3", titles: levels.map(\.label), selected: levels.firstIndex(of: settings.grainLevel) ?? 0) { [weak self] index in
                Task { @MainActor in self?.updateSettings { $0.grainLevel = levels[index] } }
            },
            .init(title: "Halation", symbol: "sun.max", titles: levels.map(\.label), selected: levels.firstIndex(of: settings.halationLevel) ?? 0) { [weak self] index in
                Task { @MainActor in self?.updateSettings { $0.halationLevel = levels[index] } }
            },
        ]
        if settings.portrait {
            let stopTitles = stops.map { "ƒ" + ApertureTitle.format($0) }
            pickers.append(.init(title: "Aperture", symbol: "camera.aperture", titles: stopTitles,
                                 selected: stops.firstIndex(of: settings.portraitFNumber) ?? 0) { [weak self] index in
                Task { @MainActor in self?.updateSettings { $0.portraitFNumber = stops[index] } }
            })
            pickers.append(.init(title: "Lens", symbol: "circle.hexagongrid", titles: lenses.map(\.label),
                                 selected: lenses.firstIndex(of: settings.lensStyle) ?? 0) { [weak self] index in
                Task { @MainActor in self?.updateSettings { $0.lensStyle = lenses[index] } }
            })
        }
        engine.controller.setControlPickers(pickers)
    }

    /// Creates a custom preset, from scratch (`base` nil) or from another preset's look and LUTs, with
    /// its own card colours and optional cover photo. Selects it and returns its id.
    @discardableResult
    func createPreset(name: String, base: Preset?, accentIndex: Int, cover: Data?) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let added = try presetLibrary.addCustom(copying: base, name: trimmed.isEmpty ? "New Preset" : trimmed, accentIndex: accentIndex)
            if let cover { setCover(cover, for: added.id) }
            presets = presetLibrary.presets
            syncCameraControls()
            selectPreset(added.id)
            return added.id
        } catch {
            alert = error.localizedDescription
            return nil
        }
    }

    /// Puts a built-in preset back to how it ships.
    func resetPreset(id: String) {
        do {
            try presetLibrary.resetBuiltIn(id: id)
            presets = presetLibrary.presets
            syncCameraControls()
            invalidateLooks(for: id)
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Card pictures of custom presets, loaded on demand.
    private(set) var covers: [String: UIImage] = [:]

    func cover(for presetID: String) -> UIImage? {
        if let cached = covers[presetID] { return cached }
        guard let url = presetLibrary.coverURL(for: presetID), let image = UIImage(contentsOfFile: url.path) else { return nil }
        // Loaded lazily from a view's body, so the cache is filled outside the update.
        Task { @MainActor in self.covers[presetID] = image }
        return image
    }

    /// Stores a photo (or with nil removes it) as a preset's card picture, downsized to 600 px.
    func setCover(_ data: Data?, for presetID: String) {
        let jpeg = data.flatMap { UIImage(data: $0) }.flatMap { Self.coverJPEG($0) }
        do {
            try presetLibrary.setCover(jpeg, for: presetID)
            covers[presetID] = jpeg.flatMap { UIImage(data: $0) }
        } catch {
            alert = error.localizedDescription
        }
    }

    private static func coverJPEG(_ image: UIImage) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        let factor = min(1, 600 / max(longSide, 1))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.85)
    }

    /// Deletes a custom preset. Built-in presets are never removed.
    /// Reorders the presets, as the camera's picker and Camera Control list them.
    func movePresets(from source: IndexSet, to destination: Int) {
        var ids = presets.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do {
            try presetLibrary.reorder(ids)
            presets = presetLibrary.presets
            syncCameraControls()
        } catch {
            alert = error.localizedDescription
        }
    }

    func deletePreset(id: String) {
        do {
            try presetLibrary.removeCustom(id: id)
            presets = presetLibrary.presets
            syncCameraControls()
            lookCache = lookCache.filter { !$0.key.hasPrefix("\(id)|") }
            covers[id] = nil
            if settings.selectedPresetID == id, let first = visiblePresets.first { selectPreset(first.id) }
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Writes a preset's JSON to a file the share sheet can send. Nil when it cannot be written.
    func exportPreset(id: String) -> URL? {
        guard let preset = preset(id: id), let data = try? presetLibrary.exportData(for: id) else { return nil }
        let safeName = preset.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).rcpreset.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Starts or stops the volume-button shutter. Called when the setting changes and when the camera
    /// comes to the foreground or goes to the background.
    func syncVolumeShutter(active: Bool) {
        if active && settings.volumeShutter {
            volumeShutter.start()
        } else {
            volumeShutter.stop()
        }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        let togglesChanged = updated.grainLevel != settings.grainLevel
            || updated.halationLevel != settings.halationLevel
        settings = updated
        try? settingsStore.save(updated)
        engine.update(settings: updated)
        syncCameraControls()
        if togglesChanged { pushLooks() }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    // MARK: Presets

    var selectedPreset: Preset {
        presets.first { $0.id == settings.selectedPresetID && !$0.isHidden } ?? visiblePresets.first ?? presets[0]
    }

    /// The presets the camera offers, in order; hidden ones are only listed in Settings.
    var visiblePresets: [Preset] {
        presets.filter { !$0.isHidden }
    }

    /// Shows or hides a preset on the camera. Hiding the selected one moves the camera to the first visible one.
    func setPresetHidden(_ hidden: Bool, id: String) {
        do {
            try presetLibrary.setHidden(hidden, id: id)
            presets = presetLibrary.presets
            syncCameraControls()
            if hidden, settings.selectedPresetID == id, let first = visiblePresets.first { selectPreset(first.id) }
        } catch {
            alert = error.localizedDescription
        }
    }

    func selectPreset(_ id: String) {
        updateSettings { $0.selectedPresetID = id }
        pushLooks()
    }

    func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    func hasLUT(_ presetID: String, slot: LUTSlot) -> Bool {
        presetLibrary.hasLUT(for: presetID, slot: slot)
    }

    func hasAnyLUT(_ presetID: String) -> Bool {
        presetLibrary.hasAnyLUT(for: presetID)
    }

    func updatePreset(_ preset: Preset) {
        do {
            try presetLibrary.update(preset)
            presets = presetLibrary.presets
            syncCameraControls()
            lookCache = lookCache.filter { !$0.key.hasPrefix("\(preset.id)|") }
            if preset.id == settings.selectedPresetID { pushLooks() }
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Reads and validates the file off the main thread, then stores it. Returns an error message, or nil on success.
    func importLUT(from url: URL, presetID: String, slot: LUTSlot) async -> String? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try LUTImport.prepare(url: url) }.value
            try presetLibrary.commit(prepared, for: presetID, slot: slot)
            invalidateLooks(for: presetID)
            return nil
        } catch let error as LUTError {
            return Self.describe(error)
        } catch {
            return error.localizedDescription
        }
    }

    func removeLUT(presetID: String, slot: LUTSlot) {
        try? presetLibrary.removeLUT(for: presetID, slot: slot)
        invalidateLooks(for: presetID)
    }

    private func invalidateLooks(for presetID: String) {
        lookCache = lookCache.filter { !$0.key.hasPrefix("\(presetID)|") }
        if presetID == settings.selectedPresetID { pushLooks() }
    }

    nonisolated static func parseLUT(_ url: URL?) -> LUT3D? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? LUT3D.parse(data: data, fileExtension: url.pathExtension.lowercased())
    }

    /// The preset's look for one kind of input, without the camera-screen toggles. LUTs are parsed off the
    /// main thread, so neither the camera nor Redevelop stutters when switching presets.
    ///
    /// A missing photo LUT falls back to the video one and back. A missing Apple Log LUT becomes the neutral
    /// Apple Log → Rec.709 conversion followed by the video LUT, so the camera can stay in Apple Log for
    /// every preset (as Lampa does with its `neutral_appleLog`).
    func baseLook(for preset: Preset, slot: LUTSlot = .photo) async -> FilmLook {
        let key = "\(preset.id)|\(slot.rawValue)"
        if let cached = lookCache[key] { return cached }
        let photoURL = presetLibrary.lutURL(for: preset.id, slot: .photo)
        let videoURL = presetLibrary.lutURL(for: preset.id, slot: .video)
        let logURL = presetLibrary.lutURL(for: preset.id, slot: .appleLog)
        let lut: LUT3D? = await Task.detached(priority: .userInitiated) {
            switch slot {
            case .photo:
                return Self.parseLUT(photoURL ?? videoURL)
            case .video:
                return Self.parseLUT(videoURL ?? photoURL)
            case .appleLog:
                if let log = Self.parseLUT(logURL) { return log }
                let neutral = Self.neutralAppleLog
                return Self.parseLUT(videoURL ?? photoURL).map { neutral.followed(by: $0) } ?? neutral
            }
        }.value
        if let cached = lookCache[key] { return cached }
        var adjustments = preset.adjustments
        // The camera has no dynamic-range control: shadows are lifted afterwards, in Redevelop.
        adjustments.dynamicRange = 1
        // LUT strength is a photo setting; video and Apple Log always take the whole LUT.
        if slot != .photo { adjustments.filmStrength = 1 }
        let look = FilmLook(lut: lut, grain: preset.grain, halation: preset.halation, adjustments: adjustments)
        lookCache[key] = look
        return look
    }

    nonisolated static let neutralAppleLog = AppleLog.neutralRec709LUT()

    /// Loads every preset's photo look in the background, so the first switch to each is instant too.
    func prepareLooks() async {
        for preset in presets {
            _ = await baseLook(for: preset)
        }
    }

    /// The preset's look with grain and halation at the given levels, as on the camera screen.
    func leveledLook(for preset: Preset, grain: GrainLevel, halation: EffectLevel, shadowLift: Double = 0) async -> FilmLook {
        let base = await baseLook(for: preset)
        let look = base.with(
            grain: min(1, base.grain * grain.multiplier),
            halation: base.halation * halation.multiplier,
            adjustments: base.adjustments
        )
        guard shadowLift != 0 else { return look }
        return look.with { $0.dynamicRange = ShadowLift.dynamicRange(for: shadowLift) }
    }

    /// The preset's look with the camera-screen grain and halation toggles applied.
    func cameraLook(for preset: Preset, slot: LUTSlot = .photo) async -> FilmLook {
        let base = await baseLook(for: preset, slot: slot)
        return base.with(
            grain: min(1, base.grain * settings.grainLevel.multiplier),
            halation: base.halation * settings.halationLevel.multiplier,
            adjustments: base.adjustments
        )
    }

    /// Resolves the selected preset in the background, then hands it to the camera. The old look stays on
    /// screen until then, and the camera crossfades to the new one.
    private func pushLooks() {
        let preset = selectedPreset
        Task {
            let photo = await cameraLook(for: preset, slot: .photo)
            let video = await cameraLook(for: preset, slot: .video)
            let appleLog = await cameraLook(for: preset, slot: .appleLog)
            guard preset.id == selectedPreset.id else { return }
            engine.setLooks(CameraEngine.Looks(photo: photo, video: video, appleLog: appleLog))
        }
    }

    private static func describe(_ error: LUTError) -> String {
        switch error {
        case .unsupportedFormat(let ext): "Unsupported file type “\(ext)”. Use .cube or .lut."
        case .unsupported1DLUT: "1D LUTs are not supported. Use a 3D LUT."
        case .unsupportedDomain: "LUTs with a custom input domain are not supported."
        case .invalidSize(let size): "Unsupported LUT size \(size). Use a size between 2 and 128."
        case .invalidData(let detail): "The LUT file is damaged: \(detail)."
        }
    }

    // MARK: Captures

    func url(_ file: CaptureFile, for record: CaptureRecord) -> URL {
        captureStore.url(file, for: record.id)
    }

    /// What Share sends: the photo, or the video as it is shown.
    func shareURL(for record: CaptureRecord) -> URL {
        record.kind == .video ? videoURL(for: record) : url(.processed, for: record)
    }

    func fileExists(_ file: CaptureFile, for record: CaptureRecord) -> Bool {
        captureStore.fileExists(file, for: record.id)
    }

    func rawFiles() -> [CaptureStore.RAWFile] { captureStore.rawFiles() }

    /// Deletes RAW files (all when `ids` is nil); photos stay and redevelop from the camera image.
    @discardableResult
    func removeRAW(ids: Set<UUID>? = nil) -> Int64 {
        let freed = (try? captureStore.removeRAW(ids: ids)) ?? 0
        captures = captureStore.records
        return freed
    }

    func daysUntilRAWExpires(_ record: CaptureRecord) -> Int {
        captureStore.daysUntilRAWExpires(record)
    }

    func toggleFavorite(_ record: CaptureRecord) {
        var updated = record
        updated.isFavorite.toggle()
        try? captureStore.update(updated)
        captures = captureStore.records
    }

    func delete(_ record: CaptureRecord) {
        try? captureStore.remove(id: record.id)
        captures = captureStore.records
    }

    private func ingest(photo: CameraEngine.PhotoResult) {
        processingCount += 1
        let preset = selectedPreset
        let saveLocation = settings.savesLocation
        let keepRAW = settings.capturesRAW
        let grainLevel = settings.grainLevel
        let halationLevel = settings.halationLevel
        let frame = settings.frame
        let portraitFNumber = settings.portraitFNumber
        let lens = settings.lensStyle

        Task {
            var look = await cameraLook(for: preset, slot: .photo)
            if photo.depth != nil { look = look.with { lens.apply(to: &$0) } }
            let place = saveLocation ? await location.currentPlaceName() : nil
            let (developed, depthFile) = await Task.detached(priority: .userInitiated) { () -> (PhotoPipeline.Developed?, Data?) in
                let developed = PhotoPipeline.develop(
                    raw: photo.raw,
                    processed: photo.processed,
                    look: look,
                    aspect: photo.aspect,
                    mirror: photo.mirror,
                    frame: frame,
                    label: preset.name,
                    accentIndex: preset.accentIndex,
                    depth: photo.depth,
                    fNumber: portraitFNumber,
                    lens: lens,
                    orientation: photo.orientation
                )
                return (developed, photo.depth.flatMap { PhotoPipeline.depthMap($0)?.encoded() })
            }.value
            processingCount -= 1
            guard let developed else {
                alert = "The photo could not be processed."
                return
            }

            let hasRAW = keepRAW && photo.raw != nil
            let record = CaptureRecord(
                date: photo.date,
                kind: .photo,
                presetID: preset.id,
                aspect: photo.aspect,
                hasRAW: hasRAW,
                placeName: place,
                rawExposureOffset: developed.rawExposureOffset,
                mirrored: photo.mirror,
                frame: frame,
                grainLevel: grainLevel,
                halationLevel: halationLevel,
                orientation: photo.orientation,
                portraitFNumber: photo.depth == nil ? nil : portraitFNumber,
                lensStyle: photo.depth == nil ? nil : lens
            )
            do {
                try captureStore.write(developed.heic, as: .processed, for: record.id)
                if let depthFile { try captureStore.write(depthFile, as: .depth, for: record.id) }
                try captureStore.write(developed.thumbnail, as: .thumbnail, for: record.id)
                if hasRAW, let raw = photo.raw { try captureStore.write(raw, as: .rawDNG, for: record.id) }
                // The camera's image before the preset: lets the photo be redeveloped without RAW, or after it expires.
                if let original = photo.processed { try captureStore.write(original, as: .original, for: record.id) }
                try captureStore.add(record)
                captures = captureStore.records
            } catch {
                alert = error.localizedDescription
                return
            }

            do {
                try await PhotoLibrarySaver.savePhoto(
                    heicURL: captureStore.url(.processed, for: record.id),
                    rawURL: hasRAW ? captureStore.url(.rawDNG, for: record.id) : nil
                )
            } catch {
                alert = error.localizedDescription
            }
        }
    }

    private func ingest(videoAt tempURL: URL, keepsLog: Bool) {
        let preset = selectedPreset
        let saveLocation = settings.savesLocation
        let grain = settings.grainLevel
        let halation = settings.halationLevel

        Task {
            let place = saveLocation ? await location.currentPlaceName() : nil
            let record = CaptureRecord(
                kind: .video,
                presetID: preset.id,
                aspect: .ratio16x9,
                placeName: place,
                grainLevel: grain,
                halationLevel: halation,
                logVideo: keepsLog
            )
            do {
                let destination = captureStore.url(.video, for: record.id)
                try FileManager.default.createDirectory(at: captureStore.folder(for: record.id), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                if let thumbnail = await Self.videoThumbnail(url: destination) {
                    try captureStore.write(thumbnail, as: .thumbnail, for: record.id)
                }
                try captureStore.add(record)
                captures = captureStore.records
                // Flat Log is saved as it is, so it can be downloaded and graded elsewhere; the preset is applied
                // later, from the gallery's Redevelop.
                try await PhotoLibrarySaver.saveVideo(url: destination)
            } catch {
                alert = error.localizedDescription
            }
        }
    }

    /// The video to play and share: the graded one once it is developed, otherwise the file as recorded.
    func videoURL(for record: CaptureRecord) -> URL {
        fileExistsForVideo(record) ? url(.processedVideo, for: record) : url(.video, for: record)
    }

    private func fileExistsForVideo(_ record: CaptureRecord) -> Bool {
        captureStore.fileExists(.processedVideo, for: record.id)
    }

    /// The look a Log video is graded with: the preset's Apple Log look, with grain and halation at the given levels.
    func videoDevelopLook(presetID: String, grain: GrainLevel, halation: EffectLevel) async -> FilmLook? {
        guard let preset = preset(id: presetID) else { return nil }
        let base = await baseLook(for: preset, slot: .appleLog)
        return base.with(
            grain: min(1, base.grain * grain.multiplier),
            halation: base.halation * halation.multiplier,
            adjustments: base.adjustments
        )
    }

    /// Grades a recorded Log video with a preset and the given grain and halation, into `processedVideo`.
    /// Frame by frame, so it takes about as long as the clip; the gallery card shows its progress.
    @discardableResult
    func redevelopVideo(_ record: CaptureRecord, presetID: String, grain: GrainLevel, halation: EffectLevel) async -> Bool {
        guard let look = await videoDevelopLook(presetID: presetID, grain: grain, halation: halation) else { return false }
        let id = record.id
        let source = captureStore.url(.video, for: id)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("redevelop-\(UUID().uuidString).mov")
        videoProgress[id] = 0
        defer { videoProgress[id] = nil }
        do {
            try await VideoRedeveloper.develop(source: source, output: temporary, look: look) { [weak self] value in
                Task { @MainActor in self?.videoProgress[id] = value }
            }
            let output = captureStore.url(.processedVideo, for: id)
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: temporary, to: output)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            alert = error.localizedDescription
            return false
        }
        var updated = record
        updated.presetID = presetID
        updated.grainLevel = grain
        updated.halationLevel = halation
        try? captureStore.update(updated)
        captures = captureStore.records
        if let thumbnail = await Self.videoThumbnail(url: captureStore.url(.processedVideo, for: id)) {
            try? captureStore.write(thumbnail, as: .thumbnail, for: id)
        }
        // The render always goes to Photos as well, with no sheet to choose from.
        try? await PhotoLibrarySaver.saveVideo(url: captureStore.url(.processedVideo, for: id))
        return true
    }

    private static func videoThumbnail(url: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image).jpegData(compressionQuality: 0.8)
    }

    // MARK: Redevelop

    /// A photo can be redeveloped from its RAW, or from the camera's original image.
    func canRedevelop(_ record: CaptureRecord) -> Bool {
        if record.kind == .video { return record.logVideo }
        return record.kind == .photo && (record.hasRAW || captureStore.fileExists(.original, for: record.id))
    }

    /// The RAW while it is kept, otherwise the camera's original image. Reads files; call off the main thread when possible.
    nonisolated static func redevelopSource(raw rawURL: URL, original originalURL: URL, hasRAW: Bool, exposureOffset: Double) -> PhotoPipeline.Source? {
        if hasRAW, let raw = try? Data(contentsOf: rawURL) { return .raw(raw, exposureOffset: exposureOffset) }
        if let original = try? Data(contentsOf: originalURL) { return .original(original) }
        return nil
    }

    func redevelopSource(for record: CaptureRecord) async -> PhotoPipeline.Source? {
        let rawURL = captureStore.url(.rawDNG, for: record.id)
        let originalURL = captureStore.url(.original, for: record.id)
        let hasRAW = record.hasRAW
        let offset = record.rawExposureOffset
        return await Task.detached(priority: .userInitiated) {
            Self.redevelopSource(raw: rawURL, original: originalURL, hasRAW: hasRAW, exposureOffset: offset)
        }.value
    }

    /// The depth map a portrait photo was blurred with; nil for other photos, or when it was not kept.
    func depthMap(for record: CaptureRecord) async -> DepthMap? {
        guard record.lensStyle != nil else { return nil }
        let url = captureStore.url(.depth, for: record.id)
        return await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: url)).flatMap { DepthMap(encoded: $0) }
        }.value
    }

    /// Re-renders a stored photo with a different preset and push/pull, replacing the processed image.
    /// A portrait photo's background is drawn again with `portraitFNumber` and `lens`.
    func redevelop(
        _ record: CaptureRecord,
        presetID: String,
        pushPull: Double,
        grain: GrainLevel,
        halation: EffectLevel,
        portraitFNumber: Double,
        lens: LensStyle,
        shadowLift: Double = 0
    ) async -> Bool {
        guard let preset = preset(id: presetID),
              let source = await redevelopSource(for: record)
        else { return false }
        let portrait = await depthMap(for: record).map {
            PhotoPipeline.PortraitDepth(map: $0, fNumber: portraitFNumber, lens: lens)
        }
        var look = await leveledLook(for: preset, grain: grain, halation: halation, shadowLift: shadowLift)
        if portrait != nil { look = look.with { lens.apply(to: &$0) } }
        let aspect = record.aspect
        let mirror = record.mirrored
        let orientation = record.orientation

        let developed = await Task.detached(priority: .userInitiated) {
            PhotoPipeline.redevelop(
                source: source,
                look: look,
                pushPull: pushPull,
                aspect: aspect,
                mirror: mirror,
                frame: record.frame,
                label: preset.name,
                accentIndex: preset.accentIndex,
                portrait: portrait,
                orientation: orientation
            )
        }.value
        guard let developed else { return false }

        do {
            try captureStore.write(developed.heic, as: .processed, for: record.id)
            try captureStore.write(developed.thumbnail, as: .thumbnail, for: record.id)
            var updated = record
            updated.presetID = presetID
            updated.evPushPull = pushPull
            updated.grainLevel = grain
            updated.halationLevel = halation
            updated.shadowLift = shadowLift
            if portrait != nil {
                updated.portraitFNumber = portraitFNumber
                updated.lensStyle = lens
            }
            try captureStore.update(updated)
            captures = captureStore.records
            try? await PhotoLibrarySaver.savePhoto(heicURL: captureStore.url(.processed, for: record.id), rawURL: nil)
            return true
        } catch {
            alert = error.localizedDescription
            return false
        }
    }

}
