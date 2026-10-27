import Foundation

public struct Preset: Identifiable, Equatable, Codable, Sendable {
    /// True for presets the user added. Only these can be deleted.
    public var isCustom: Bool { id.hasPrefix(PresetCatalog.customPrefix) }

    public var id: String
    public var name: String
    /// 0...1 film grain amount applied after the LUT.
    public var grain: Double
    /// 0...1 red glow around bright areas, applied after the LUT.
    public var halation: Double
    /// Picks the gradient shown on the preset card.
    public var accentIndex: Int
    /// Manual regulators on top of the LUT. Neutral unless the user changes them.
    public var adjustments: LookAdjustments
    /// Left out of the camera's preset row and Camera Control; still listed in Settings.
    public var isHidden: Bool

    public init(
        id: String,
        name: String,
        grain: Double = 0,
        halation: Double = 0,
        accentIndex: Int,
        adjustments: LookAdjustments = .neutral,
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.grain = grain
        self.halation = halation
        self.accentIndex = accentIndex
        self.adjustments = adjustments
        self.isHidden = isHidden
    }

    enum CodingKeys: String, CodingKey { case id, name, grain, halation, accentIndex, adjustments, isHidden }

    /// Files written before halation existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        grain = (try? c.decode(Double.self, forKey: .grain)) ?? 0
        halation = (try? c.decode(Double.self, forKey: .halation)) ?? 0
        accentIndex = (try? c.decode(Int.self, forKey: .accentIndex)) ?? 0
        adjustments = (try? c.decode(LookAdjustments.self, forKey: .adjustments)) ?? .neutral
        isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
    }
}

/// A preset can carry up to three LUTs, one per kind of input.
public enum LUTSlot: String, CaseIterable, Codable, Sendable {
    /// Photos and the photo viewfinder. Falls back to the video LUT when missing.
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
    /// Presets the user adds start with this, so they can be told apart from the built-in ten.
    public static let customPrefix = "custom-"
    /// Bumped whenever default names or looks change, so older installs can adopt them.
    /// Revision 4 locked the built-in presets; earlier edits to them move into custom copies.
    /// Revision 5 put the presets in `displayOrder` and hid every other one.
    public static let revision = 5
    static let lockRevision = 4
    static let orderRevision = 5

    /// The order the camera shows the built-in presets in: JaneSu, Solstice, Velvet, Rise, Carbon,
    /// Clear, Mosaic, Silver, Sienna, Drift.
    public static let displayOrder = ["preset-1", "preset-9", "preset-10", "preset-6", "preset-2", "preset-3", "preset-5", "preset-8", "preset-7", "preset-4"]

    /// JaneSu first, then the Roshfort collection.
    static let names = ["JaneSu", "Carbon", "Clear", "Drift", "Mosaic", "Rise", "Sienna", "Silver", "Solstice", "Velvet"]
    /// Film grain amount each preset starts with (see `FilmMath.grainIntensity`).
    static let grain = [0.5, 0.45, 0.35, 0.45, 0.55, 0.45, 0.45, 0.5, 0.45, 0.45]
    /// Halation strength each preset starts with (see `FilmMath.halationStrength`).
    static let halation = [0.6, 0.55, 0.5, 0.6, 0.6, 0.6, 0.65, 0.55, 0.65, 0.6]
    /// Revision 3 changed how grain and halation are rendered, so earlier amounts are replaced.
    static let filmRevision = 3

    /// Names earlier releases used as placeholders. They are replaced, user-chosen names are not.
    static func isOldPlaceholder(_ name: String, index: Int) -> Bool {
        name == "Пресет \(index)" || name == "JaneSu 2"
    }

