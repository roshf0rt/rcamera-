import Foundation

/// A printed-looking border around saved photos, with the preset's name on the bottom band.
/// mood.camera has about thirty of these with film-stock defaults; this app draws one gradient frame,
/// coloured by the preset card's gradient.
public enum FrameStyle: String, CaseIterable, Codable, Sendable {
    case off
    case gradient

    public var label: String {
        switch self {
        case .off: "Off"
        case .gradient: "Gradient"
        }
    }

    public var next: FrameStyle {
        let all = FrameStyle.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Border widths in pixels, proportional to the photo so the frame looks the same at any size.
public struct FrameLayout: Equatable, Sendable {
    public let side: Int
    public let top: Int
    public let bottom: Int

    public init(side: Int, top: Int, bottom: Int) {
        self.side = side
        self.top = top
        self.bottom = bottom
    }

    /// Sides and top are 4% of the shorter edge, the bottom band is three times that for the label.
    public static func make(width: Int, height: Int) -> FrameLayout {
        let edge = max(1, min(width, height) / 25)
        return FrameLayout(side: edge, top: edge, bottom: edge * 3)
    }

    public func canvasWidth(photoWidth: Int) -> Int { photoWidth + 2 * side }
    public func canvasHeight(photoHeight: Int) -> Int { photoHeight + top + bottom }
}
