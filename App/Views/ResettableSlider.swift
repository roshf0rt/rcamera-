import SwiftUI

/// A slider that goes back to where it starts on a double tap. The system Slider takes every touch on itself,
/// so a double tap on it never reaches a gesture outside; this one draws its own track and listens for both.
struct ResettableSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where a double tap puts it.
    let reset: Double
    /// Snaps to multiples of this from the lower end of the range.
    var step: Double?
    /// True when a drag begins, false when it ends or a double tap resets it.
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    private let thumb: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: thumb / 2 + usable * fraction, height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: usable * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { drag in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        let position = min(max((drag.location.x - thumb / 2) / usable, 0), 1)
                        value = snapped(range.lowerBound + Double(position) * span)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard value != reset else { return }
                    withAnimation(.smooth(duration: 0.25)) { value = reset }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEditingChanged(false)
                }
            )
        }
        .frame(height: 32)
        .sensoryFeedback(.selection, trigger: step == nil ? nil : value)
    }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard let step, step > 0 else { return clamped }
        return min(range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step, range.upperBound)
    }
}
