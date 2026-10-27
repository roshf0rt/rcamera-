import Foundation

/// Cinematic auto exposure, as the Kino app does it: the shutter stays at the 180° rule (half the frame
/// time, so 1/48 s at 24 fps) for natural motion blur, and ISO carries the exposure. Only when ISO runs
/// out does the shutter give way: faster in bright light (there is no ND filter), slower in the dark,
/// but never longer than one frame.
public enum CineExposure {
    public struct Limits: Equatable, Sendable {
        public var minISO: Double
        public var maxISO: Double
        /// Seconds.
        public var minDuration: Double
        public var maxDuration: Double

        public init(minISO: Double, maxISO: Double, minDuration: Double, maxDuration: Double) {
            self.minISO = minISO
            self.maxISO = maxISO
            self.minDuration = minDuration
            self.maxDuration = maxDuration
        }
    }

    public struct Setting: Equatable, Sendable {
        public var iso: Double
        /// Seconds.
        public var duration: Double

        public init(iso: Double, duration: Double) {
            self.iso = iso
            self.duration = duration
        }
    }

    /// The 180° shutter for a frame rate.
    public static func shutter(fps: Int) -> Double {
        1 / Double(2 * max(fps, 1))
    }

    /// One step of the loop. `offset` is how far the metered exposure is above the target, in EV
    /// (positive: too bright). `damping` takes part of the correction per step, so the picture does not pump.
    public static func next(current: Setting, offset: Double, fps: Int, limits: Limits, damping: Double = 0.5) -> Setting {
        let correction = abs(offset) < 0.05 ? 0 : -offset * damping
        let exposure = current.iso * current.duration * pow(2, correction)
        let longest = min(limits.maxDuration, 1 / Double(max(fps, 1)))
        let preferred = min(max(shutter(fps: fps), limits.minDuration), longest)

        // Already at the cine shutter and on target: nothing to change.
        if correction == 0, abs(current.duration - preferred) < 1e-9 { return current }

        var duration = preferred
        var iso = exposure / duration
        if iso > limits.maxISO {
            iso = limits.maxISO
            duration = min(exposure / iso, longest)
        } else if iso < limits.minISO {
            iso = limits.minISO
            duration = max(exposure / iso, limits.minDuration)
        }
        return Setting(iso: min(max(iso, limits.minISO), limits.maxISO), duration: duration)
    }

    /// "1/48 · ISO 320", for the viewfinder.
    public static func readout(_ setting: Setting) -> String {
        let denominator = Int((1 / setting.duration).rounded())
        return "1/\(denominator) · ISO \(Int(setting.iso.rounded()))"
    }
}
