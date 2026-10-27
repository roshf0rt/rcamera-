import Foundation

/// The f-numbers the portrait blur can be set to, from the camera screen's aperture strip.
public enum PortraitAperture {
    public static let stops: [Double] = [1.4, 2.8, 4.0, 5.6, 8, 16]
    public static let standard: Double = 4.0

    /// The stop nearest to `value`, so a stored value that no longer matches a stop still lands on one.
    public static func nearest(to value: Double) -> Double {
        stops.min { abs($0 - value) < abs($1 - value) } ?? standard
    }
}
