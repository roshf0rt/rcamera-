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
        if settings.histogram { names.append("HIST") }
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
    /// The five viewfinder tools in one row.
    private let viewfinderColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

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
                LazyVGrid(columns: viewfinderColumns, spacing: 10) {
                    tool("Zebra", symbol: "circle.lefthalf.striped.horizontal", on: settings.zebra) { $0.zebra.toggle() }
                    tool("Peaking", symbol: "scope", on: settings.focusPeaking) { $0.focusPeaking.toggle() }
                    tool("False color", symbol: "paintpalette", on: settings.falseColor) { $0.falseColor.toggle() }
                    tool("Histogram", symbol: "chart.bar.fill", on: settings.histogram) { $0.histogram.toggle() }
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

/// The scopes in the corner of the viewfinder: the histogram, and under it the luma waveform as Kino draws
/// it (across, the picture as it is held; up, brightness, with lines at black, 50% and white). They are laid
/// out once, landscape, and turn with the phone inside a square, so turned they still sit in the corner and
/// never leave their frame.
struct ScopesPanel: View {
    let engine: CameraEngine
    let showsHistogram: Bool
    let showsWaveform: Bool
    @Environment(\.iconRotation) private var angle

    static let width: CGFloat = 150
    static let waveformDepth: CGFloat = 84
    static let histogramDepth: CGFloat = 62
    private static let gap: CGFloat = 6

    private var sideways: Bool { abs(angle.truncatingRemainder(dividingBy: 180)) == 90 }

    private var height: CGFloat {
        (showsHistogram ? Self.histogramDepth : 0) + (showsWaveform ? Self.waveformDepth : 0)
            + (showsHistogram && showsWaveform ? Self.gap : 0)
    }

    var body: some View {
        let side = max(Self.width, height)
        let slackX = (side - Self.width) / 2
        let slackY = (side - height) / 2
        VStack(spacing: Self.gap) {
            if showsHistogram {
                histogram
                    .frame(height: Self.histogramDepth)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if showsWaveform {
                waveform
                    .frame(height: Self.waveformDepth)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: Self.width, height: height)
        .followsDevice()
        // Held upright the scopes hug the top left of their square; sideways too, as they are then seen.
        .offset(x: sideways ? -slackY : -slackX, y: sideways ? -slackX : -slackY)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sideways)
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var histogram: some View {
        let measured = engine.histogram
        let clipped = (measured?.clippedShare ?? 0) > 0.005
        let crushed = (measured?.crushedShare ?? 0) > 0.03
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.6))
            GeometryReader { geo in
                Path { path in
                    for share in [0.25, 0.5, 0.75] {
                        let x = 5 + (geo.size.width - 10) * share
                        path.move(to: CGPoint(x: x, y: 11))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height - 5))
                    }
                }
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }
            HistogramView(histogram: measured)
                .padding(.horizontal, 5)
                .padding(.top, 11)
                .padding(.bottom, 5)
            // The ends light up when the picture runs into them: blue for crushed blacks, red for clipping.
            HStack {
                Circle().fill(crushed ? Color(red: 0.25, green: 0.5, blue: 1) : Color.white.opacity(0.16)).frame(width: 5, height: 5)
                Spacer()
                Circle().fill(clipped ? Color(red: 1, green: 0.25, blue: 0.2) : Color.white.opacity(0.16)).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .animation(.easeOut(duration: 0.2), value: clipped)
            .animation(.easeOut(duration: 0.2), value: crushed)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var waveform: some View {
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

/// A histogram as cameras draw it: red, green and blue laid over each other, white where all three agree.
/// Black is on the left, white on the right.
struct HistogramView: View {
    let histogram: Histogram?

    private static let channels: [(channel: Histogram.Channel, color: Color)] = [
        (.red, Color(red: 0.96, green: 0.26, blue: 0.22)),
        (.green, Color(red: 0.24, green: 0.86, blue: 0.36)),
        (.blue, Color(red: 0.26, green: 0.46, blue: 1.0)),
    ]

    var body: some View {
        Canvas { context, size in
            guard let histogram, histogram.samples > 0 else { return }
            context.blendMode = .screen
            for entry in Self.channels {
                let heights = histogram.heights(entry.channel)
                let step = size.width / CGFloat(heights.count)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for (bin, value) in heights.enumerated() {
                    let y = size.height * (1 - CGFloat(value))
                    path.addLine(to: CGPoint(x: CGFloat(bin) * step, y: y))
                    path.addLine(to: CGPoint(x: CGFloat(bin + 1) * step, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(entry.color))
            }
        }
    }
}

/// What the false colours mean, shown while false colour is on: the bands of `ExposureAssist`, brightest first.
struct FalseColorLegend: View {
    private struct Row: Identifiable {
        let label: String
        /// A level inside the band, to take its colour from `ExposureAssist`.
        let luma: Double
        var id: String { label }
    }

    private static let rows = [
        Row(label: "CLIP", luma: 0.99),
        Row(label: "95%", luma: 0.95),
        Row(label: "SKIN", luma: 0.64),
        Row(label: "18%", luma: 0.46),
        Row(label: "LOW", luma: 0.05),
        Row(label: "BLACK", luma: 0.01),
    ]

    static let side: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Self.rows) { row in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Self.color(row.luma))
                        .frame(width: 11, height: 8)
                    Text(row.label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.6)))
        .followsDevice()
        .frame(width: Self.side, height: Self.side, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func color(_ luma: Double) -> Color {
        let colour = ExposureAssist.falseColor(luma: luma)
        return Color(red: colour.x, green: colour.y, blue: colour.z)
    }
}
