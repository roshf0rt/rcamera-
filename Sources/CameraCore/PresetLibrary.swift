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

public enum PresetCatalog {
    public static let defaultCount = 10

    public static func defaults(count: Int = defaultCount) -> [Preset] {
        (1 ... count).map { Preset(id: "preset-\($0)", name: "Пресет \($0)", accentIndex: $0 - 1) }
    }
}

/// Presets plus the LUT files behind them.
///
/// LUTs are looked up as `<preset id>.cube` or `<preset id>.lut`, first in the user directory
/// (where imports go), then in the optional bundled directory.
public final class PresetLibrary {
    public static let lutExtensions = ["cube", "lut"]

    public private(set) var presets: [Preset]

    private let storageDirectory: URL
    private let userLUTDirectory: URL
    private let bundledLUTDirectory: URL?
    private let fileManager: FileManager
    private var lutCache: [String: LUT3D] = [:]

    private var presetsFile: URL { storageDirectory.appendingPathComponent("presets.json") }

    public init(storageDirectory: URL, bundledLUTDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.storageDirectory = storageDirectory
        self.userLUTDirectory = storageDirectory.appendingPathComponent("LUTs", isDirectory: true)
        self.bundledLUTDirectory = bundledLUTDirectory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: userLUTDirectory, withIntermediateDirectories: true)

        let presetsFile = storageDirectory.appendingPathComponent("presets.json")
        if let data = try? Data(contentsOf: presetsFile),
           let saved = try? JSONDecoder().decode([Preset].self, from: data),
           !saved.isEmpty {
            presets = saved
        } else {
            presets = PresetCatalog.defaults()
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
        try data.write(to: presetsFile, options: .atomic)
    }

    public func lutURL(for presetID: String) -> URL? {
        for directory in [userLUTDirectory, bundledLUTDirectory].compactMap({ $0 }) {
            for ext in Self.lutExtensions {
                let url = directory.appendingPathComponent("\(presetID).\(ext)")
                if fileManager.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    public func hasLUT(for presetID: String) -> Bool {
        lutURL(for: presetID) != nil
    }

    public func loadLUT(for presetID: String) throws -> LUT3D? {
        if let cached = lutCache[presetID] { return cached }
        guard let url = lutURL(for: presetID) else { return nil }
        let lut = try LUT3D.parse(data: Data(contentsOf: url), fileExtension: url.pathExtension)
        lutCache[presetID] = lut
        return lut
    }

    /// Validates the file, then copies it into the user LUT directory as `<preset id>.<ext>`.
    @discardableResult
    public func importLUT(from source: URL, for presetID: String) throws -> LUT3D {
        let ext = source.pathExtension.lowercased()
        guard Self.lutExtensions.contains(ext) else { throw LUTError.unsupportedFormat(ext) }
        let data = try Data(contentsOf: source)
        let lut = try LUT3D.parse(data: data, fileExtension: ext)

        try removeUserLUT(for: presetID)
        try data.write(to: userLUTDirectory.appendingPathComponent("\(presetID).\(ext)"), options: .atomic)
        lutCache[presetID] = lut
        return lut
    }

    /// Removes an imported LUT. Bundled LUTs stay.
    public func removeLUT(for presetID: String) throws {
        try removeUserLUT(for: presetID)
        lutCache[presetID] = nil
    }

    private func removeUserLUT(for presetID: String) throws {
        for ext in Self.lutExtensions {
            let url = userLUTDirectory.appendingPathComponent("\(presetID).\(ext)")
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }
}
