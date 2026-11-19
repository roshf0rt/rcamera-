import Foundation

/// The video LUTs bundled as `App/Resources/LUTs/video-<key>.video.cube` (Rec.709) and
/// `video-<key>.applelog.cube` (Apple Log → Rec.709). Each look is a built-in preset, shown after the classic
/// presets and before the film looks. A look with only an Apple Log LUT is graded in Apple Log mode alone.
public enum VideoCollection {
    public static let idPrefix = "video-"

    public struct Entry: Sendable {
        public let key: String
        public let name: String
        /// Rec.709 LUT, used for standard video and, through the fallback, for photos.
        public let hasVideo: Bool
        /// Apple Log LUT, used when the camera records Apple Log.
        public let hasAppleLog: Bool

        public var id: String { VideoCollection.idPrefix + key }

        public var subtitle: String {
            switch (hasVideo, hasAppleLog) {
            case (true, true): "Video • Apple Log"
            case (true, false): "Video • LUT"
            default: "Apple Log only"
            }
        }
    }

    public static func isVideo(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    public static func entry(id: String) -> Entry? { entries.first { $0.id == id } }

    public static var ids: [String] { entries.map(\.id) }

    public static let entries: [Entry] = [
        Entry(key: "anji", name: "Anji", hasVideo: false, hasAppleLog: true),
        Entry(key: "chromadark", name: "Chroma Dark", hasVideo: false, hasAppleLog: true),
        Entry(key: "fade", name: "Fade", hasVideo: false, hasAppleLog: true),
        Entry(key: "falsecolour", name: "False Colour", hasVideo: false, hasAppleLog: true),
        Entry(key: "film03", name: "Film 03", hasVideo: false, hasAppleLog: true),
        Entry(key: "glost", name: "Glost", hasVideo: true, hasAppleLog: true),
        Entry(key: "kodiac", name: "Kodiac", hasVideo: true, hasAppleLog: true),
        Entry(key: "lectar", name: "Lectar", hasVideo: true, hasAppleLog: true),
        Entry(key: "natural", name: "Natural", hasVideo: false, hasAppleLog: true),
        Entry(key: "pillow", name: "Pillow", hasVideo: false, hasAppleLog: true),
        Entry(key: "sanda", name: "Sanda", hasVideo: true, hasAppleLog: true),
        Entry(key: "tyrel", name: "Tyrel", hasVideo: false, hasAppleLog: true),
        Entry(key: "verva", name: "Verva", hasVideo: false, hasAppleLog: true),
        Entry(key: "alpina", name: "Alpina", hasVideo: true, hasAppleLog: false),
        Entry(key: "mellow", name: "Mellow", hasVideo: true, hasAppleLog: false),
        Entry(key: "monobw", name: "Mono BW", hasVideo: true, hasAppleLog: false),
        Entry(key: "tamaris", name: "Tamaris", hasVideo: true, hasAppleLog: false),
        Entry(key: "wallis", name: "Wallis", hasVideo: true, hasAppleLog: false),
        Entry(key: "base-sdr", name: "Base SDR", hasVideo: true, hasAppleLog: false),
        Entry(key: "base-hdr", name: "Base HDR", hasVideo: true, hasAppleLog: false),
        // IvakinColor pack: the REC709 file is the video LUT, the LOG file the Apple Log one.
        Entry(key: "ivakin-cabinet", name: "Cabinet", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-film2", name: "Film 2", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-baby-day", name: "Baby Day", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-baby-night", name: "Baby Night", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-lut", name: "Ivakin", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-osen", name: "Osen", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-sup8", name: "Super 8", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-vision3", name: "Vision 3", hasVideo: true, hasAppleLog: true),
        Entry(key: "ivakin-skin", name: "Skin", hasVideo: true, hasAppleLog: false),
    ]
}