    public static func defaults(count: Int = defaultCount) -> [Preset] {
        (1 ... count).map { index in
            let slot = (index - 1) % names.count
            return Preset(
                id: "preset-\(index)",
                name: index <= names.count ? names[slot] : "Пресет \(index)",
                grain: grain[slot],
                halation: halation[slot],
                accentIndex: index - 1
            )
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
        let revisionFile = storageDirectory.appendingPathComponent("catalog-revision")
        let savedRevision = (try? String(contentsOf: revisionFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0

        if let data = try? Data(contentsOf: presetsFile),
           var saved = try? JSONDecoder().decode([Preset].self, from: data),
           !saved.isEmpty {
            if savedRevision < PresetCatalog.revision {
                // Older installs adopt the new default names, and the default grain and halation
                // where the user never touched them (both still zero) or the renderer changed.
                for index in saved.indices {
                    guard let fresh = defaults.first(where: { $0.id == saved[index].id }) else { continue }
                    if PresetCatalog.isOldPlaceholder(saved[index].name, index: index + 1) { saved[index].name = fresh.name }
                    let untouched = saved[index].grain == 0 && saved[index].halation == 0
                    if untouched || savedRevision < PresetCatalog.filmRevision {
                        saved[index].grain = fresh.grain
                        saved[index].halation = fresh.halation
                    }
                }
                try? JSONEncoder().encode(saved).write(to: presetsFile, options: .atomic)
            }
            presets = saved
        } else {
            presets = defaults
        }
        if savedRevision < PresetCatalog.lockRevision {
            moveBuiltInEditsToCustomCopies(defaults: defaults)
        }
        if savedRevision < PresetCatalog.orderRevision {
            adoptDisplayOrder()
        }
        try? "\(PresetCatalog.revision)".write(to: revisionFile, atomically: true, encoding: .utf8)
    }

    /// Built-in presets only change through film speed, contrast curve and dynamic range now. A built-in
    /// the user had changed in other ways is kept as a custom copy (with its LUTs), then reset.
    private func moveBuiltInEditsToCustomCopies(defaults: [Preset]) {
        var changed = false
        for index in presets.indices {
            let stored = presets[index]
            guard !stored.isCustom, let fresh = defaults.first(where: { $0.id == stored.id }) else { continue }
            let locked = Self.lockedEdit(stored: fresh, edited: stored)
            let renamed = stored.name != fresh.name
            if locked != stored || renamed {
                var copy = stored
                copy.id = PresetCatalog.customPrefix + UUID().uuidString.lowercased()
                copy.name = renamed ? stored.name : "\(stored.name) Custom"
                presets.append(copy)
                copyLUTs(from: stored.id, to: copy.id)
            }
            // Film speed, curve and range choices stay on the built-in itself.
            presets[index] = locked
            changed = true
        }
        if changed { try? save() }
    }

    /// Puts the built-in presets in `PresetCatalog.displayOrder` and hides every preset outside it.
    /// Hidden presets keep their files and can be shown again from Settings.
    private func adoptDisplayOrder() {
        let order = PresetCatalog.displayOrder
        for index in presets.indices {
            presets[index].isHidden = !order.contains(presets[index].id)
        }
        try? reorder(order)
        try? save()
    }

    /// What may change on a built-in preset: the film speed's values (grain, grain size, sharpness,
    /// fringing), the contrast curve's tone, dynamic range and the card's colours. Everything else stays as stored.
    public static func lockedEdit(stored: Preset, edited: Preset) -> Preset {
        var result = stored
        result.grain = edited.grain
        result.accentIndex = edited.accentIndex
        var look = stored.adjustments
        let wanted = edited.adjustments
        look.grainSize = wanted.grainSize
        look.sharpness = wanted.sharpness
        look.chromaticAberration = wanted.chromaticAberration
        look.contrast = wanted.contrast
        look.postExposure = wanted.postExposure
        look.shadows = wanted.shadows
        look.midpoint = wanted.midpoint
        look.highlights = wanted.highlights
        look.fade = wanted.fade
        look.mute = wanted.mute
        look.saturation = wanted.saturation
        look.filmStrength = wanted.filmStrength
        look.curve = wanted.curve
        look.dynamicRange = wanted.dynamicRange
        result.adjustments = look
        return result
    }

    public func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    /// Saves a preset. Built-in presets only take the changes `lockedEdit` allows.
    public func update(_ preset: Preset) throws {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset.isCustom ? preset : Self.lockedEdit(stored: presets[index], edited: preset)
        updated.grain = min(max(updated.grain, 0), 1)
        updated.halation = min(max(updated.halation, 0), 1)
        presets[index] = updated
        try save()
    }

    /// Adds a custom preset. With a `source` it starts as a copy of that look, LUT files included;
    /// without one it starts from scratch: no LUT, no grain or halation, neutral regulators.
    @discardableResult
    public func addCustom(copying source: Preset?, name: String = "New Preset", accentIndex: Int? = nil) throws -> Preset {
        let id = PresetCatalog.customPrefix + UUID().uuidString.lowercased()
        var preset = source ?? Preset(id: id, name: name, accentIndex: accentIndex ?? 0)
        preset.id = id
        preset.name = name
        if let accentIndex { preset.accentIndex = accentIndex }
        presets.append(preset)
        if let source { copyLUTs(from: source.id, to: id) }
        try save()
        return preset
    }

    /// Puts a built-in preset back to how it ships. Custom presets are left alone.
    public func resetBuiltIn(id: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }), !presets[index].isCustom,
              let fresh = PresetCatalog.defaults().first(where: { $0.id == id })
        else { return }
        presets[index] = fresh
        try save()
    }

    /// Gives a preset's LUTs (bundled or imported) to another preset as imported files.
    private func copyLUTs(from sourceID: String, to targetID: String) {
        for slot in LUTSlot.allCases {
            guard let url = lutURL(for: sourceID, slot: slot), lutURL(for: targetID, slot: slot) == nil else { continue }
            let target = userLUTDirectory.appendingPathComponent("\(targetID)\(slot.fileSuffix).\(url.pathExtension)")
            try? fileManager.copyItem(at: url, to: target)
        }
        invalidateCache(for: targetID)
    }

    // MARK: Covers

    private var coverDirectory: URL { storageDirectory.appendingPathComponent("Covers", isDirectory: true) }

    /// The picture a preset's card shows, if the user chose one.
    public func coverURL(for presetID: String) -> URL? {
        let url = coverDirectory.appendingPathComponent("\(presetID).jpg")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Stores (or with nil removes) the card picture of a preset, as JPEG data.
    public func setCover(_ data: Data?, for presetID: String) throws {
        guard preset(id: presetID) != nil else { return }
        let url = coverDirectory.appendingPathComponent("\(presetID).jpg")
        if let data {
            try fileManager.createDirectory(at: coverDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Removes a custom preset and its LUT files. Built-in presets cannot be removed.
    public func removeCustom(id: String) throws {
        guard let preset = preset(id: id), preset.isCustom else { return }
        for slot in LUTSlot.allCases {
            try? removeLUT(for: preset.id, slot: slot)
        }
        lutCache = lutCache.filter { !$0.key.hasPrefix("\(preset.id)|") }
        try? setCover(nil, for: preset.id)
        presets.removeAll { $0.id == preset.id }
        try save()
    }

    /// Puts the presets in the order of `ids`, as the camera's picker shows them. Presets missing from
    /// `ids` keep their relative order after the listed ones.
    public func reorder(_ ids: [String]) throws {
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = presets.enumerated().sorted { lhs, rhs in
            let a = rank[lhs.element.id] ?? ids.count + lhs.offset
            let b = rank[rhs.element.id] ?? ids.count + rhs.offset
            return a < b
        }.map(\.element)
        guard ordered != presets else { return }
        presets = ordered
        try save()
    }

    /// Shows or hides a preset on the camera. The last visible preset cannot be hidden.
    public func setHidden(_ hidden: Bool, id: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }), presets[index].isHidden != hidden else { return }
        if hidden, presets.filter({ !$0.isHidden }).count <= 1 { return }
        presets[index].isHidden = hidden
        try save()
    }

    /// The preset as JSON, for sharing. The LUTs are not included.
    public func exportData(for id: String) throws -> Data {
        guard let preset = preset(id: id) else { throw CocoaError(.fileNoSuchFile) }
        return try JSONEncoder.sortedPretty.encode(preset)
    }

    private func save() throws {
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

    /// The LUT to use for `slot`: the slot's own file, or the other display-referred one
    /// (photo and standard video look alike). Apple Log never falls back.
    public func loadLUT(for presetID: String, slot: LUTSlot = .photo) throws -> LUT3D? {
        let key = "\(presetID)|\(slot.rawValue)"
        if let cached = lutCache[key] { return cached }
        let alternate: LUTSlot? = switch slot {
        case .photo: .video
        case .video: .photo
        case .appleLog: nil
        }
        let url = lutURL(for: presetID, slot: slot) ?? alternate.flatMap { lutURL(for: presetID, slot: $0) }
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

extension JSONEncoder {
    /// Readable JSON for files people share.
    static var sortedPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
