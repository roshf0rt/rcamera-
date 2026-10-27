import CameraCore
import CoreMotion
import Observation
import SwiftUI

/// Which way the phone is held, from gravity. The screen stays portrait; this turns the icons and the
/// captured photos and videos, as the system camera does, even with rotation lock on.
@MainActor
@Observable
final class OrientationMonitor {
    private(set) var current: DeviceOrientation = .portrait

    @ObservationIgnored private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 10.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let next = DeviceOrientation.from(gravityX: gravity.x, gravityY: gravity.y, previous: self.current)
                if next != self.current { self.current = next }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

private struct IconRotationKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    /// Degrees, clockwise, that icons turn to stay upright while the phone is held sideways.
    var iconRotation: Double {
        get { self[IconRotationKey.self] }
        set { self[IconRotationKey.self] = newValue }
    }
}

/// Turns a control's content with the phone, with a spring, like the system camera's icons.
struct FollowsDevice: ViewModifier {
    @Environment(\.iconRotation) private var angle

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: angle)
    }
}

extension View {
    func followsDevice() -> some View { modifier(FollowsDevice()) }
}
