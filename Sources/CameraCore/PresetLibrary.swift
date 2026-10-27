import Foundation

public struct Preset: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    /// 0...1 film grain amount applied after the LUT.
    public var grain: Double
    /// Picks the gradient shown on the preset card.
    public var accentIndex: Int

    public init(id: String, name: String, grain: Double = 0, accentIndex: Int) {
        self.id = id
        self.name = name
        self.grain = grain
        self.accentIndex = accentIndex
    }
}

/// A preset can carry up to three LUTs, one per kind of input.
public enum LUTSlot: String, CaseIterable, Codable, Sendable {
    /// Photos and the photo viewfinder.
    case photo
    /// Standard (Rec.709) video. Falls back to the photo LUT when missing.
    case video
    /// Apple Log video. Never falls back: a log image needs a log LUT.
    case appleLog

    public var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video (Rec.709)"
        case .appleLog: "Video (Apple Log)"
        }
    }

    var fileSuffix: String {
        switch self {
        case .photo: ""
        case .video: ".video"
        case .appleLog: ".applelog"
        }
    }
}

public enum PresetCatalog {
    public static let defaultCount = 10

    static func legacyName(index: Int) -> String { "Пресет \(index)" }

    public static func defaults(count: Int = defaultCount) -> [Preset] {
        (1 ... count).map { index in
            let name: String
            switch index {
            case 1: name = "JaneSu"
            case 2: name = "JaneSu 2"
            default: name = legacyName(index: index)
            }
            return Preset(id: "preset-\(index)", name: name, accentIndex: index - 1)
        }
    }
}

/// A LUT file that was read and validated but not stored yet. Parsing a 65^3 cube takes a moment,
/// so callers can prepare off the main thread and commit afterwards.
public struct PreparedLUT: Sendable {
    public let data: Data
    public let fileExtension: String
    public let lut: LUT3D
}

public enum LUTImport {
    public static func prepare(url: URL) throws -> PreparedLUT {
        let ext = url.pathExtension.lowercased()
        guard PresetLibrary.lutExtensions.contains(ext) else { throw LUTError.unsupportedFormat(ext) }
        let data = try Data(contentsOf: url)
        return PreparedLUT(data: data, fileExtension: ext, lut: try LUT3D.parse(data: data, fileExtension: ext))
    }
}

/// Presets plus the LUT files behind them.
///
/// LUTs are looked up as `<preset id>[.video|.applelog].cube` or `.lut`, first in the user directory
/// (where imports go), then in the optional bundled directory.
public final class PresetLibrary {
    public static let lutExtensions = ["cube", "lut"]

    public private(set) var presets: [Preset]

    private let storageDirectory: URL
    private let userLUTDirectory: URL
    private let bundledLUTDirectory: URL?
    private let fileManager: FileManager
    private var lutCache: [String: LUT3D] = [:]

    public init(storageDirectory: URL, bundledLUTDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.storageDirectory = storageDirectory
        self.userLUTDirectory = storageDirectory.appendingPathComponent("LUTs", isDirectory: true)
        self.bundledLUTDirectory = bundledLUTDirectory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: userLUTDirectory, withIntermediateDirectories: true)

        let defaults = PresetCatalog.defaults()
        let presetsFile = storageDirectory.appendingPathComponent("presets.json")
        if let data = try? Data(contentsOf: presetsFile),
           var saved = try? JSONDecoder().decode([Preset].self, from: data),
           !saved.isEmpty {
            // Presets still carrying an old placeholder name pick up the current default name.
            for index in saved.indices {
                guard let fresh = defaults.first(where: { $0.id == saved[index].id }) else { continue }
                if saved[index].name == PresetCatalog.legacyName(index: index + 1) { saved[index].name = fresh.name }
            }
            presets = saved
        } else {
            presets = defaults
        }
    }

    public func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    public func update(_ preset: Preset) throws {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        updated.grain = min(max(preset.grain, 0), 1)
        presets[index] = updated
        let data = try JSONEncoder().encode(presets)
        try data.write(to: storageDirectory.appendingPathComponent("presets.json"), options: .atomic)
    }

    // MARK: LUTs

    /// The file that holds exactly this slot, if any.
    public func lutURL(for presetID: String, slot: LUTSlot = .photo) -> URL? {
        for directory in [userLUTDirectory, bundledLUTDirectory].compactMap({ $0 }) {
            for ext in Self.lutExtensions {
                let url = directory.appendingPathComponent("\(presetID)\(slot.fileSuffix).\(ext)")
                if fileManager.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    public func hasLUT(for presetID: String, slot: LUTSlot = .photo) -> Bool {
        lutURL(for: presetID, slot: slot) != nil
    }

    public func hasAnyLUT(for presetID: String) -> Bool {
        LUTSlot.allCases.contains { hasLUT(for: presetID, slot: $0) }
    }

    /// The LUT to use for `slot`: the slot's own file, or for video the photo LUT.
    public func loadLUT(for presetID: String, slot: LUTSlot = .photo) throws -> LUT3D? {
        let key = "\(presetID)|\(slot.rawValue)"
        if let cached = lutCache[key] { return cached }
        let url = lutURL(for: presetID, slot: slot) ?? (slot == .video ? lutURL(for: presetID, slot: .photo) : nil)
        guard let url else { return nil }
        let lut = try LUT3D.parse(data: Data(contentsOf: url), fileExtension: url.pathExtension)
        lutCache[key] = lut
        return lut
    }

    /// Validates the file, then copies it into the user LUT directory.
    @discardableResult
    public func importLUT(from source: URL, for presetID: String, slot: LUTSlot = .photo) throws -> LUT3D {
        try commit(LUTImport.prepare(url: source), for: presetID, slot: slot)
    }

    @discardableResult
    public func commit(_ prepared: PreparedLUT, for presetID: String, slot: LUTSlot = .photo) throws -> LUT3D {
        try removeUserLUT(for: presetID, slot: slot)
        let name = "\(presetID)\(slot.fileSuffix).\(prepared.fileExtension)"
        try prepared.data.write(to: userLUTDirectory.appendingPathComponent(name), options: .atomic)
        invalidateCache(for: presetID)
        return prepared.lut
    }

    /// Removes an imported LUT. Bundled LUTs stay.
    public func removeLUT(for presetID: String, slot: LUTSlot = .photo) throws {
        try removeUserLUT(for: presetID, slot: slot)
        invalidateCache(for: presetID)
    }

    private func invalidateCache(for presetID: String) {
        for slot in LUTSlot.allCases { lutCache["\(presetID)|\(slot.rawValue)"] = nil }
    }

    private func removeUserLUT(for presetID: String, slot: LUTSlot) throws {
        for ext in Self.lutExtensions {
            let url = userLUTDirectory.appendingPathComponent("\(presetID)\(slot.fileSuffix).\(ext)")
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }
}
