import Foundation

public enum CaptureKind: String, Codable, Sendable {
    case photo
    case video
}

public enum CaptureFile: String, Sendable {
    case rawDNG = "original.dng"
    /// The camera's own image before the preset, kept when there is no RAW so the photo can still be redeveloped.
    case original = "original.heic"
    case processed = "processed.heic"
    case thumbnail = "thumb.jpg"
    case video = "video.mov"
    /// Portrait photos: the depth map the background was blurred with, so Redevelop can change the lens and aperture.
    case depth = "depth.bin"
}

public struct CaptureRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: CaptureKind
    public var presetID: String
    /// Push/pull applied when the RAW was last developed.
    public var evPushPull: Double
    public var aspect: AspectOption
    public var hasRAW: Bool
    public var placeName: String?
    public var isFavorite: Bool
    /// EV offset that makes a developed RAW match the camera's own processed image in brightness.
    public var rawExposureOffset: Double
    /// Front-camera photo saved mirrored; redevelop mirrors it again.
    public var mirrored: Bool
    /// How much film grain and halation the saved image has. Redevelop can change them.
    public var grainLevel: GrainLevel
    public var halationLevel: EffectLevel
    public var grainEnabled: Bool { grainLevel != .off }
    public var halationEnabled: Bool { halationLevel != .off }
    /// Border the saved photo was made with. Redevelop keeps it.
    public var frame: FrameStyle
    /// How the phone was held; the saved photo is turned to match, and Redevelop turns it again.
    public var orientation: DeviceOrientation
    /// Portrait photos: the f-number and lens the background was drawn with. Nil for other photos. Redevelop changes them.
    public var portraitFNumber: Double?
    public var lensStyle: LensStyle?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: CaptureKind,
        presetID: String,
        evPushPull: Double = 0,
        aspect: AspectOption = .ratio4x3,
        hasRAW: Bool = false,
        placeName: String? = nil,
        isFavorite: Bool = false,
        rawExposureOffset: Double = 0,
        mirrored: Bool = false,
        frame: FrameStyle = .off,
        grainLevel: GrainLevel = .medium,
        halationLevel: EffectLevel = .medium,
        orientation: DeviceOrientation = .portrait,
        portraitFNumber: Double? = nil,
        lensStyle: LensStyle? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.presetID = presetID
        self.evPushPull = evPushPull
        self.aspect = aspect
        self.hasRAW = hasRAW
        self.placeName = placeName
        self.isFavorite = isFavorite
        self.rawExposureOffset = rawExposureOffset
        self.mirrored = mirrored
        self.frame = frame
        self.grainLevel = grainLevel
        self.halationLevel = halationLevel
        self.orientation = orientation
        self.portraitFNumber = portraitFNumber
        self.lensStyle = lensStyle
    }

    enum CodingKeys: String, CodingKey {
        case id, date, kind, presetID, evPushPull, aspect, hasRAW, placeName, isFavorite, rawExposureOffset, mirrored, frame
        case grainLevel, halationLevel, grainEnabled, halationEnabled, orientation, portraitFNumber, lensStyle
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(kind, forKey: .kind)
        try c.encode(presetID, forKey: .presetID)
        try c.encode(evPushPull, forKey: .evPushPull)
        try c.encode(aspect, forKey: .aspect)
        try c.encode(hasRAW, forKey: .hasRAW)
        try c.encodeIfPresent(placeName, forKey: .placeName)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(rawExposureOffset, forKey: .rawExposureOffset)
        try c.encode(mirrored, forKey: .mirrored)
        try c.encode(frame, forKey: .frame)
        try c.encode(grainLevel, forKey: .grainLevel)
        try c.encode(halationLevel, forKey: .halationLevel)
        try c.encode(orientation, forKey: .orientation)
        try c.encodeIfPresent(portraitFNumber, forKey: .portraitFNumber)
        try c.encodeIfPresent(lensStyle, forKey: .lensStyle)
    }

    /// Index files from earlier releases lack newer keys; they keep their captures.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        kind = try c.decode(CaptureKind.self, forKey: .kind)
        presetID = try c.decode(String.self, forKey: .presetID)
        evPushPull = (try? c.decode(Double.self, forKey: .evPushPull)) ?? 0
        aspect = (try? c.decode(AspectOption.self, forKey: .aspect)) ?? .ratio4x3
        hasRAW = (try? c.decode(Bool.self, forKey: .hasRAW)) ?? false
        placeName = try? c.decode(String?.self, forKey: .placeName)
        isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
        rawExposureOffset = (try? c.decode(Double.self, forKey: .rawExposureOffset)) ?? 0
        mirrored = (try? c.decode(Bool.self, forKey: .mirrored)) ?? false
        frame = (try? c.decode(FrameStyle.self, forKey: .frame)) ?? .off
        // Earlier index files only know on or off.
        grainLevel = (try? c.decode(GrainLevel.self, forKey: .grainLevel))
            ?? ((try? c.decode(Bool.self, forKey: .grainEnabled)) ?? true ? .medium : .off)
        halationLevel = (try? c.decode(EffectLevel.self, forKey: .halationLevel))
            ?? ((try? c.decode(Bool.self, forKey: .halationEnabled)) ?? true ? .medium : .off)
        orientation = (try? c.decode(DeviceOrientation.self, forKey: .orientation)) ?? .portrait
        portraitFNumber = try? c.decodeIfPresent(Double.self, forKey: .portraitFNumber)
        lensStyle = try? c.decodeIfPresent(LensStyle.self, forKey: .lensStyle)
    }
}

