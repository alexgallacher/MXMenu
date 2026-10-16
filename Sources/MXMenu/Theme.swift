import SwiftUI

// Controls here are drawn in plain SwiftUI (no NSView-backed Toggle/Slider/Picker)
// so they render in `--snapshot` images. They use system colours to look native
// in both light and dark mode.

enum Theme {
    static let fill = Color.primary.opacity(0.07)
    static let selected = Color.primary.opacity(0.13)
    static let track = Color.primary.opacity(0.12)
    static let separator = Color.primary.opacity(0.09)

    static func batteryColor(_ battery: HIDPPDevice.Battery) -> Color {
        if battery.charging { return .green }
        return battery.percent <= 15 ? .red : battery.percent <= 30 ? .orange : .green
    }

    static func batterySymbol(_ battery: HIDPPDevice.Battery) -> String {
        if battery.charging { return "battery.100percent.bolt" }
        switch battery.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

struct SwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.track))
                        .frame(width: 30, height: 18)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A slim slider in the system accent colour. `onCommit` fires when the drag ends.
struct AccentSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var onCommit: (Double) -> Void = { _ in }

    private let knob: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 4)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(4, knob / 2 + fraction * (width - knob)), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .offset(x: fraction * (width - knob))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in value = snapped(drag.location.x, width: width) }
                    .onEnded { _ in onCommit(value) })
        }
        .frame(height: 18)
    }

    private func snapped(_ x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max((x - knob / 2) / max(width - knob, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
    }
}

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

/// Compact segmented switch with a sliding highlight.
struct SegmentedControl<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { onSelect(option.value) }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Theme.selected)
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
