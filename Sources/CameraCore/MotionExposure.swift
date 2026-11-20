import Foundation

/// Auto exposure for video that keeps motion cinematic, after Kino's AutoMotion: the camera's metering says
/// how bright the picture should be, and the loop makes that brightness with the shutter held on 180°
/// (`CineExposure.referenceShutter`) and only the ISO moving, a fifth of the way per step (at most
/// `maxStep` stops), so the picture ramps instead of jumping and the motion blur never changes.
///
/// The shutter leaves 180° only where the ISO has run out: in light too bright for the lowest ISO it gets
/// faster (as an ND filter would be needed), in the dark past the highest ISO it slows, never longer than a
/// frame. Both follow the same ramp, so even then it glides. The iPhone's own auto exposure never takes over
/// while the loop runs: it would move the shutter freely.
///
/// For Apple Log the target sits `bias` stops to the right of the camera's (ETTR): less noise in the shadows,
/// which the grade pulls down again. `HighlightGuard` takes the bias back when highlights start to clip.
///
/// The meter is the camera's: `AVCaptureDevice.exposureTargetOffset`, which in custom exposure still says
/// how far the picture is from the camera's target, with the EV bias added.
public enum MotionExposure {
    public enum Mode: Equatable, Sendable {
        /// The loop sets shutter and ISO.
        case motion
        /// The camera's own auto exposure runs.
        case native
    }

    /// How the picture stands, for the light on the viewfinder.
    public enum Status: Equatable, Sendable {
        /// On the 180° shutter and exposed right: green.
        case cinematic
        /// On the 180° shutter, still ramping to the target: amber.
        case settling
        /// The shutter had to leave 180° by `stops`: positive faster (too much light), negative slower.
        case bent(stops: Double)
        /// Past what the shutter and ISO can make by more than `outOfReach` stops: too bright even at the fastest
        /// shutter, or too dark at the highest ISO and a frame-long shutter. The loop keeps running.
        case handedOver(tooBright: Bool)
        /// The camera's meter did not answer a test change in exposure; its own auto exposure runs.
        case noMeter
    }

    /// Which way the camera's meter reads, found out on the device itself: the loop makes the picture a little
    /// brighter (or darker), waits for the meter, and sees which way `exposureTargetOffset` moved. The sign of
    /// the offset is then no guess, and a meter that does not move is caught instead of steered by.
    public enum Meter {
        /// Stops of exposure the test changes the picture by.
        public static let probeStops = 0.6
        /// Loop steps to wait after the change before reading the meter.
        public static let settleSteps = 4

        /// +1 when a brighter picture reads as a higher offset, -1 when it reads lower, 0 when the meter hardly moved.
        public static func sign(before: Double, after: Double, stops: Double) -> Double {
            guard stops != 0 else { return 0 }
            let moved = (after - before) / stops
            if moved > 0.3 { return 1 }
            if moved < -0.3 { return -1 }
            return 0
        }

        /// The test change from `current`: brighter when the ISO range has room above, otherwise darker, with
        /// the shutter untouched. Nil when the range has no room either way.
        public static func probe(current: CineExposure.Setting, limits: CineExposure.Limits) -> (setting: CineExposure.Setting, stops: Double)? {
            let up = current.iso * pow(2, probeStops)
            if up <= limits.maxISO { return (.init(iso: up, duration: current.duration), probeStops) }
            let down = current.iso * pow(2, -probeStops)
            if down >= limits.minISO { return (.init(iso: down, duration: current.duration), -probeStops) }
            return nil
        }
    }

    public struct Decision: Equatable, Sendable {
        public var mode: Mode
        /// Shutter and ISO to set. Nil hands exposure to the camera.
        public var setting: CineExposure.Setting?
        public var status: Status
        /// Kept for callers that pass it back; the loop no longer counts steps before switching.
        public var strikes = 0
    }

    /// Kept for callers: the loop takes over on its first step.
    public static let patience = 1
    /// Share of the metering error corrected per step.
    public static let rate = 0.2
    /// The most the exposure moves in one step, in stops, so a sudden change of light glides.
    public static let maxStep = 0.25
    /// Errors smaller than this, in stops, are left alone, so the picture does not pump.
    public static let deadband = 0.1
    /// Stops of headroom past the ISO range at which the status says the light is out of reach.
    public static let outOfReach = 1.0

    /// How many stops beyond the ISO range the exposure `exposure` (ISO × seconds) lies at the shutter
    /// `reference`; zero when ISO alone can make it.
    public static func shortfall(exposure: Double, reference: Double, limits: CineExposure.Limits) -> (stops: Double, tooBright: Bool) {
        let iso = exposure / reference
        if iso < limits.minISO { return (log2(limits.minISO / iso), true) }
        if iso > limits.maxISO { return (log2(iso / limits.maxISO), false) }
        return (0, false)
    }

