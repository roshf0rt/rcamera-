import Foundation

/// How the phone is held, from gravity, for an app whose screen stays portrait: the icons turn to stay
/// upright and photos and videos come out the way the phone was held, as in the system camera.
public enum DeviceOrientation: String, Codable, Sendable {
    case portrait
    /// Top of the phone to the left (gravity along -x).
    case landscapeLeft
    /// Top of the phone to the right (gravity along +x).
    case landscapeRight

    /// From the gravity vector in device axes (x right, y up). Needs a clear tilt past 45° plus a margin
    /// before it changes, so it does not flicker at the diagonal; lying flat keeps the last orientation.
    public static func from(gravityX x: Double, gravityY y: Double, previous: DeviceOrientation) -> DeviceOrientation {
        let margin = 0.2
        guard x * x + y * y > 0.25 else { return previous }
        if abs(x) > abs(y) + margin { return x < 0 ? .landscapeLeft : .landscapeRight }
        if y < 0, abs(y) > abs(x) + margin { return .portrait }
        return previous
    }

    /// Degrees the on-screen icons turn, clockwise, to stay upright.
    public var iconRotation: Double {
        switch self {
        case .portrait: 0
        case .landscapeLeft: 90
        case .landscapeRight: -90
        }
    }

    /// Quarter turns, counter-clockwise, that bring a portrait frame to how the phone was held:
    /// 1 for top-left, -1 for top-right. Stored with each capture so Redevelop turns it the same way.
    public var quarterTurns: Int {
        switch self {
        case .portrait: 0
        case .landscapeLeft: 1
        case .landscapeRight: -1
        }
    }
}
