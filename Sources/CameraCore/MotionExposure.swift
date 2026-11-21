import Foundation

/// Auto exposure for video that keeps motion cinematic, after Kino's AutoMotion: the camera's metering says
/// how bright the picture should be, and the loop makes that brightness with the shutter on 180°
/// (`CineExposure.referenceShutter`) and ISO doing the work, moving a fifth of the way per step so the
/// picture ramps instead of jumping.
///
/// The ISO is kept comfortable first (`comfortISO`): in dim light the shutter slows up to a stop past 180° before
/// the ISO climbs. When ISO alone cannot reach the brightness at all, the shutter gives up to one stop (faster in
/// bright light, slower in the dark, never longer than a frame). Past that, for `patience` steps in a row, the light is
/// out of reach of 180° and the iPhone's own auto exposure takes over, until the light has been back within
/// 0.7 stops for as long. The wait keeps a brief flash or a noisy meter from throwing the camera between
/// the two every frame.
///
/// RWater runs the loop with `Policy.holdShutter` instead: the shutter stays on 180° and only the ISO moves,
/// the iPhone's own exposure never takes over, and Apple Log can be exposed to the right (`bias`).
///
/// The meter is the camera's: `AVCaptureDevice.exposureTargetOffset`, which in custom exposure still says
/// how far the picture is from the camera's target, with the EV bias added.
public enum MotionExposure {
    /// How the loop splits the light between shutter and ISO.
    public enum Policy: Equatable, Sendable {
        /// RCamera: a comfortable ISO first, the shutter bends up to a stop, the camera takes over out of reach.
        case classic
        /// RWater: the shutter holds 180° and the ISO does all the work; the shutter leaves 180° only past the
        /// ends of the ISO range, on the same ramp, and the camera never takes over.
        case holdShutter
    }
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
        /// Out of reach of 180°; the camera's own auto exposure runs.
        /// With `Policy.holdShutter` the loop keeps running and this says the light is past what the shutter and
        /// ISO can make by more than `outOfReach` stops.
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
        /// Steps in a row the light has stood past the threshold for switching mode; pass it to the next step.
        public var strikes = 0
    }

    /// Steps in a row past a threshold before the mode switches.
    public static let patience = 6

    /// Stops past the ISO range at which the loop hands over to the camera.
    public static let handOver = 1.0
    /// Stops past the ISO range below which it takes exposure back.
    public static let takeBack = 0.7
    /// Share of the metering error corrected per step.
    public static let rate = 0.2
    /// Errors smaller than this, in stops, are left alone, so the picture does not pump.
    public static let deadband = 0.1

    /// How many stops beyond the ISO range the exposure `exposure` (ISO × seconds) lies at the shutter
    /// `reference`; zero when ISO alone can make it.
    public static func shortfall(exposure: Double, reference: Double, limits: CineExposure.Limits) -> (stops: Double, tooBright: Bool) {
        let iso = exposure / reference
        if iso < limits.minISO { return (log2(limits.minISO / iso), true) }
        if iso > limits.maxISO { return (log2(iso / limits.maxISO), false) }
        return (0, false)
    }

    /// One step. `current` is what the camera runs now, `offset` how far the metered picture is above the
    /// target in stops (positive: too bright), as `AVCaptureDevice.exposureTargetOffset` reports it.
    /// `strikes` is the last decision's.
    public static func step(
        mode: Mode,
        current: CineExposure.Setting,
        offset: Double,
        fps: Int,
        limits: CineExposure.Limits,
        mainsHz: Int? = nil,
        strikes: Int = 0,
        policy: Policy = .classic,
        bias: Double = 0
    ) -> Decision {
        if policy == .holdShutter {
            return holdStep(mode: mode, current: current, offset: offset, fps: fps, limits: limits, mainsHz: mainsHz, bias: bias)
        }
        let longest = min(limits.maxDuration, 1 / Double(max(fps, 1)))
        let reference = min(max(CineExposure.referenceShutter(fps: fps, mainsHz: mainsHz), limits.minDuration), longest)
        let wanted = current.iso * current.duration * pow(2, -offset)
        let gap = shortfall(exposure: wanted, reference: reference, limits: limits)

        switch mode {
        case .native:
            guard gap.stops <= takeBack else {
                return Decision(mode: .native, setting: nil, status: .handedOver(tooBright: gap.tooBright))
            }
            guard strikes + 1 >= patience else {
                // Within reach, not for long enough yet: amber while the camera still runs.
                return Decision(mode: .native, setting: nil, status: .settling, strikes: strikes + 1)
            }
            // The camera was exposing right, so the loop starts from its brightness at once.
            return place(exposure: wanted, reference: reference, longest: longest, limits: limits, offset: 0)
        case .motion:
            var outOfReach = 0
            if gap.stops > handOver {
                outOfReach = strikes + 1
                if outOfReach >= patience {
                    return Decision(mode: .native, setting: nil, status: .handedOver(tooBright: gap.tooBright))
                }
            }
            let correction = abs(offset) < deadband ? 0 : -offset * rate
            let exposure = current.iso * current.duration * pow(2, correction)
            var decision = place(exposure: exposure, reference: reference, longest: longest, limits: limits, offset: offset)
            decision.strikes = outOfReach
            return decision
        }
    }

    /// The ISO the loop would rather not pass: 25 times the camera's lowest (about ISO 800 on a main camera, where
    /// pictures are still clean). Past it the shutter lengthens before the ISO climbs any further.
    public static func comfortISO(limits: CineExposure.Limits) -> Double {
        min(limits.maxISO, max(limits.minISO * 25, 640))
    }

    /// Shutter and ISO for `exposure`: 180° while the ISO stays comfortable; in dimmer light the shutter slows
    /// (at most a stop past 180°, never longer than a frame) to keep the ISO down; at the ends of the ISO range
    /// the shutter bends the other way as well.
    private static func place(exposure: Double, reference: Double, longest: Double, limits: CineExposure.Limits, offset: Double) -> Decision {
        let iso = exposure / reference
        let comfort = comfortISO(limits: limits)
        if iso >= limits.minISO, iso <= comfort {
            // The shutter is already on 180°; the status goes green once the picture has ramped near its target.
            let status: Status = abs(offset) < 0.5 ? .cinematic : .settling
            return Decision(mode: .motion, setting: .init(iso: iso, duration: reference), status: status)
        }
        if iso > comfort {
            let slowest = min(longest, reference * 2)
            let duration = min(slowest, exposure / comfort)
            let finalISO = exposure / duration
            if finalISO <= limits.maxISO {
                let status: Status = duration > reference * 1.02 ? .bent(stops: log2(reference / duration)) : (abs(offset) < 0.5 ? .cinematic : .settling)
                return Decision(mode: .motion, setting: .init(iso: finalISO, duration: duration), status: status)
            }
        }
        let edgeISO = iso < limits.minISO ? limits.minISO : limits.maxISO
        let duration = min(max(exposure / edgeISO, limits.minDuration), longest)
        let finalISO = min(max(exposure / duration, limits.minISO), limits.maxISO)
        return Decision(
            mode: .motion,
            setting: .init(iso: finalISO, duration: duration),
            status: .bent(stops: log2(reference / duration))
        )
    }
    // MARK: Holding the shutter (RWater)

    /// The most the exposure moves in one step with `Policy.holdShutter`, in stops, so a sudden change of light glides.
    public static let maxStep = 0.25
    /// Stops past the ends of ISO and shutter at which `Policy.holdShutter` says the light is out of reach.
    public static let outOfReach = 1.0

    /// One step with the shutter held on 180°. `bias` moves the target: +0.7 exposes 0.7 stops brighter than
    /// the camera would (ETTR for Log).
    static func holdStep(mode: Mode, current: CineExposure.Setting, offset: Double, fps: Int, limits: CineExposure.Limits, mainsHz: Int?, bias: Double) -> Decision {
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

/// Catches a loop that runs on a meter read the wrong way. Such a loop drives the picture to black while the meter
/// says it is far too bright (or to white while it says far too dark). A scene that is really dark reads dark on
/// the meter and in the picture alike and is never touched, nor is any change of light: only the meter and the
/// picture contradicting each other for `stuckSteps` steps in a row counts.
public struct MeterWatch: Equatable, Sendable {
    /// Steps in a row the contradiction must last (about half a second).
    public static let stuckSteps = 5
    /// The meter reading, in stops, that counts as far off.
    public static let pinned = 3.0
    /// A picture darker than this (mean, 0…1) cannot be "far too bright"; one brighter than `white` not "far too dark".
    public static let black = 0.25
    public static let white = 0.75

    private var stuck = 0

    public init() {}

    /// `offset` is the meter as the loop reads it (positive: too bright); `pictureLuma` the picture's mean
    /// brightness, nil when unknown (then nothing is judged). True when the meter should be tested again.
    public mutating func check(offset: Double, pictureLuma: Double?) -> Bool {
        let contradicts: Bool
        if let luma = pictureLuma {
            contradicts = (offset >= Self.pinned && luma < Self.black) || (offset <= -Self.pinned && luma > Self.white)
        } else {
            contradicts = false
        }
        stuck = contradicts ? stuck + 1 : 0
        guard stuck >= Self.stuckSteps else { return false }
        stuck = 0
        return true
    }

    public mutating func reset() {
        stuck = 0
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
