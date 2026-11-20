import Foundation

/// The buttons of an underwater housing (ShellBox and others sold with the "ShellBoxCamera" app). The housing
/// pairs with the phone as a Bluetooth keyboard and types a character per button; its shutter button is a
/// volume key. The characters, as the housing's own app reads them:
///
/// - "1" and "2": zoom in and out
/// - "3": front or back camera
/// - "4": photo mode (and stops a recording)
/// - Return: video mode
public enum HousingRemote {
    public enum Action: Equatable, Sendable {
        case zoomIn
        case zoomOut
        case flipCamera
        case photoMode
        case videoMode
        case shutter
    }

    /// The action for the characters a key typed (`UIKey.charactersIgnoringModifiers`). Space works as the
    /// shutter too, for housings and remotes that send it.
    public static func action(for characters: String) -> Action? {
        switch characters {
        case "1": .zoomIn
        case "2": .zoomOut
        case "3": .flipCamera
        case "4": .photoMode
        case "\r", "\n", "\r\n": .videoMode
        case " ": .shutter
        default: nil
        }
    }

    /// Zoom in or out holds the zoom moving: one press steps by `stepFactor`, a held key keeps going by
    /// `holdFactor` per `holdInterval` seconds after `holdDelay`.
    public static let stepFactor = 1.25
    public static let holdFactor = 1.03
    public static let holdDelay = 0.35
    public static let holdInterval = 0.05

    /// The zoom after one press (`zoomIn` or `zoomOut`) from `zoom`, inside `range`.
    public static func zoom(_ zoom: Double, _ action: Action, factor: Double = stepFactor, range: ClosedRange<Double>) -> Double {
        let next: Double = switch action {
        case .zoomIn: zoom * factor
        case .zoomOut: zoom / factor
        default: zoom
        }
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// What the housing's buttons do, for the settings screen.
    public static let legend: [(key: String, action: String)] = [
        ("Volume / shutter", "Photo, or start and stop a recording"),
        ("1 / 2", "Zoom in / out (hold to keep zooming)"),
        ("3", "Front or back camera"),
        ("4", "Photo mode; stops a recording"),
        ("Return", "Video mode"),
    ]
}
