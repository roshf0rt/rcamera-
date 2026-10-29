import AVFoundation
import CameraCore
import SwiftUI

/// Hosts the sample-buffer display layer that shows the processed camera frames.
struct ViewfinderLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.host(layer)
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        private var hosted: CALayer?

        func host(_ layer: CALayer) {
            hosted?.removeFromSuperlayer()
            hosted = layer
            self.layer.addSublayer(layer)
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    path.move(to: CGPoint(x: geo.size.width * fraction, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width * fraction, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: geo.size.height * fraction))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * fraction))
                }
            }
            .stroke(.white.opacity(0.55), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}

struct LevelOverlay: View {
    let roll: Double

    var body: some View {
        let isLevel = abs(roll) < 0.02
        Capsule()
            .fill(isLevel ? Theme.accent : .white.opacity(0.8))
            .frame(width: 120, height: 2)
            .rotationEffect(.radians(-roll))
            .animation(.easeOut(duration: 0.1), value: roll)
            .allowsHitTesting(false)
    }
}

struct FocusMarker: View {
    @State private var settled = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Theme.accent, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(settled ? 1 : 1.35)
            .onAppear { withAnimation(.easeOut(duration: 0.2)) { settled = true } }
            .allowsHitTesting(false)
    }
}

struct CircleIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.black.opacity(0.38)))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ZoomChips: View {
    let stops: [ZoomStop]
    let active: ZoomStop?
    let mode: CaptureMode
    let select: (ZoomStop) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(stops) { stop in
                let isActive = stop == active
                Button { select(stop) } label: {
                    chip(for: stop, isActive: isActive)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: active)
    }

    @ViewBuilder
    private func chip(for stop: ZoomStop, isActive: Bool) -> some View {
        Group {
            if mode == .video {
                VStack(spacing: -1) {
                    Text(stop.label).font(.system(size: isActive ? 20 : 17, weight: .semibold))
                    if isActive { Text("mm").font(.system(size: 11, weight: .medium)) }
                }
            } else {
                Text(isActive ? "\(stop.label)×" : stop.label)
                    .font(.system(size: isActive ? 18 : 17, weight: .semibold))
            }
        }
        .foregroundStyle(isActive ? Theme.accent : .white)
        .followsDevice()
        .frame(width: isActive ? 54 : 42, height: 54)
        .background(Circle().fill(Color.black.opacity(isActive ? 0.45 : 0)))
        .contentShape(Rectangle())
    }
}

/// Exposure wheel. Collapsed it is a small pill; while you drag it opens into a full-width ruler.
/// Dragging right moves the ticks right, so the value under the center mark goes down.
struct EVWheel: View {
    @Binding var value: Double
    @Binding var isActive: Bool
    var overlaid = false
    /// Keeps the ruler open, for screens where the wheel is the main control.
    var pinnedOpen = false

    @State private var dragStartValue: Double?
    @State private var rawValue: Double?
    @State private var collapseTask: Task<Void, Never>?

    private let pointsPerEV: CGFloat = 200

    var body: some View {
        GeometryReader { geo in
            let open = isActive || pinnedOpen
            let width = open ? geo.size.width - (pinnedOpen ? 0 : 24) : 176
            ZStack {
                Capsule().fill(Color.black.opacity(overlaid ? 0.4 : 0.3))
                    .background(.ultraThinMaterial, in: Capsule())
                if open { ruler(width: width) } else { compact }
            }
            .frame(width: width, height: 46)
            .contentShape(Capsule())
            .position(x: geo.size.width / 2, y: 23)
            .gesture(drag)
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
            .animation(.easeOut(duration: 0.2), value: open)
            .sensoryFeedback(.selection, trigger: value)
        }
        .frame(height: 46)
    }

    private var compact: some View {
        HStack(spacing: 10) {
            ticks
            VStack(spacing: 0) {
                Text("EV").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Text(EVScale.format(value))
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 56)
            ticks
        }
    }

    private var ticks: some View {
        HStack(spacing: 9) {
            ForEach(0 ..< 4, id: \.self) { _ in
                Capsule().fill(Color(white: 0.4)).frame(width: 2, height: 14)
            }
        }
    }

