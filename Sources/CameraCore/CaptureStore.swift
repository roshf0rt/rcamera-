import Foundation

public enum CaptureKind: String, Codable, Sendable {
    case photo
    case video
}

public enum CaptureFile: String, Sendable {
    case rawDNG = "original.dng"
    case processed = "processed.heic"
    case thumbnail = "thumb.jpg"
    case video = "video.mov"
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

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: CaptureKind,
        presetID: String,
        evPushPull: Double = 0,
        aspect: AspectOption = .ratio4x3,
        hasRAW: Bool = false,
        placeName: String? = nil,
        isFavorite: Bool = false
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
