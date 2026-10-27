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
        engine.onVideo = { [weak self] url in self?.ingest(videoAt: url) }
        engine.onModeChanged = { [weak self] mode in self?.updateSettings { $0.lastCaptureMode = mode } }
        volumeShutter.onPress = { [weak self] in self?.engine.shutterTapped() }
        NotificationCenter.default.addObserver(forName: .takePhotoRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.engine.shutterTapped() }
        }
        pushLooks()
        syncCameraControls()
    }

    /// The Camera Control button's lists: presets, grain and halation, plus aperture and lens in portrait mode.
    func syncCameraControls() {
        let presets = presets
        let selected = presets.firstIndex { $0.id == settings.selectedPresetID } ?? 0
        let levels = GrainLevel.allCases
        let stops = PortraitAperture.stops
        let lenses = LensStyle.allCases.sorted { $0.order < $1.order }
        var pickers: [CaptureSessionController.ControlPicker] = [
            .init(title: "Preset", symbol: "camera.filters", titles: presets.map(\.name), selected: selected) { [weak self] index in
                Task { @MainActor in
                    guard let self, self.presets.indices.contains(index) else { return }
                    self.selectPreset(self.presets[index].id)
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
            if settings.selectedPresetID == id, let first = presets.first { selectPreset(first.id) }
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
            || updated.dynamicRange != settings.dynamicRange
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
        presets.first { $0.id == settings.selectedPresetID } ?? presets[0]
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
        let look = FilmLook(lut: lut, grain: preset.grain, halation: preset.halation, adjustments: preset.adjustments)
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

    /// The preset's look with the camera-screen grain and halation toggles applied.
    func cameraLook(for preset: Preset, slot: LUTSlot = .photo) async -> FilmLook {
        let base = await baseLook(for: preset, slot: slot)
        let look = base.with(
            grain: min(1, base.grain * settings.grainLevel.multiplier),
            halation: base.halation * settings.halationLevel.multiplier,
            adjustments: base.adjustments
        )
        // The dynamic-range strip is a photo control; video keeps the preset's own range.
        guard slot == .photo, let range = settings.dynamicRange.value else { return look }
        return look.with { $0.dynamicRange = range }
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

    func fileExists(_ file: CaptureFile, for record: CaptureRecord) -> Bool {
        captureStore.fileExists(file, for: record.id)
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
        let grainOn = settings.grainEnabled
        let halationOn = settings.halationEnabled
        let frame = settings.frame
        let portraitFNumber = settings.portraitFNumber
        let lens = settings.lensStyle

        Task {
            var look = await cameraLook(for: preset, slot: .photo)
            if photo.depth != nil { look = look.with { lens.apply(to: &$0) } }
            let place = saveLocation ? await location.currentPlaceName() : nil
            let developed = await Task.detached(priority: .userInitiated) {
                PhotoPipeline.develop(
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
                grainEnabled: grainOn,
                halationEnabled: halationOn,
                orientation: photo.orientation
            )
            do {
                try captureStore.write(developed.heic, as: .processed, for: record.id)
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

    private func ingest(videoAt tempURL: URL) {
        let preset = selectedPreset
        let saveLocation = settings.savesLocation

        Task {
            let place = saveLocation ? await location.currentPlaceName() : nil
            let record = CaptureRecord(kind: .video, presetID: preset.id, aspect: .ratio16x9, placeName: place)
            do {
                let destination = captureStore.url(.video, for: record.id)
                try FileManager.default.createDirectory(at: captureStore.folder(for: record.id), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                if let thumbnail = await Self.videoThumbnail(url: destination) {
                    try captureStore.write(thumbnail, as: .thumbnail, for: record.id)
                }
                try captureStore.add(record)
                captures = captureStore.records
                try await PhotoLibrarySaver.saveVideo(url: destination)
            } catch {
                alert = error.localizedDescription
            }
        }
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
        record.kind == .photo && (record.hasRAW || captureStore.fileExists(.original, for: record.id))
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

    /// Re-renders a stored photo with a different preset and push/pull, replacing the processed image.
    func redevelop(_ record: CaptureRecord, presetID: String, pushPull: Double, grain: Bool, halation: Bool) async -> Bool {
        guard let preset = preset(id: presetID),
              let source = await redevelopSource(for: record)
        else { return false }
        let look = await baseLook(for: preset).with(grain: grain, halation: halation)
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
            updated.grainEnabled = grain
            updated.halationEnabled = halation
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