    private func ruler(width: CGFloat) -> some View {
        let shown = rawValue ?? value
        return ZStack {
            Canvas { context, size in
                let center = size.width / 2
                for step in -20 ... 20 {
                    let x = center + CGFloat(Double(step) / 10 - shown) * pointsPerEV
                    guard x > 8, x < size.width - 8 else { continue }
                    let major = step % 5 == 0
                    let height: CGFloat = major ? 22 : 16
                    let rect = CGRect(x: x - 1, y: (size.height - height) / 2, width: 2, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(major ? 0.7 : 0.35)))
                }
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            Capsule().fill(.white).frame(width: 3, height: 30)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                collapseTask?.cancel()
                if dragStartValue == nil {
                    dragStartValue = value
                    isActive = true
                }
                let start = dragStartValue ?? value
                let raw = min(max(start - Double(gesture.translation.width) / Double(pointsPerEV), EVScale.range.lowerBound), EVScale.range.upperBound)
                rawValue = raw
                value = EVScale.snapped(raw)
            }
            .onEnded { _ in
                dragStartValue = nil
                rawValue = nil
                scheduleCollapse()
            }
    }

    private func reset() {
        value = 0
        isActive = true
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            if !Task.isCancelled { isActive = false }
        }
    }
}

/// The "Exposure -0.4" label shown above the wheel while it is open.
struct EVBubble: View {
    let value: Double

