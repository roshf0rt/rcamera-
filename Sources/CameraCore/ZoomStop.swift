import Foundation

/// One selectable zoom position: which lens to use and how much digital zoom on top of it.
public struct ZoomStop: Equatable, Hashable, Sendable, Identifiable {
    public var lens: LensID
    public var digitalZoom: Double
    public var label: String

    public var id: String { "\(lens)-\(digitalZoom)" }

    public init(lens: LensID, digitalZoom: Double = 1.0, label: String) {
        self.lens = lens
        self.digitalZoom = digitalZoom
        self.label = label
    }

    /// 35 mm equivalent focal lengths used when the device cannot report its own.
    public static let defaultFocalLengths: [LensID: Double] = [
        .ultraWide: 13,
        .wide: 24,
        .telephoto: 100,
    ]

    /// Common 35 mm equivalent focal lengths, so detected values read as 13 / 24 / 100 rather than 14 / 24 / 104.
    static let standardTelephoto: [Double] = [48, 65, 77, 85, 100, 120]

    /// Rounds each detected lens to the nearest standard focal length.
    public static func normalized(_ focalLengths: [LensID: Double]) -> [LensID: Double] {
        func nearest(_ value: Double, in options: [Double]) -> Double {
            options.min { abs($0 - value) < abs($1 - value) } ?? value
        }
        var result = focalLengths
        if let value = focalLengths[.ultraWide] { result[.ultraWide] = value < 16 ? 13 : value.rounded() }
        if let value = focalLengths[.telephoto] { result[.telephoto] = nearest(value, in: standardTelephoto) }
        if focalLengths[.wide] != nil { result[.wide] = 24 }
        return result
    }

    /// Photo stops are labelled as zoom factors relative to the wide lens: 0.5, 1, 4.
    /// Only lenses the phone has appear. `digital` adds one optional crop stop (1.5 or 2).
    public static func photoStops(focalLengths: [LensID: Double], digital: DigitalZoomStop = .none) -> [ZoomStop] {
        let focals = normalized(focalLengths)
        let reference = focals[.wide] ?? defaultFocalLengths[.wide]!
        var stops: [ZoomStop] = []
        if let ultraWide = focals[.ultraWide] {
            stops.append(ZoomStop(lens: .ultraWide, label: formatFactor(ultraWide / reference)))
        }
        stops.append(ZoomStop(lens: .wide, label: "1"))
        if let factor = digital.factor {
            let realLensNearby = [LensID.ultraWide, .telephoto].contains { lens in
                focals[lens].map { abs($0 / reference - factor) < 0.3 } ?? false
            }
            if !realLensNearby {
                stops.append(ZoomStop(lens: .wide, digitalZoom: factor, label: formatFactor(factor)))
            }
        }
        if let telephoto = focals[.telephoto] {
            stops.append(ZoomStop(lens: .telephoto, label: formatFactor(telephoto / reference)))
        }
        return stops.sorted { zoomFactor($0, reference: reference, focals: focals) < zoomFactor($1, reference: reference, focals: focals) }
    }

    private static func zoomFactor(_ stop: ZoomStop, reference: Double, focals: [LensID: Double]) -> Double {
        (focals[stop.lens] ?? reference) / reference * stop.digitalZoom
    }

    /// The zoom this stop gives, in the units the chips are labelled in: the wide lens is 1, the ultra wide
    /// about 0.5, a telephoto its focal length over the wide one, digital zoom multiplies on top.
    public func factor(focalLengths: [LensID: Double]) -> Double {
        let focals = Self.normalized(focalLengths)
        let reference = focals[.wide] ?? Self.defaultFocalLengths[.wide]!
        return Self.zoomFactor(self, reference: reference, focals: focals)
    }

    /// Where a zoom sits among the chips. Within 0.05 of a stop it is on that stop; between stops it is on the
    /// stop just below, and `live` carries the value that chip shows (one decimal, as the zoom goes past it).
    public struct Reading: Equatable, Sendable {
        public var stop: ZoomStop?
        public var live: Double?

        public init(stop: ZoomStop?, live: Double?) {
            self.stop = stop
            self.live = live
        }
    }

    public static func reading(zoom: Double, stops: [ZoomStop], focalLengths: [LensID: Double]) -> Reading {
        let below = stops
            .map { (stop: $0, value: $0.factor(focalLengths: focalLengths)) }
            .filter { $0.value <= zoom + 0.05 }
            .max { $0.value < $1.value }
        guard let below else { return Reading(stop: nil, live: zoom) }
        return Reading(stop: below.stop, live: abs(zoom - below.value) < 0.05 ? nil : zoom)
    }

    /// Video stops are labelled with the 35 mm equivalent focal length: 13, 24, 100.
    public static func videoStops(focalLengths: [LensID: Double]) -> [ZoomStop] {
        let focals = normalized(focalLengths)
        return [LensID.ultraWide, .wide, .telephoto].compactMap { lens in
            guard let focal = focals[lens] else { return nil }
            return ZoomStop(lens: lens, label: String(Int(focal.rounded())))
        }
    }

    static func formatFactor(_ factor: Double) -> String {
        let rounded = factor < 2 ? (factor * 10).rounded() / 10 : factor.rounded()
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
