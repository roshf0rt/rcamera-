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

/// The EV pill: drag sideways to change exposure compensation, double-tap to reset.
struct EVDial: View {
    @Binding var value: Double
    var overlaid = false

    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 10) {
            ticks
            VStack(spacing: 0) {
                Text("EV").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Text(EVScale.format(value))
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 52)
            ticks
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(Capsule().fill(Color.black.opacity(overlaid ? 0.45 : 0.85)))
        .background(overlaid ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear), in: Capsule())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { gesture in
                    let start = dragStart ?? value
                    dragStart = start
                    value = EVScale.snapped(start + Double(gesture.translation.width) / 70)
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) { value = 0 }
        .sensoryFeedback(.selection, trigger: value)
    }

    private var ticks: some View {
        HStack(spacing: 9) {
            ForEach(0 ..< 4, id: \.self) { _ in
                Capsule().fill(Color(white: 0.4)).frame(width: 2, height: 14)
            }
        }
    }
}

struct OptionsPanel: View {
    let flash: FlashMode
    let timer: TimerOption
    let aspect: AspectOption
    let onFlash: () -> Void
    let onTimer: () -> Void
    let onAspect: () -> Void

    var body: some View {
        HStack {
            option(title: "Flash", active: flash != .off, action: onFlash) {
                Image(systemName: flashSymbol).font(.system(size: 26))
            }
            option(title: "Timer", active: timer != .off, action: onTimer) {
                ZStack {
                    Image(systemName: "timer").font(.system(size: 26))
                    if timer != .off {
                        Text("\(timer.seconds)")
                            .font(.system(size: 11, weight: .bold))
                            .offset(x: 0, y: 3)
                    }
                }
            }
            option(title: "Aspect", active: false, action: onAspect) {
                ZStack {
                    Image(systemName: "viewfinder").font(.system(size: 34, weight: .light))
                    Text(aspect.label).font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 8)
    }

    private var flashSymbol: String {
        switch flash {
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