    var body: some View {
        VStack(spacing: 0) {
            Text("Exposure").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
            Text(EVScale.format(value))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// The panel under the "..." button, a grid of fixed-width cells so labels never wrap, and below it the
/// PRO row that opens the tools for those who want them (`ProPanel`).
/// Photo: Flash, Timer, Aspect, Frame, Range, Portrait. Video: FPS, Resolution, Stabilization.
struct OptionsPanel: View {
    let mode: CaptureMode
    let settings: AppSettings
    let update: ((inout AppSettings) -> Void) -> Void
    let openDynamicRange: () -> Void
    let openPro: () -> Void
    /// Frame rates the camera runs, by video width; 120 appears only where the camera has it.
    var frameRates: [Int: [Int]] = [:]

    /// Six photo options sit three by two, three video options in one row, so no cell is left empty.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    }

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 14) {
                if mode == .photo { photoOptions } else { videoOptions }
            }
            ProRow(mode: mode, settings: settings, action: openPro)
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var photoOptions: some View {
        option(title: "Flash", active: settings.flash != .off, action: { update { $0.flash = $0.flash.next } }) {
            Image(systemName: flashSymbol).font(.system(size: 22))
        }
        option(title: settings.timer == .off ? "Timer" : "\(settings.timer.seconds)s", active: settings.timer != .off, action: { update { $0.timer = $0.timer.next } }) {
            Image(systemName: "timer").font(.system(size: 22))
        }
        option(title: "Aspect", active: false, action: { update { $0.aspect = $0.aspect.next } }) {
            ZStack {
                Image(systemName: "viewfinder").font(.system(size: 28, weight: .light))
                Text(settings.aspect.label).font(.system(size: 9, weight: .semibold))
            }
        }
        option(title: settings.frame == .off ? "Frame" : settings.frame.label, active: settings.frame != .off, action: { update { $0.frame = $0.frame.next } }) {
            Image(systemName: "rectangle.inset.filled").font(.system(size: 22))
        }
        dynamicRangeOption
        option(title: "Portrait", active: settings.portrait, action: { update { $0.portrait.toggle() } }) {
            Image(systemName: "person.crop.circle").font(.system(size: 22))
        }
    }

    private var dynamicRangeOption: some View {
        option(title: "Range", active: settings.dynamicRange != .preset, action: openDynamicRange) {
            VStack(spacing: 1) {
                Text("DR").font(.system(size: 15, weight: .bold))
                Text(settings.dynamicRange.label).font(.system(size: 8, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private var videoOptions: some View {
        option(title: "FPS", active: settings.videoFPS > 60, action: {
            let options = rates(for: settings.videoResolution)
            update { $0.videoFPS = Self.next($0.videoFPS, in: options) }
        }) {
            Text("\(settings.videoFPS)").font(.system(size: 18, weight: .semibold))
        }
        option(title: "Resolution", active: false, action: {
            let resolution: VideoResolution = settings.videoResolution == .hd1080 ? .uhd4K : .hd1080
            let options = rates(for: resolution)
            update {
                $0.videoResolution = resolution
                // A rate the new size cannot run steps down to the nearest one it can.
                if !options.contains($0.videoFPS) {
                    let current = settings.videoFPS
                    $0.videoFPS = options.last { $0 <= current } ?? options.first ?? 30
                }
            }
        }) {
            Text(settings.videoResolution.label).font(.system(size: 18, weight: .semibold))
        }
        option(title: "Stabilize", active: settings.videoStabilization != .off, action: { update { $0.videoStabilization = $0.videoStabilization.next } }) {
            Text(Self.shortStabilization(settings.videoStabilization))
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(settings.videoStabilization == .off ? 0.1 : 0.28)))
        }
    }

    /// Short enough that the cell still fits once the icon turns with the phone (rotation does not re-lay out).
    private static func shortStabilization(_ mode: VideoStabilization) -> String {
        switch mode {
        case .off: "OFF"
        case .standard: "STD"
        case .cinematic: "CINE"
        }
    }

    private func rates(for resolution: VideoResolution) -> [Int] {
        let known = frameRates[resolution.size.width] ?? []
        return known.isEmpty ? [24, 30, 60] : known
    }

    private static func next(_ fps: Int, in options: [Int]) -> Int {
        guard !options.isEmpty else { return fps }
        return options[((options.firstIndex(of: fps) ?? -1) + 1) % options.count]
    }

    private var flashSymbol: String {
        switch settings.flash {
        case .off: "bolt.slash.fill"
        case .auto: "bolt.badge.automatic.fill"
        case .on: "bolt.fill"
        }
    }

    private func option<Icon: View>(title: String, active: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon().frame(height: 30)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .followsDevice()
            .foregroundStyle(active ? Theme.accent : .white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The strip under the top bar for the dynamic-range control: one tap picks a step. Equal cells, one line.
struct DynamicRangeStrip: View {
    let selected: DynamicRangeChoice
    let pick: (DynamicRangeChoice) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DynamicRangeChoice.allCases, id: \.self) { choice in
                Button { pick(choice) } label: {
                    Text(choice.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(choice == selected ? Theme.accent : .white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(choice == selected ? Color.white.opacity(0.14) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
    }
}

/// Hold, then slide sideways to pick from a list, as mood's aperture and lens controls work: the control
/// opens when the press is held, follows the finger while it stays down, and closes on release. A quick
/// tap runs `tapped` instead.
struct HoldScrub: ViewModifier {
    let count: Int
    let index: Int
    var step: CGFloat = 34
    let began: () -> Void
    let changed: (Int) -> Void
    let ended: () -> Void
    let tapped: () -> Void

    @State private var start: Int?
    /// True while the hold lasts. A gesture the system cancels never reaches `onEnded`, but this resets,
    /// so the control never stays open after the finger is gone.
    @GestureState private var holding = false

    func body(content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: 0.18)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($holding) { value, state, _ in
                    switch value {
                    case .first(true), .second(true, _): state = true
                    default: break
                    }
                }
                .onChanged { value in
                    switch value {
                    case .first(true):
                        begin()
                    case .second(true, let drag):
                        begin()
                        guard let drag, let start else { return }
                        // The scale follows the finger: sliding right brings the lower values in.
                        let moved = Int((drag.translation.width / step).rounded())
                        let target = min(max(start - moved, 0), count - 1)
                        if target != index {
                            UISelectionFeedbackGenerator().selectionChanged()
                            changed(target)
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    start = nil
                    ended()
                }
                .exclusively(before: TapGesture().onEnded { tapped() })
        )
        .onChange(of: holding) { _, now in
            if !now, start != nil {
                start = nil
                ended()
            }
        }
    }

    private func begin() {
        guard start == nil else { return }
        start = index
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        began()
    }
}

/// A sideways scale of values centred on the current one, the neighbours fading out, as under mood's
/// aperture dial.
struct ScaleStrip: View {
    let labels: [String]
    let index: Int
    var spacing: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(labels.indices, id: \.self) { item in
                    let distance = abs(item - index)
                    Text(labels[item])
                        .font(.system(size: item == index ? 26 : 22, weight: item == index ? .semibold : .medium))
                        .foregroundStyle(item == index ? Theme.accent : .white.opacity(distance == 1 ? 0.75 : 0.3))
                        .fixedSize()
                        .position(x: geo.size.width / 2 + CGFloat(item - index) * spacing, y: geo.size.height / 2)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: index)
        }
        .frame(height: 36)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                     .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}

/// A polygon with rounded corners: the aperture blades. Roundness 0 is sharp, 1 nearly a circle.
struct ApertureShape: Shape {
    var sides = 6
    var roundness: CGFloat
    var rotation: Angle

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(roundness, rotation.radians) }
        set { roundness = newValue.first; rotation = .radians(newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let count = Double(sides)
        let points = (0 ..< sides).map { side -> CGPoint in
            let angle: Double = rotation.radians + Double(side) * 2 * Double.pi / count - Double.pi / 2
            let x: CGFloat = centre.x + radius * CGFloat(cos(angle))
            let y: CGFloat = centre.y + radius * CGFloat(sin(angle))
            return CGPoint(x: x, y: y)
        }
        let edge = 2 * radius * sin(.pi / CGFloat(sides))
        let corner = max(0.5, roundness * edge * 0.5)
        var path = Path()
        let last = points[sides - 1], first = points[0]
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for side in 0 ..< sides {
            let point = points[side], next = points[(side + 1) % sides]
            path.addArc(tangent1End: point, tangent2End: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), radius: corner)
        }
        path.closeSubpath()
        return path
    }
}

/// The big aperture shown while the f-number is being dragged: a glowing out-of-focus light seen through
/// six blades that close as the number goes up, a dotted ring, and the scale of stops.
struct ApertureOverlay: View {
    let fNumber: Double

    private var index: Int { PortraitAperture.stops.firstIndex(of: fNumber) ?? 0 }
    /// 1 wide open, 0.3 at f/16: the opening shrinks like real blades closing.
    private var openness: CGFloat {
        let t = log(fNumber / 1.4) / log(16 / 1.4)
        return CGFloat(1 - 0.7 * t)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 10]))
                    .frame(width: 150, height: 150)
                let shape = ApertureShape(roundness: openness * 0.9, rotation: .degrees(Double(openness) * 30))
                ZStack {
                    Circle().fill(Color(red: 1, green: 0.62, blue: 0.2)).frame(width: 70).offset(x: 6, y: -24)
                    Circle().fill(Color(red: 0.5, green: 0.15, blue: 0.95)).frame(width: 80).offset(x: -18, y: 14)
                    Circle().fill(Color(red: 0.95, green: 0.3, blue: 0.15)).frame(width: 64).offset(x: 24, y: 16)
                }
                .blur(radius: 14)
                .frame(width: 120, height: 120)
                .clipShape(shape)
                .overlay(shape.stroke(.white, lineWidth: 4 / max(openness, 0.3)))
                .scaleEffect(openness)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: fNumber)
            }
            .frame(height: 160)
            ScaleStrip(labels: PortraitAperture.stops.map(Self.format), index: index)
                .frame(width: 300)
            Text("APERTURE")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .shadow(color: .black.opacity(0.35), radius: 12)
    }

    static func format(_ value: Double) -> String { ApertureTitle.format(value) }
}

/// The big lens shown while the lens is being dragged: its name in a ring, the scale of lenses and its character.
struct LensOverlay: View {
    let lens: LensStyle

    private var lenses: [LensStyle] { LensStyle.allCases.sorted { $0.order < $1.order } }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 10]))
                    .frame(width: 150, height: 150)
                Text(lens.label)
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .id(lens)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            .frame(height: 160)
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: lens)
            ScaleStrip(labels: lenses.map(\.label), index: lenses.firstIndex(of: lens) ?? 0, spacing: 76)
                .frame(width: 320)
            Text(lens.summary.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .shadow(color: .black.opacity(0.35), radius: 12)
    }
}
