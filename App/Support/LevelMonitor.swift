import CoreMotion
import Observation

/// Phone roll in radians: 0 when held upright, used to draw the level line.
@MainActor
@Observable
final class LevelMonitor {
    private(set) var roll = 0.0

    @ObservationIgnored private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity else { return }
            let angle = atan2(gravity.x, -gravity.y)
            MainActor.assumeIsolated { self?.roll = angle }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
