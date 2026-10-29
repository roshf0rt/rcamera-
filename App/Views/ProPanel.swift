import CameraCore
import SwiftUI

/// The row at the bottom of the options shade that opens the pro tools. It names what is on, so a tool left
/// on is never a mystery.
struct ProRow: View {
    let mode: CaptureMode
    let settings: AppSettings
    let action: () -> Void

    private var active: [String] {
        var names: [String] = []
        if mode == .video, settings.autoMotion { names.append("180°") }
        if settings.zebra { names.append("ZEBRA") }
        if settings.focusPeaking { names.append("PEAK") }
        if settings.falseColor { names.append("FALSE") }
        if settings.waveform { names.append("WAVE") }
        if settings.whiteBalanceKelvin != nil { names.append(WhiteBalanceSteps.label(kelvin: settings.whiteBalanceKelvin)) }
        if mode == .video, settings.lockExposureWhileRecording || settings.lockWhiteBalanceWhileRecording { names.append("REC LOCK") }
        return names
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("PRO")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Theme.accent))
                Text(active.isEmpty ? "Exposure tools, white balance" : active.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active.isEmpty ? Theme.secondaryText : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Tools for those who want them, kept out of the way under PRO in the options shade: aids drawn on the
/// viewfinder only, white balance, and for video AutoMotion and the recording locks.
struct ProPanel: View {
    let mode: CaptureMode
    let settings: AppSettings
    let update: ((inout AppSettings) -> Void) -> Void
    let back: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        Text("PRO").font(.system(size: 14, weight: .heavy)).tracking(1.2)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Shown on the viewfinder only")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            section("VIEWFINDER") {
                LazyVGrid(columns: columns, spacing: 10) {
                    tool("Zebra", symbol: "circle.lefthalf.striped.horizontal", on: settings.zebra) { $0.zebra.toggle() }
                    tool("Peaking", symbol: "scope", on: settings.focusPeaking) { $0.focusPeaking.toggle() }
                    tool("False color", symbol: "paintpalette", on: settings.falseColor) { $0.falseColor.toggle() }
                    tool("Waveform", symbol: "waveform.path.ecg", on: settings.waveform) { $0.waveform.toggle() }
                }
            }

            if mode == .video {
                section("EXPOSURE") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        tool("AutoMotion", text: "180°", on: settings.autoMotion) { $0.autoMotion.toggle() }
                        tool("AE lock REC", symbol: "lock.circle", on: settings.lockExposureWhileRecording) { $0.lockExposureWhileRecording.toggle() }
                        tool("WB lock REC", symbol: "lock.square", on: settings.lockWhiteBalanceWhileRecording) { $0.lockWhiteBalanceWhileRecording.toggle() }
                    }
                }
            }

            section("WHITE BALANCE") {
                VStack(alignment: .leading, spacing: 8) {
                    chips(["AUTO"] + WhiteBalanceSteps.kelvins.map { "\($0)K" },
                          selected: settings.whiteBalanceKelvin.map { "\($0)K" } ?? "AUTO") { title in
                        update { $0.whiteBalanceKelvin = title == "AUTO" ? nil : Int(title.dropLast()) }
                    }
                    if settings.whiteBalanceKelvin != nil {
                        chips(WhiteBalanceSteps.tints.map(Self.tintLabel), selected: Self.tintLabel(settings.whiteBalanceTint)) { title in
                            if let index = WhiteBalanceSteps.tints.map(Self.tintLabel).firstIndex(of: title) {
                                update { $0.whiteBalanceTint = WhiteBalanceSteps.tints[index] }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .animation(CameraView.panelSpring, value: settings.whiteBalanceKelvin != nil)
    }

    /// "G15", "0", "M15": green or magenta.
    private static func tintLabel(_ tint: Int) -> String {
        tint == 0 ? "TINT 0" : (tint < 0 ? "G\(-tint)" : "M\(tint)")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    private func tool(_ title: String, symbol: String? = nil, text: String? = nil, on: Bool, change: @escaping (inout AppSettings) -> Void) -> some View {
        Button { update(change) } label: {
            VStack(spacing: 4) {
                // A square slot that holds the icon turned either way (rotation does not re-lay out).
                Group {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 20))
                    } else if let text {
                        Text(text).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: 30, maxHeight: 30)
                .followsDevice()
                .frame(width: 30, height: 30)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? Theme.accent : .white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Color.white.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }

    private func chips(_ titles: [String], selected: String, pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(titles, id: \.self) { title in
                    Button { pick(title) } label: {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(title == selected ? Color.black : .white)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(title == selected ? Theme.accent : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The luma waveform in the corner of the viewfinder, as Kino draws it: across, the picture as it is held;
/// up, brightness, with lines at black, 50% and white. The panel is laid out once, landscape, and turns
/// with the phone inside a square, so turned it still sits in the corner and never leaves its frame.
struct WaveformPanel: View {
    let engine: CameraEngine
    @Environment(\.iconRotation) private var angle

    static let side: CGFloat = 150
    static let depth: CGFloat = 84

    private var sideways: Bool { abs(angle.truncatingRemainder(dividingBy: 180)) == 90 }

    var body: some View {
        let slack = (Self.side - Self.depth) / 2
        panel
            .frame(width: Self.side, height: Self.depth)
            .followsDevice()
            // Held upright the panel hugs the top of its square, sideways the left.
            .offset(x: sideways ? -slack : 0, y: sideways ? 0 : -slack)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sideways)
            .frame(width: Self.side, height: Self.side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var panel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.6))
            GeometryReader { geo in
                let inset: CGFloat = 5
                let height = geo.size.height - inset * 2
                Path { path in
                    for share in [0.0, 0.25, 0.5, 0.75, 1.0] {
                        let y = inset + height * share
                        path.move(to: CGPoint(x: inset, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width - inset, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                if let image = engine.waveform {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .blendMode(.screen)
                        .frame(width: geo.size.width - inset * 2, height: height)
                        .offset(x: inset, y: inset)
                }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text("100").padding(.top, 1)
                    Spacer()
                    Text("50")
                    Spacer()
                    Text("0").padding(.bottom, 1)
                }
                Spacer()
            }
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.leading, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
