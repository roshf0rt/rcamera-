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

    /// How the picture stands against the cinematic rule, for the indicator on the viewfinder.
    public enum Status: Equatable, Sendable {
        /// Shutter on its reference and the picture exposed right: green.
        case cinematic
        /// Shutter on its reference, exposure still moving towards the target: amber.
        case settling
        /// Too much light even at the lowest ISO: the shutter had to get faster. `ndStops` is the ND
        /// filter that would bring it back to the reference: red.
        case tooBright(ndStops: Double)
        /// Too little light: the shutter had to get slower than its reference: red.
        case tooDark
    }

    public struct Step: Equatable, Sendable {
        public var setting: Setting
        public var status: Status
    }

    /// ISO up to which the picture stays clean; above it the loop prefers a slower shutter first.
    public static let cleanISO = 1600.0

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

    /// One step of the loop. `offset` is how far the metered exposure is above the target, in EV
    /// (positive: too bright). Big errors are corrected fast, small ones gently, tiny ones not at all,
    /// so the picture neither lags nor pumps.
    ///
    /// Order of give: ISO within its clean range at the reference shutter; then, in the dark, the
    /// shutter opens to 270°, ISO climbs to its maximum, and only then the shutter opens to a full
    /// frame; in bright light the shutter has to get faster, since a phone has no ND filter.
    public static func step(current: Setting, offset: Double, fps: Int, limits: Limits, mainsHz: Int? = nil) -> Step {
        let magnitude = abs(offset)
        let damping = magnitude > 1.5 ? 0.75 : magnitude > 0.5 ? 0.5 : 0.3
        let correction = magnitude < 0.08 ? 0 : -offset * damping
        let exposure = current.iso * current.duration * pow(2, correction)
        let longest = min(limits.maxDuration, 1 / Double(max(fps, 1)))
        let reference = min(max(referenceShutter(fps: fps, mainsHz: mainsHz), limits.minDuration), longest)
        let clean = min(limits.maxISO, max(limits.minISO, cleanISO))

        let settled: Status = magnitude < 0.35 ? .cinematic : .settling

        // Already on the reference and on target: hold still.
        if correction == 0, abs(current.duration - reference) / reference < 0.01,
           current.iso >= limits.minISO, current.iso <= clean {
            return Step(setting: current, status: .cinematic)
        }

        var iso = exposure / reference
        if iso >= limits.minISO, iso <= clean {
            let setting = Setting(iso: iso, duration: reference)
            return Step(setting: setting, status: settled)
        }
        if iso < limits.minISO {
            let duration = max(exposure / limits.minISO, limits.minDuration)
            return Step(setting: Setting(iso: limits.minISO, duration: duration), status: .tooBright(ndStops: log2(reference / duration)))
        }
        // Too dark at clean ISO: open the shutter to 270° first.
        var duration = min(exposure / clean, reference * 1.5, longest)
        iso = exposure / duration
        if iso > clean {
            iso = min(iso, limits.maxISO)
            if exposure / iso > duration {
                duration = min(exposure / iso, longest)
            }
        }
        iso = min(max(exposure / duration, limits.minISO), limits.maxISO)
        return Step(setting: Setting(iso: iso, duration: duration), status: .tooDark)
    }

    /// One step, returning only the setting.
    public static func next(current: Setting, offset: Double, fps: Int, limits: Limits, mainsHz: Int? = nil) -> Setting {
        step(current: current, offset: offset, fps: fps, limits: limits, mainsHz: mainsHz).setting
    }

    /// "1/48 · ISO 320", for the viewfinder.
    public static func readout(_ setting: Setting) -> String {
        let denominator = Int((1 / setting.duration).rounded())
        return "1/\(denominator) · ISO \(Int(setting.iso.rounded()))"
    }
}
