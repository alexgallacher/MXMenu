import SwiftUI

// Controls here are drawn in plain SwiftUI (no NSView-backed Toggle/Slider/Picker)
// so they look the same everywhere and render in `--snapshot` images.

enum Theme {
    static let bgTop = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let bgBottom = Color(red: 0.05, green: 0.05, blue: 0.08)
    static let card = Color.white.opacity(0.055)
    static let cardActive = Color.white.opacity(0.13)
    static let stroke = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.10)
    static let accent = Color(red: 0.40, green: 0.62, blue: 1.0)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
    static let good = Color(red: 0.36, green: 0.86, blue: 0.56)
    static let warn = Color(red: 1.0, green: 0.73, blue: 0.32)
    static let bad = Color(red: 1.0, green: 0.43, blue: 0.43)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.68, blue: 1.0), Color(red: 0.55, green: 0.43, blue: 1.0)],
        startPoint: .leading, endPoint: .trailing)

    static func batteryColor(_ battery: HIDPPDevice.Battery) -> Color {
        if battery.charging { return good }
        return battery.percent <= 15 ? bad : battery.percent <= 35 ? warn : good
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A rounded panel with a small caps heading.
struct Card<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }
}

/// Small rounded square holding an SF Symbol, used at the start of rows.
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Title with an optional explanation underneath, for toggle rows.
struct RowLabel: View {
    let title: String
    var detail: String?
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

struct SwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.track))
                        .frame(width: 34, height: 20)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A slim gradient slider. `onCommit` fires when the drag ends.
struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var onCommit: (Double) -> Void = { _ in }

    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 6)
                Capsule().fill(Theme.accentGradient)
                    .frame(width: max(6, knob / 2 + fraction * (width - knob)), height: 6)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
                    .offset(x: fraction * (width - knob))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in value = snapped(drag.location.x, width: width) }
                    .onEnded { _ in onCommit(value) })
        }
        .frame(height: 20)
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
    let symbol: String
    var id: Value { value }
}

/// Two-or-more-way switch with a sliding highlight.
struct SegmentedControl<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { onSelect(option.value) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 11, weight: .semibold))
                        Text(option.title).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.white : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.cardActive)
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Circular battery gauge with the percentage in the middle.
struct BatteryRing: View {
    let battery: HIDPPDevice.Battery?

    var body: some View {
        let color = battery.map(Theme.batteryColor) ?? Theme.tertiary
        let fraction = CGFloat(battery?.percent ?? 0) / 100
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 4)
            VStack(spacing: -1) {
                if battery?.charging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(color)
                }
                Text(battery.map { "\($0.percent)%" } ?? "–")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: 50, height: 50)
        .animation(.easeOut(duration: 0.6), value: battery?.percent)
    }
}

/// Capsule button used for DPI presets.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : Theme.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card),
                            in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Theme.stroke))
        }
        .buttonStyle(PressableStyle())
    }
}
