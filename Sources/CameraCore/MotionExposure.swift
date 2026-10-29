import Foundation

/// Auto exposure for video that keeps motion cinematic, after Kino's AutoMotion: the camera's metering says
/// how bright the picture should be, and the loop makes that brightness with the shutter on 180°
/// (`CineExposure.referenceShutter`) and ISO doing the work, moving a fifth of the way per step so the
/// picture ramps instead of jumping.
///
/// When ISO alone cannot reach the brightness, the shutter gives up to one stop (faster in bright light,
/// slower in the dark, never longer than a frame). Past that the light is out of reach of 180°, and the
/// iPhone's own auto exposure takes over until the light comes back within 0.7 stops.
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
    }

    public struct Decision: Equatable, Sendable {
        public var mode: Mode
        /// Shutter and ISO to set. Nil hands exposure to the camera.
        public var setting: CineExposure.Setting?
        public var status: Status
    }

    /// The brightness the loop meters towards: a mid grey in the picture as the camera shows it.
    public static let targetLevel = 0.44

    /// Stops the mean display level lies above (positive) or below (negative) `target`, on a gamma of 2.2.
    public static func stops(displayLevel: Double, target: Double = targetLevel) -> Double {
        log2(pow(max(displayLevel, 0.001), 2.2) / pow(max(target, 0.001), 2.2))
    }

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
    public static func step(
        mode: Mode,
        current: CineExposure.Setting,
        offset: Double,
        fps: Int,
        limits: CineExposure.Limits,
        mainsHz: Int? = nil
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
            // The camera was exposing right, so the loop starts from its brightness at once.
            return place(exposure: wanted, reference: reference, longest: longest, limits: limits, offset: offset)
        case .motion:
            if gap.stops > handOver {
                return Decision(mode: .native, setting: nil, status: .handedOver(tooBright: gap.tooBright))
            }
            let correction = abs(offset) < deadband ? 0 : -offset * rate
            let exposure = current.iso * current.duration * pow(2, correction)
            return place(exposure: exposure, reference: reference, longest: longest, limits: limits, offset: offset)
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
