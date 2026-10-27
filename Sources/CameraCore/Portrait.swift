import Foundation

/// The f-numbers the portrait blur can be set to, from the camera screen's aperture strip.
public enum PortraitAperture {
    public static let stops: [Double] = [1.4, 1.8, 2.2, 2.8, 4.0, 5.6, 8, 11, 16]
    public static let standard: Double = 4.0

    /// How strong the portrait blur is at an f-number: 1 at f/2.8, 2 at f/1.4, about 0.17 at f/16.
    public static func blurStrength(fNumber: Double) -> Double {
        2.8 / max(fNumber, 0.7)
    }

    /// The stop nearest to `value`, so a stored value that no longer matches a stop still lands on one.
    public static func nearest(to value: Double) -> Double {
        stops.min { abs($0 - value) < abs($1 - value) } ?? standard
    }
}