    /// One step. `current` is what the camera runs now, `offset` how far the metered picture is above the
    /// camera's target in stops (positive: too bright), as `AVCaptureDevice.exposureTargetOffset` reports it.
    /// `bias` moves the target: +0.7 exposes 0.7 stops brighter than the camera would (ETTR for Log).
    public static func step(
        mode: Mode,
        current: CineExposure.Setting,
        offset: Double,
        fps: Int,
        limits: CineExposure.Limits,
        mainsHz: Int? = nil,
        strikes: Int = 0,
        bias: Double = 0
    ) -> Decision {
        let longest = min(limits.maxDuration, 1 / Double(max(fps, 1)))
        let reference = min(max(CineExposure.referenceShutter(fps: fps, mainsHz: mainsHz), limits.minDuration), longest)
        let error = offset - bias
        let exposure: Double
        switch mode {
        case .native:
            // The camera was exposing right, so the loop starts from its brightness at once and ramps to the bias.
            exposure = current.iso * current.duration * pow(2, -offset)
        case .motion:
            let correction = abs(error) < deadband ? 0 : min(max(-error * rate, -maxStep), maxStep)
            exposure = current.iso * current.duration * pow(2, correction)
        }
        return place(exposure: exposure, reference: reference, longest: longest, limits: limits, error: mode == .native ? offset - bias : error)
    }

    /// Kept for the readout: the ISO the old loop would rather not pass. The shutter no longer slows for it.
    public static func comfortISO(limits: CineExposure.Limits) -> Double {
        min(limits.maxISO, max(limits.minISO * 25, 640))
    }

    /// Shutter and ISO for `exposure`: 180° with the ISO doing the work; only past the ends of the ISO range
    /// the shutter takes the rest, faster in bright light, slower in the dark up to a frame.
    private static func place(exposure: Double, reference: Double, longest: Double, limits: CineExposure.Limits, error: Double) -> Decision {
        let iso = exposure / reference
        if iso >= limits.minISO, iso <= limits.maxISO {
            let status: Status = abs(error) < 0.5 ? .cinematic : .settling
            return Decision(mode: .motion, setting: .init(iso: iso, duration: reference), status: status)
        }
        let edgeISO = iso < limits.minISO ? limits.minISO : limits.maxISO
        let duration = min(max(exposure / edgeISO, limits.minDuration), longest)
        let finalISO = min(max(exposure / duration, limits.minISO), limits.maxISO)
        // At the end of both the ISO and the shutter, an error past `outOfReach` is light the camera cannot make.
        let atEnd = iso < limits.minISO ? duration <= limits.minDuration * 1.001 : duration >= longest * 0.999
        let status: Status = atEnd && abs(error) > outOfReach
            ? .handedOver(tooBright: iso < limits.minISO)
            : .bent(stops: log2(reference / duration))
        return Decision(mode: .motion, setting: .init(iso: finalISO, duration: duration), status: status)
    }
}

/// How far to the right Apple Log is exposed (ETTR), taken back while highlights clip.
///
/// Fed a few times a second with the share of the picture piled up at the top of the Log signal
/// (`HighlightMeter.clippedShare`): above `clipLimit` the bias drops quickly, below `clearLimit` it creeps back
/// to the target, in between it stays. It may go under zero, so a bright sky is held even at the cost of shadows.
public struct HighlightGuard: Equatable, Sendable {
    /// Share of clipped pixels that starts taking the bias back.
    public static let clipLimit = 0.01
    /// Under this share the bias returns to the target.
    public static let clearLimit = 0.003
    public static let dropPerUpdate = 0.15
    public static let risePerUpdate = 0.03
    /// The lowest the bias goes, in stops.
    public static let floor = -1.0

    public private(set) var bias: Double

    public init(bias: Double = 0) {
        self.bias = bias
    }

    /// The bias to use now, for a wanted `target` and the latest `clippedShare` (nil: nothing measured).
    @discardableResult
    public mutating func update(target: Double, clippedShare: Double?) -> Double {
        guard let share = clippedShare else {
            bias = target
            return bias
        }
        if share > Self.clipLimit {
            bias = max(Self.floor, min(bias, target) - Self.dropPerUpdate)
        } else if share < Self.clearLimit {
            bias = min(target, bias + Self.risePerUpdate)
        } else {
            bias = min(bias, target)
        }
        return bias
    }
}

/// Finds clipping in a Log picture: a clipped sensor piles its brightest pixels up at one code value, near the top
/// of the signal, where an unclipped highlight spreads out.
public enum HighlightMeter {
    /// Levels under this (0...1 of the signal) are never taken for clipping: Apple Log reaches the sensor's
    /// limit around 0.85–0.95.
    public static let floor = 0.75
    /// How close to the brightest level a pixel counts as piled up.
    public static let width = 0.006

    /// Share of `levels` (0...1) at the brightest level, when that level is high enough to be the clip point.
    public static func clippedShare(levels: [Double]) -> Double {
        guard let peak = levels.max(), peak >= floor else { return 0 }
        let piled = levels.reduce(0) { $0 + ($1 >= peak - width ? 1 : 0) }
        return Double(piled) / Double(levels.count)
    }

    /// The level of a 10-bit video-range luma code (64...940), 0...1.
    public static func level(videoRangeCode code: Int) -> Double {
        min(max(Double(code - 64) / 876, 0), 1)
    }
}
