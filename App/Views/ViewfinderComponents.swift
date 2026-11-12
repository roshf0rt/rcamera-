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
        // Level is measured from the nearest quarter turn, so a phone held level on its side lights too.
        let quarter = Double.pi / 2
        let off = roll - (roll / quarter).rounded() * quarter
        let isLevel = abs(off) < 0.02
        Capsule()
            .fill(isLevel ? Theme.accent : .white.opacity(0.8))
            .frame(width: 120, height: 2)
            .rotationEffect(.radians(-roll))
            .animation(.easeOut(duration: 0.1), value: roll)
            .allowsHitTesting(false)
    }
}

/// The square where a tap focused: it closes in on the spot, holds, then dims before it goes.
struct FocusMarker: View {
    @State private var settled = false
    @State private var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .overlay {
                // Ticks on the four sides, as on a camera's focus frame.
                ForEach(0 ..< 4, id: \.self) { side in
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 1.5, height: 6)
                        .offset(y: -32)
                        .rotationEffect(.degrees(Double(side) * 90))
                }
            }
            .scaleEffect(settled ? 1 : 1.4)
            .opacity(settled ? (dimmed ? 0.45 : 1) : 0)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { settled = true }
                withAnimation(.easeInOut(duration: 0.35).delay(0.7)) { dimmed = true }
            }
            .allowsHitTesting(false)
    }
}

struct ZoomChips: View {
    let stops: [ZoomStop]
    /// The stop the zoom is on, and between stops the live value its chip shows.
    let reading: ZoomStop.Reading
    let mode: CaptureMode
    let select: (ZoomStop) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(stops) { stop in
                let isActive = stop == reading.stop
                Button { select(stop) } label: {
                    chip(for: stop, isActive: isActive, live: isActive ? reading.live : nil)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.smooth(duration: 0.22), value: reading.stop)
        // A tick as the zoom passes a lens or a stop.
        .sensoryFeedback(.selection, trigger: reading.stop)
    }

    /// `live` is the zoom while it sits between stops: one decimal on photo, the focal length on video.
    @ViewBuilder
    private func chip(for stop: ZoomStop, isActive: Bool, live: Double?) -> some View {
        Group {
            if mode == .video {
                VStack(spacing: -1) {
                    Text(live.map { "\(Int(($0 * 24).rounded()))" } ?? stop.label)
                        .font(.system(size: isActive ? 20 : 17, weight: .semibold))
                        .contentTransition(.numericText())
                    if isActive {
                        Text("mm")
                            .font(.system(size: 11, weight: .medium))
                            .transition(.opacity)
                    }
                }
            } else {
                Text(live.map { String(format: "%.1f×", $0) } ?? (isActive ? "\(stop.label)×" : stop.label))
                    .font(.system(size: isActive ? 18 : 17, weight: .semibold))
                    .contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(isActive ? Theme.accent : .white)
        .followsDevice()
        .frame(width: isActive ? 54 : 42, height: 54)
        .background(Circle().fill(Color.black.opacity(isActive ? 0.45 : 0)))
        .contentShape(Rectangle())
        // The chip that takes the zoom grows and fades in; the one that lets go shrinks back.
        .animation(.smooth(duration: 0.22), value: isActive)
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

/// The exposure ruler across the top of the picture, as Kino has it: the value over a ruler of ticks, and a
/// swipe along it moves the exposure. Held sideways the host lays it along the edge that is then the top
/// and turns it with the phone, and the swipe follows: `quarterTurns` says which way the user's right runs
/// on the screen. Double tap puts it back to 0.
struct ExposureRuler: View {
    @Binding var value: Double
    let orientation: DeviceOrientation

    @State private var dragStart: Double?
    @State private var rawValue: Double?
    /// Lit while a finger is on it, and a moment after.
    @State private var active = false
    @State private var fadeTask: Task<Void, Never>?

    private let pointsPerEV: CGFloat = 180

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill").font(.system(size: 12))
                Text(EVScale.format(value))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .frame(width: 44)
            }
            .foregroundStyle(abs(value) > 0.05 ? Theme.accent : .white)
            .shadow(color: .black.opacity(0.5), radius: 3)
            ZStack {
                Capsule().fill(Color.black.opacity(0.35))
                    .background(.ultraThinMaterial, in: Capsule())
                ticks
                Capsule().fill(Theme.accent).frame(width: 3, height: 24)
            }
            .frame(height: 32)
        }
        .opacity(active ? 1 : 0.85)
        .contentShape(Rectangle())
        .gesture(drag)
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        .sensoryFeedback(.selection, trigger: value)
        .animation(.easeOut(duration: 0.2), value: active)
        .accessibilityElement()
        .accessibilityLabel("Exposure")
        .accessibilityValue(EVScale.format(value))
        .accessibilityAdjustableAction { direction in
            let next = value + (direction == .increment ? EVScale.step : -EVScale.step)
            value = EVScale.snapped(next)
        }
    }

    private var ticks: some View {
        let shown = rawValue ?? value
        return Canvas { context, size in
            let center = size.width / 2
            for step in Int(EVScale.range.lowerBound * 10) ... Int(EVScale.range.upperBound * 10) {
                let x = center + CGFloat(Double(step) / 10 - shown) * pointsPerEV
                guard x > 10, x < size.width - 10 else { continue }
                let whole = step % 10 == 0
                let half = step % 5 == 0
                let height: CGFloat = whole ? 20 : (half ? 15 : 10)
                let rect = CGRect(x: x - 0.75, y: (size.height - height) / 2, width: 1.5, height: height)
                let opacity = step == 0 ? 0.95 : (half ? 0.65 : 0.35)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(.white.opacity(opacity)))
            }
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    /// Measured on the screen, not in the ruler's own turned space, so it is right however the ruler is laid.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { gesture in
                fadeTask?.cancel()
                if dragStart == nil {
                    dragStart = value
                    active = true
                }
                let travel = orientation.rightwardTravel(dx: Double(gesture.translation.width), dy: Double(gesture.translation.height))
                // Ticks follow the finger, so the value under the centre mark falls as the finger goes right.
                let raw = min(max((dragStart ?? value) - travel / Double(pointsPerEV), EVScale.range.lowerBound), EVScale.range.upperBound)
                rawValue = raw
                value = EVScale.snapped(raw)
            }
            .onEnded { _ in
                dragStart = nil
                rawValue = nil
                dim()
            }
    }

    private func reset() {
        value = 0
        active = true
        dim()
    }

    private func dim() {
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { active = false }
        }
    }
}

/// The panel under the "..." button, a grid of fixed-width cells so labels never wrap, and below it the
/// PRO row that opens the tools for those who want them (`ProPanel`).
/// Photo: Flash, Timer, Aspect, Frame. Video: FPS, Resolution, Stabilization.
struct OptionsPanel: View {
    let mode: CaptureMode
    let settings: AppSettings
    let update: ((inout AppSettings) -> Void) -> Void
    let openPro: () -> Void
    /// Frame rates the camera runs, by video width; 120 appears only where the camera has it.
    var frameRates: [Int: [Int]] = [:]

    /// One row either way: four photo options, three video options.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: mode == .photo ? 4 : 3)
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

    /// Short, so the chip fits the icon's square at a readable size.
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
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(spacing: 2) {
                // A square slot, and content no wider than it: turned with the phone it still fits, as
                // rotation does not re-lay out ("1080p" sideways would otherwise run into the title).
                icon()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 40, maxHeight: 40)
                    .followsDevice()
                    .frame(width: 40, height: 40)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(active ? Theme.accent : .white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}
