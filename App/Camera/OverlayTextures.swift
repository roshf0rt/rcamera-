import CameraCore
import Metal
import MetalKit

/// The bundled overlay pictures (App/Resources/Overlays/<Category>/<file>) and their GPU textures.
/// Textures load on first use and stay cached; pixel values are kept as stored (no sRGB decode),
/// because the grade works on display-encoded values.
enum OverlayTextures {
    static var root: URL? { Bundle.main.url(forResource: "Overlays", withExtension: nil) }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// Categories in a fixed order, each with its files sorted by name, for the editor's picker.
    static let catalog: [(category: String, files: [String])] = {
        let fm = FileManager.default
        guard let root, let categories = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        let order = ["Grain", "Light", "Dust", "Masks", "Extras"]
        return categories
            .sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
            .compactMap { category in
                let files = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(category).path)) ?? [])
                    .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                return files.isEmpty ? nil : (category, files.map { "\(category)/\($0)" })
            }
    }()

    static func url(for file: String) -> URL? { root?.appendingPathComponent(file) }

    private static let lock = NSLock()
    private static var cache: [String: MTLTexture] = [:]
    private static var order: [String] = []

    /// The texture for `file`, loaded once. A dozen are kept; the oldest goes first.
    static func texture(for file: String, device: MTLDevice) -> MTLTexture? {
        lock.lock()
        if let hit = cache[file] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        guard let url = url(for: file) else { return nil }
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .generateMipmaps: false,
        ]
        guard let texture = try? loader.newTexture(URL: url, options: options) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        cache[file] = texture
        order.removeAll { $0 == file }
        order.append(file)
        while order.count > 12 { cache[order.removeFirst()] = nil }
        return texture
    }
}
