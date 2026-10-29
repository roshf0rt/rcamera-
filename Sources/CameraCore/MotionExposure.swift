import Foundation

/// Auto exposure for video that keeps motion cinematic, after Kino's AutoMotion: the camera's metering says
/// how bright the picture should be, and the loop makes that brightness with the shutter on 180°
/// (`CineExposure.referenceShutter`) and ISO doing the work, moving a fifth of the way per step so the
/// picture ramps instead of jumping.
///
/// When ISO alone cannot reach the brightness, the shutter gives up to one stop (faster in bright light,
/// slower in the dark, never longer than a frame). Past that, for `patience` steps in a row, the light is
/// out of reach of 180° and the iPhone's own auto exposure takes over, until the light has been back within
/// 0.7 stops for as long. The wait keeps a brief flash or a noisy meter from throwing the camera between
/// the two every frame.
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
        /// Out of reach of 180°; the camera's own auto exposure runs.
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
        strikes: Int = 0
    ) -> Decision {
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

    /// Shutter and ISO for `exposure`: 180° when ISO can carry it, otherwise the shutter bends.
    private static func place(exposure: Double, reference: Double, longest: Double, limits: CineExposure.Limits, offset: Double) -> Decision {
        let iso = exposure / reference
        if iso >= limits.minISO, iso <= limits.maxISO {
            // The shutter is already on 180°; the status goes green once the picture has ramped near its target.
            let status: Status = abs(offset) < 0.5 ? .cinematic : .settling
            return Decision(mode: .motion, setting: .init(iso: iso, duration: reference), status: status)
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
}
