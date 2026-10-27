import Foundation

/// A printed-looking border around saved photos, with the preset's name on the bottom band.
/// mood.camera has about thirty frames with film-stock defaults. This app has four frames, and `auto`
/// picks one per preset, since its presets stand in for film stocks.
public enum FrameStyle: String, CaseIterable, Codable, Sendable {
    case off
    case auto
    case gradient
    case dots
    case stripes
    case grid

    public var label: String {
        switch self {
        case .off: "Off"
        case .auto: "Auto"
        case .gradient: "Gradient"
        case .dots: "Dots"
        case .stripes: "Stripes"
        case .grid: "Grid"
        }
    }

    public var next: FrameStyle {
        let all = FrameStyle.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The pattern drawn over the gradient. Nil for frames without one.
    public var pattern: FramePattern {
        switch self {
        case .dots: .dots
        case .stripes: .stripes
        case .grid: .grid
        case .off, .auto, .gradient: .none
        }
    }

    /// The frame a photo gets. `auto` is replaced by the preset's default frame, which depends on its accent
    /// index. Every other frame is returned as it is.
    public func resolved(accentIndex: Int) -> FrameStyle {
        guard self == .auto else { return self }
        let defaults: [FrameStyle] = [.gradient, .dots, .stripes, .grid]
        let index = ((accentIndex % defaults.count) + defaults.count) % defaults.count
        return defaults[index]
    }
}

/// The pattern printed on the frame, drawn in the frame's own colours.
public enum FramePattern: Equatable, Sendable {
    case none
    case dots
    case stripes
    case grid
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
