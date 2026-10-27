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
    let location = LocationProvider()
    let level = LevelMonitor()

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
        engine.setLook(look(for: selectedPreset))
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        try? settingsStore.save(updated)
        engine.update(settings: updated)
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
        engine.setLook(look(for: selectedPreset))
    }

    func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    func hasLUT(_ presetID: String) -> Bool {
        presetLibrary.hasLUT(for: presetID)
    }

    func updatePreset(_ preset: Preset) {
        do {
            try presetLibrary.update(preset)
            presets = presetLibrary.presets
            lookCache[preset.id] = nil
            if preset.id == settings.selectedPresetID { engine.setLook(look(for: selectedPreset)) }
        } catch {
            alert = error.localizedDescription
        }
    }

    func importLUT(from url: URL, presetID: String) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try presetLibrary.importLUT(from: url, for: presetID)
            lookCache[presetID] = nil
            if presetID == settings.selectedPresetID { engine.setLook(look(for: selectedPreset)) }
        } catch let error as LUTError {
            alert = Self.describe(error)
        } catch {
            alert = error.localizedDescription
        }
    }

    func removeLUT(presetID: String) {
        try? presetLibrary.removeLUT(for: presetID)
        lookCache[presetID] = nil
        if presetID == settings.selectedPresetID { engine.setLook(look(for: selectedPreset)) }
    }

    func look(for preset: Preset) -> FilmLook {
        if let cached = lookCache[preset.id] { return cached }
        let lut = try? presetLibrary.loadLUT(for: preset.id)
        let look = FilmLook(lut: lut, grain: preset.grain)
        lookCache[preset.id] = look
        return look
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
        let look = look(for: preset)
        let saveLocation = settings.savesLocation
        let keepRAW = settings.capturesRAW

        Task {
            let place = saveLocation ? await location.currentPlaceName() : nil
            let developed = await Task.detached(priority: .userInitiated) {
                PhotoPipeline.develop(
                    raw: photo.raw,
                    processed: photo.processed,
                    look: look,
                    pushPull: 0,
                    aspect: photo.aspect,
                    mirror: photo.mirror
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
                placeName: place
            )
            do {
                try captureStore.write(developed.heic, as: .processed, for: record.id)
                try captureStore.write(developed.thumbnail, as: .thumbnail, for: record.id)
                if hasRAW, let raw = photo.raw { try captureStore.write(raw, as: .rawDNG, for: record.id) }
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

    /// Re-renders a stored RAW with a different preset and push/pull, replacing the processed image.
    func redevelop(_ record: CaptureRecord, presetID: String, pushPull: Double) async -> Bool {
        guard let preset = preset(id: presetID),
              let raw = try? Data(contentsOf: captureStore.url(.rawDNG, for: record.id))
        else { return false }
        let look = look(for: preset)
        let aspect = record.aspect

        let developed = await Task.detached(priority: .userInitiated) {
            PhotoPipeline.develop(raw: raw, processed: nil, look: look, pushPull: pushPull, aspect: aspect, mirror: false)
        }.value
        guard let developed else { return false }

        do {
            try captureStore.write(developed.heic, as: .processed, for: record.id)
            try captureStore.write(developed.thumbnail, as: .thumbnail, for: record.id)
            var updated = record
            updated.presetID = presetID
            updated.evPushPull = pushPull
            try captureStore.update(updated)
            captures = captureStore.records
            try? await PhotoLibrarySaver.savePhoto(heicURL: captureStore.url(.processed, for: record.id), rawURL: nil)
            return true
        } catch {
            alert = error.localizedDescription
            return false
        }
    }

    func rawData(for record: CaptureRecord) -> Data? {
        try? Data(contentsOf: captureStore.url(.rawDNG, for: record.id))
    }
}
