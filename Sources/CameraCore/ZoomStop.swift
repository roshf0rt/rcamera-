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
