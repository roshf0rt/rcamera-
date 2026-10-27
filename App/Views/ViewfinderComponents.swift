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

/// The panel under the "..." button. Photo mode: Flash, Timer, Aspect, Frame. Video mode: FPS, Resolution, Stabilization.
struct OptionsPanel: View {
    let mode: CaptureMode
    let settings: AppSettings
    let update: ((inout AppSettings) -> Void) -> Void
    let openDynamicRange: () -> Void

    var body: some View {
        HStack {
            if mode == .photo { photoOptions } else { videoOptions }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var photoOptions: some View {
        option(title: "Flash", active: settings.flash != .off, action: { update { $0.flash = $0.flash.next } }) {
            Image(systemName: flashSymbol).font(.system(size: 26))
        }
        option(title: "Timer", active: settings.timer != .off, action: { update { $0.timer = $0.timer.next } }) {
            ZStack {
                Image(systemName: "timer").font(.system(size: 26))
                if settings.timer != .off {
                    Text("\(settings.timer.seconds)").font(.system(size: 11, weight: .bold)).offset(y: 3)
                }
            }
        }
        option(title: "Aspect", active: false, action: { update { $0.aspect = $0.aspect.next } }) {
            ZStack {
                Image(systemName: "viewfinder").font(.system(size: 34, weight: .light))
                Text(settings.aspect.label).font(.system(size: 11, weight: .semibold))
            }
        }
        option(title: "Frame", active: settings.frame != .off, action: { update { $0.frame = $0.frame.next } }) {
            Image(systemName: "rectangle.inset.filled").font(.system(size: 26))
        }
        dynamicRangeOption
        option(title: "Portrait", active: settings.portrait, action: { update { $0.portrait.toggle() } }) {
            Image(systemName: "person.crop.circle").font(.system(size: 26))
        }
    }

    private var dynamicRangeOption: some View {
        option(title: "Dynamic range", active: settings.dynamicRange != .preset, action: openDynamicRange) {
            VStack(spacing: 2) {
                Text("DR").font(.system(size: 18, weight: .bold))
                Text(settings.dynamicRange.label).font(.system(size: 10, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private var videoOptions: some View {
        option(title: "FPS", active: false, action: { update { $0.videoFPS = Self.nextFPS($0.videoFPS) } }) {
            Text("\(settings.videoFPS)").font(.system(size: 24, weight: .semibold))
        }
        option(title: "Resolution", active: false, action: {
            update { $0.videoResolution = $0.videoResolution == .hd1080 ? .uhd4K : .hd1080 }
        }) {
            Text(settings.videoResolution.label).font(.system(size: 24, weight: .semibold))
        }
        dynamicRangeOption
        option(title: "Stabilization", active: false, action: { update { $0.videoStabilization = $0.videoStabilization.next } }) {
            Text(settings.videoStabilization.label)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(settings.videoStabilization == .off ? 0.1 : 0.28)))
                .foregroundStyle(settings.videoStabilization == .off ? Theme.secondaryText : .white)
        }
    }

    private static func nextFPS(_ fps: Int) -> Int {
        let options = [24, 30, 60]
        return options[((options.firstIndex(of: fps) ?? 0) + 1) % options.count]
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
            VStack(spacing: 10) {
                icon().frame(height: 38)
                Text(title).font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(active ? Theme.accent : .white)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// The strip under the top bar for the dynamic-range control: one tap picks a step.
struct DynamicRangeStrip: View {
    let selected: DynamicRangeChoice
    let pick: (DynamicRangeChoice) -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 22))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.chrome))
            ForEach(DynamicRangeChoice.allCases, id: \.self) { choice in
                Button { pick(choice) } label: {
                    Text(choice.label)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(choice == selected ? Theme.accent : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(choice == selected ? Theme.accent : Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.6))
        .background(.ultraThinMaterial)
    }
}

/// The f-number pill over the viewfinder in portrait mode. Tapped open, it lists the stops.
struct ApertureControl: View {
    let fNumber: Double
    @Binding var expanded: Bool
    let pick: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if expanded {
                ForEach(PortraitAperture.stops, id: \.self) { stop in
                    Button { pick(stop) } label: {
                        Text(String(format: "%.1f", stop))
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(stop == fNumber ? Theme.accent : .white)
                            .frame(minWidth: 42)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { expanded = true } label: {
                    HStack(spacing: 6) {
                        Text("ƒ").font(.system(size: 16, weight: .semibold))
                        Text(String(format: "%.1f", fNumber)).font(.system(size: 16, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)).background(.ultraThinMaterial, in: Capsule()))
    }
}
