import Foundation

/// The film looks bundled as `App/Resources/LUTs/film-<key>.lut` (33^3), one built-in preset each, shown after
/// the classic presets. Generated from the bundled files: the icon is `App/Resources/FilterIcons/<icon>` and
/// a look whose name matches a `grain_<name>` or `vignette_<name>` texture starts with it as an overlay.
public enum FilmCollection {
    public static let idPrefix = "film-"

    public struct Entry: Sendable {
        public let key: String
        public let name: String
        public let icon: String?
        public let overlays: [PresetOverlay]

        public var id: String { FilmCollection.idPrefix + key }
    }

    public static func isFilm(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    public static func entry(id: String) -> Entry? { entries.first { $0.id == id } }

    public static var ids: [String] { entries.map(\.id) }

    /// Film grain each look starts with: none when a grain scan is attached, a little otherwise.
    static func grain(for entry: Entry) -> Double {
        entry.overlays.contains { PresetOverlay.category(of: $0.file) == "Grain" } ? 0 : 0.3
    }

    static let halation = 0.3

    public static let entries: [Entry] = [
        Entry(key: "dslide", name: "DSLIDE", icon: nil, overlays: []),
        Entry(key: "f_blue", name: "F BLUE", icon: nil, overlays: []),
        Entry(key: "f_green", name: "F GREEN", icon: nil, overlays: []),
        Entry(key: "f_red", name: "F RED", icon: nil, overlays: []),
        Entry(key: "f_yellow", name: "F YELLOW", icon: nil, overlays: []),
        Entry(key: "half_black", name: "HALF BLACK", icon: nil, overlays: []),
        Entry(key: "half_color", name: "HALF COLOR", icon: nil, overlays: []),
        Entry(key: "half_colorf", name: "HALF COLORF", icon: nil, overlays: []),
        Entry(key: "07FF", name: "07FF", icon: "icon_filter_07FF.png", overlays: []),
        Entry(key: "120_1", name: "120 1", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_120.jpg", opacity: 0.5)]),
        Entry(key: "120_2", name: "120 2", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_120.jpg", opacity: 0.5)]),
        Entry(key: "120_3", name: "120 3", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_120.jpg", opacity: 0.5)]),
        Entry(key: "135sr", name: "135SR", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_135sr.jpg", opacity: 0.5)]),
        Entry(key: "16mm", name: "16MM", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_16mm.jpg", opacity: 0.5)]),
        Entry(key: "19M", name: "19M", icon: "icon_filter_19M.png", overlays: []),
        Entry(key: "19P", name: "19P", icon: "icon_filter_19P.png", overlays: []),
        Entry(key: "19P2", name: "19P2", icon: "icon_filter_19P2.png", overlays: []),
        Entry(key: "22M", name: "22M", icon: "icon_filter_22M.png", overlays: []),
        Entry(key: "8mm", name: "8MM", icon: nil, overlays: []),
        Entry(key: "8mm_2", name: "8MM 2", icon: nil, overlays: []),
        Entry(key: "IR01", name: "IR01", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_IR.jpg", opacity: 0.5)]),
        Entry(key: "IR02", name: "IR02", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_IR.jpg", opacity: 0.5)]),
        Entry(key: "c400", name: "C400", icon: nil, overlays: []),
        Entry(key: "ccdr", name: "CCDR", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_ccdr.jpg", opacity: 0.5)]),
        Entry(key: "classic", name: "CLASSIC", icon: nil, overlays: []),
        Entry(key: "classicu", name: "CLASSICU", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_classicu.jpg", opacity: 0.5)]),
        Entry(key: "collage", name: "COLLAGE", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_collage.jpg", opacity: 0.5)]),
        Entry(key: "cpm35", name: "CPM35", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_cpm35.jpg", opacity: 0.5), PresetOverlay(file: "Masks/vignette_cpm35.jpg", opacity: 0.8)]),
        Entry(key: "ct2f", name: "CT2F", icon: nil, overlays: [PresetOverlay(file: "Masks/vignette_ct2f.jpg", opacity: 0.8)]),
        Entry(key: "d", name: "D", icon: nil, overlays: []),
        Entry(key: "d3d", name: "D3D", icon: nil, overlays: []),
        Entry(key: "d3d2", name: "D3D2", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_d3d2.jpg", opacity: 0.5)]),
        Entry(key: "dblack_1", name: "DBLACK 1", icon: nil, overlays: []),
        Entry(key: "dblack_2", name: "DBLACK 2", icon: nil, overlays: []),
        Entry(key: "dcr", name: "DCR", icon: nil, overlays: []),
        Entry(key: "dexp", name: "DEXP", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_dexp.jpg", opacity: 0.5), PresetOverlay(file: "Masks/vignette_dexp.jpg", opacity: 0.8)]),
        Entry(key: "dexp3", name: "DEXP3", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_dexp.jpg", opacity: 0.5), PresetOverlay(file: "Masks/vignette_dexp3.jpg", opacity: 0.8)]),
        Entry(key: "dfuns", name: "DFUNS", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_dfuns.jpg", opacity: 0.5)]),
        Entry(key: "dqs", name: "DQS", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_dqs.jpg", opacity: 0.5)]),
        Entry(key: "ff100", name: "FF100", icon: nil, overlays: []),
        Entry(key: "fx3_2", name: "FX3 2", icon: nil, overlays: []),
        Entry(key: "fx3_3", name: "FX3 3", icon: nil, overlays: []),
        Entry(key: "fxn2", name: "FXN2", icon: "icon_filter_fxn.jpg", overlays: []),
        Entry(key: "fxnr", name: "FXNR", icon: "icon_filter_fxn.jpg", overlays: []),
        Entry(key: "glow", name: "GLOW", icon: nil, overlays: []),
        Entry(key: "grdr", name: "GRDR", icon: nil, overlays: []),
        Entry(key: "hoga", name: "HOGA", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_hoga.jpg", opacity: 0.5)]),
        Entry(key: "instc", name: "INSTC", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_instc.jpg", opacity: 0.5)]),
        Entry(key: "instsq", name: "INSTSQ", icon: nil, overlays: []),
        Entry(key: "instss", name: "INSTSS", icon: nil, overlays: []),
        Entry(key: "kg100", name: "KG100", icon: "icon_filter_kg100.png", overlays: []),
        Entry(key: "kino", name: "KINO", icon: nil, overlays: []),
        Entry(key: "kv80_kg200", name: "KV80 KG200", icon: "icon_filter_kg200.png", overlays: []),
        Entry(key: "kv88", name: "KV88", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_kv88.jpg", opacity: 0.5)]),
        Entry(key: "kv88_r", name: "KV88 R", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_kv88.jpg", opacity: 0.5)]),
        Entry(key: "nt16", name: "NT16", icon: "icon_filter_fnt16.png", overlays: [PresetOverlay(file: "Masks/vignette_nt16.jpg", opacity: 0.8)]),
        Entry(key: "nt16_2", name: "NT16 2", icon: nil, overlays: [PresetOverlay(file: "Masks/vignette_nt16.jpg", opacity: 0.8)]),
        Entry(key: "ofm_color", name: "OFM COLOR", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_ofm.jpg", opacity: 0.5)]),
        Entry(key: "ofm_light", name: "OFM LIGHT", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_ofm.jpg", opacity: 0.5)]),
        Entry(key: "ou_color", name: "OU COLOR", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_ou.jpg", opacity: 0.5)]),
        Entry(key: "ou_light", name: "OU LIGHT", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_ou.jpg", opacity: 0.5)]),
        Entry(key: "paf_eb3000_color", name: "PAF EB3000 COLOR", icon: "icon_filter_eb3000.png", overlays: [PresetOverlay(file: "Grain/grain_paf.jpg", opacity: 0.5)]),
        Entry(key: "paf_eb3000_light", name: "PAF EB3000 LIGHT", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_paf.jpg", opacity: 0.5)]),
        Entry(key: "paf_ec100_color", name: "PAF EC100 COLOR", icon: "icon_filter_ec100.png", overlays: [PresetOverlay(file: "Grain/grain_paf.jpg", opacity: 0.5)]),
        Entry(key: "paf_ec100_light", name: "PAF EC100 LIGHT", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_paf.jpg", opacity: 0.5)]),
        Entry(key: "s67", name: "S67", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_s67.jpg", opacity: 0.5)]),
        Entry(key: "slidep", name: "SLIDEP", icon: nil, overlays: [PresetOverlay(file: "Grain/grain_slidep.jpg", opacity: 0.5)]),
        Entry(key: "vclassic", name: "VCLASSIC", icon: nil, overlays: []),
        Entry(key: "velvia_x5", name: "VELVIA X5", icon: "icon_filter_velx5.png", overlays: []),
        Entry(key: "vfuns", name: "VFUNS", icon: nil, overlays: []),
        Entry(key: "lut_lip", name: "LUT LIP", icon: nil, overlays: []),
        Entry(key: "ndfilter", name: "NDFILTER", icon: nil, overlays: []),
        Entry(key: "puli", name: "PULI", icon: nil, overlays: []),
        Entry(key: "vhs", name: "VHS", icon: nil, overlays: []),
        Entry(key: "a709", name: "A709", icon: nil, overlays: []),
        Entry(key: "grdp", name: "GRDP", icon: "icon_filter_grdp.jpg", overlays: []),
        Entry(key: "kv2", name: "KV2", icon: nil, overlays: []),
        Entry(key: "std", name: "STD", icon: nil, overlays: []),
        Entry(key: "vs2", name: "VS2", icon: "icon_filter_vs2.png", overlays: []),
    ]
}
