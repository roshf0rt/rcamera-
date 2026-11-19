import Foundation

/// A bundled texture (App/Resources/Overlays/<Category>/<file>) blended over the graded picture:
/// grain scans, light leaks, dust, vignette masks. Rendered by `MetalGrader` after grain and halation,
/// on the viewfinder, video and photos alike.
public struct PresetOverlay: Equatable, Hashable, Codable, Sendable {
    public enum Blend: String, CaseIterable, Codable, Sendable {
        case normal, screen, multiply, overlay, softLight, add

        public var title: String {
            switch self {
            case .normal: "Normal"
            case .screen: "Screen"
            case .multiply: "Multiply"
            case .overlay: "Overlay"
            case .softLight: "Soft light"
            case .add: "Add"
            }
        }

        /// The number the shader switches on (`overlayBlend` in Grade.metal). 0 means no layer.
        public var shaderCode: Int32 {
            switch self {
            case .normal: 1
            case .screen: 2
            case .multiply: 3
            case .overlay: 4
            case .softLight: 5
            case .add: 6
            }
        }
    }

    /// How many layers a preset can carry; the shader has this many texture slots.
    public static let maxLayers = 3

    /// "Category/file.ext" inside the bundled Overlays folder.
    public var file: String
    public var blend: Blend
    /// 0...1
    public var opacity: Double
    /// Repeat at a fixed texel size (and move every frame, like grain) instead of stretching over the frame.
    public var tile: Bool

    public init(file: String, blend: Blend? = nil, opacity: Double = 1, tile: Bool? = nil) {
        self.file = file
        self.blend = blend ?? Self.defaultBlend(for: file)
        self.opacity = min(max(opacity, 0), 1)
        self.tile = tile ?? (Self.category(of: file) == "Grain")
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        blend = (try? c.decode(Blend.self, forKey: .blend)) ?? Self.defaultBlend(for: file)
        opacity = min(max((try? c.decode(Double.self, forKey: .opacity)) ?? 1, 0), 1)
        tile = (try? c.decode(Bool.self, forKey: .tile)) ?? (Self.category(of: file) == "Grain")
    }

    public static func category(of file: String) -> String {
        file.split(separator: "/").first.map(String.init) ?? ""
    }

    /// File name without folder and extension, for labels.
    public var title: String {
        let last = file.split(separator: "/").last.map(String.init) ?? file
        return last.split(separator: ".").dropLast().joined(separator: ".")
    }

    /// Starting blend for each kind of texture: grain scans overlay, light leaks screen (dark ones multiply),
    /// masks multiply, transparent PNGs sit on top as they are.
    public static func defaultBlend(for file: String) -> Blend {
        let lower = file.lowercased()
        let png = lower.hasSuffix(".png")
        let name = lower.split(separator: "/").last.map(String.init) ?? lower
        switch category(of: file) {
        case "Grain": return .overlay
        case "Light": return name.hasPrefix("dark") ? .multiply : .screen
        case "Masks": return png ? .normal : .multiply
        case "Dust": return png ? .normal : .screen
        default: return png ? .normal : .screen
        }
    }
}
