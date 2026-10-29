import Foundation

/// The cinematic shutter rule and its readouts: 180° (half the frame time, so 1/48 s at 24 fps) for natural
/// motion blur, moved to a flicker-free time under mains lighting. `MotionExposure` runs the exposure on it.
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

    /// The shutter the loop aims for: 180°, or, under mains lighting, the flicker-free time closest to
    /// it (a whole number of light pulses, 1/100 s each at 50 Hz, 1/120 s at 60 Hz), as long as it fits
    /// in a frame and stays between 144° and 216°. So 24 fps runs at 1/50 in Europe and 1/48 or 1/60 in America.
    public static func referenceShutter(fps: Int, mainsHz: Int?) -> Double {
        let ideal = shutter(fps: fps)
        guard let mainsHz, mainsHz > 0 else { return ideal }
        let pulse = 1 / Double(2 * mainsHz)
        let frame = 1 / Double(max(fps, 1))
        let low: Double = ideal * 0.8
        let high: Double = ideal * 1.2
        var candidates: [Double] = []
        for count in 1 ... 12 {
            let time = Double(count) * pulse
            if time <= frame, time >= low, time <= high { candidates.append(time) }
        }
        // A slightly shorter time is preferred to a slightly longer one: crisper motion.
        func score(_ time: Double) -> Double { abs(log(time / ideal)) + (time > ideal ? 0.05 : 0) }
        return candidates.min { score($0) < score($1) } ?? ideal
    }

    /// Mains frequency for a region code: 60 Hz in the Americas (mostly), Korea, Taiwan, the Philippines
    /// and Saudi Arabia, 50 Hz elsewhere (Japan is split; Tokyo is 50).
    public static func mainsFrequency(regionCode: String?) -> Int {
        let sixty: Set<String> = [
            "US", "CA", "MX", "BR", "CO", "VE", "EC", "PE", "CU", "DO", "GT", "HN", "NI", "SV", "CR", "PA",
            "PR", "BS", "BZ", "HT", "JM", "TT", "KR", "TW", "PH", "SA", "LR",
        ]
        return regionCode.map { sixty.contains($0.uppercased()) } == true ? 60 : 50
    }

    /// "1/48 · ISO 320", for the viewfinder.
    public static func readout(_ setting: Setting) -> String {
        "\(shutterText(setting.duration)) · ISO \(Int(setting.iso.rounded()))"
    }

    /// "1/50", or "0.5s" for times of a quarter second and longer.
    public static func shutterText(_ duration: Double) -> String {
        guard duration > 0 else { return "—" }
        if duration >= 0.25 { return String(format: "%.1fs", duration) }
        return "1/\(Int((1 / duration).rounded()))"
    }

    /// The shutter as a film camera's rotating shutter would be set: 180° is half the frame time.
    public static func shutterAngle(duration: Double, fps: Int) -> Int {
        Int((duration * Double(max(fps, 1)) * 360).rounded())
    }
}
