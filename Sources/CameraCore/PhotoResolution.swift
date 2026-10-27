import Foundation

/// The photo size the camera asks for: about 12 MP (the default, quick to capture) or the largest the format
/// offers (48 MP on the models that have it).
public enum PhotoResolution: String, CaseIterable, Codable, Sendable {
    case mp12
    case mp48

    public var label: String {
        switch self {
        case .mp12: "12MP"
        case .mp48: "48MP"
        }
    }

    /// Photos with more pixels than this are not offered. Nil means no limit.
    public var pixelLimit: Int? {
        switch self {
        case .mp12: FormatChooser.preferredPhotoPixels
        case .mp48: nil
        }
    }

    public var next: PhotoResolution {
        let all = PhotoResolution.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
