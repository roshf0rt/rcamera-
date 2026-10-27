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

    /// Photo stops are labelled as zoom factors relative to the wide lens: 0.5, 1, 1.5, 4.
    public static func photoStops(focalLengths: [LensID: Double]) -> [ZoomStop] {
        let reference = focalLengths[.wide] ?? defaultFocalLengths[.wide]!
        var stops: [ZoomStop] = []
        if let ultraWide = focalLengths[.ultraWide] {
            stops.append(ZoomStop(lens: .ultraWide, label: formatFactor(ultraWide / reference)))
        }
        stops.append(ZoomStop(lens: .wide, label: "1"))
        stops.append(ZoomStop(lens: .wide, digitalZoom: 1.5, label: "1.5"))
        if let telephoto = focalLengths[.telephoto] {
            stops.append(ZoomStop(lens: .telephoto, label: formatFactor(telephoto / reference)))
        } else {
            stops.append(ZoomStop(lens: .wide, digitalZoom: 2.0, label: "2"))
        }
        return stops
    }

    /// Video stops are labelled with the 35 mm equivalent focal length: 13, 24, 100.
    public static func videoStops(focalLengths: [LensID: Double]) -> [ZoomStop] {
        [LensID.ultraWide, .wide, .telephoto].compactMap { lens in
            guard let focal = focalLengths[lens] else { return nil }
            return ZoomStop(lens: lens, label: String(Int(focal.rounded())))
        }
    }

    static func formatFactor(_ factor: Double) -> String {
        let rounded = factor < 2 ? (factor * 10).rounded() / 10 : factor.rounded()
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