/// Captures on disk: one folder per capture plus a JSON index. RAW files expire after
/// `rawRetentionDays`.
public final class CaptureStore {
    public static let rawRetentionDays = 30

    /// Newest first.
    public private(set) var records: [CaptureRecord]

    private let directory: URL
    private let fileManager: FileManager
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
           let saved = try? decoder.decode([CaptureRecord].self, from: data) {
            records = saved.sorted { $0.date > $1.date }
        } else {
            records = []
        }
    }

    public func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func url(_ file: CaptureFile, for id: UUID) -> URL {
        folder(for: id).appendingPathComponent(file.rawValue)
    }

    public func fileExists(_ file: CaptureFile, for id: UUID) -> Bool {
        fileManager.fileExists(atPath: url(file, for: id).path)
    }

    public func record(id: UUID) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    /// Writes `data` into the capture folder, creating the folder when needed.
    public func write(_ data: Data, as file: CaptureFile, for id: UUID) throws {
        try fileManager.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
        try data.write(to: url(file, for: id), options: .atomic)
    }

    public func add(_ record: CaptureRecord) throws {
        records.insert(record, at: 0)
        records.sort { $0.date > $1.date }
        try saveIndex()
    }

    public func update(_ record: CaptureRecord) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        try saveIndex()
    }

    public func remove(id: UUID) throws {
        records.removeAll { $0.id == id }
        if fileManager.fileExists(atPath: folder(for: id).path) {
            try fileManager.removeItem(at: folder(for: id))
        }
        try saveIndex()
    }

    /// Deletes RAW files older than the retention window. Returns the affected capture ids.
    @discardableResult
    public func purgeExpiredRAW(now: Date = Date()) throws -> [UUID] {
        var purged: [UUID] = []
        for index in records.indices where records[index].hasRAW {
            if daysUntilRAWExpires(records[index], now: now) <= 0 {
                let url = self.url(.rawDNG, for: records[index].id)
                if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
                records[index].hasRAW = false
                purged.append(records[index].id)
            }
        }
        if !purged.isEmpty { try saveIndex() }
        return purged
    }

    public func daysUntilRAWExpires(_ record: CaptureRecord, now: Date = Date()) -> Int {
        let expiry = record.date.addingTimeInterval(TimeInterval(Self.rawRetentionDays) * 86_400)
        return Int((expiry.timeIntervalSince(now) / 86_400).rounded(.up))
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: indexURL, options: .atomic)
    }
}
