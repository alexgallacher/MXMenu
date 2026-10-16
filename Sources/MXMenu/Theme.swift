import SwiftUI

// Controls here are drawn in plain SwiftUI (no NSView-backed Toggle/Slider/Picker)
// so they render in `--snapshot` images. Fills use the primary colour at low
// opacity so the panel works on the menu's material in light and dark mode.

enum Theme {
    static let fill = Color.primary.opacity(0.07)
    static let fillStrong = Color.primary.opacity(0.12)
    static let separator = Color.primary.opacity(0.09)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.30, green: 0.58, blue: 1.0), Color(red: 0.56, green: 0.40, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func batteryColors(_ battery: HIDPPDevice.Battery?) -> [Color] {
        guard let battery else { return [.gray, .gray] }
        if battery.charging || battery.percent > 30 {
            return [Color(red: 0.20, green: 0.84, blue: 0.62), Color(red: 0.42, green: 0.90, blue: 0.36)]
        }
        if battery.percent > 15 {
            return [Color(red: 1.0, green: 0.62, blue: 0.20), Color(red: 1.0, green: 0.80, blue: 0.30)]
        }
        return [Color(red: 1.0, green: 0.30, blue: 0.35), Color(red: 1.0, green: 0.50, blue: 0.40)]
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// An MX-style mouse silhouette that fills up with the battery level.
struct BatteryMouse: View {
    let battery: HIDPPDevice.Battery?
    var size = CGSize(width: 46, height: 70)

    var body: some View {
        let colors = Theme.batteryColors(battery)
        let level = CGFloat(battery?.percent ?? 0) / 100
        let body = RoundedRectangle(cornerRadius: size.width * 0.48, style: .continuous)
        ZStack {
            body.fill(Theme.fill)
            // Liquid fill, clipped to the mouse shape.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
                    .frame(height: size.height * level)
            }
            .clipShape(body)
            // Button split and scroll wheel.
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 1, height: size.height * 0.30)
                .offset(y: -size.height * 0.33)
            Capsule()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 5, height: 11)
                .offset(y: -size.height * 0.30)
            body.stroke(Color.primary.opacity(0.22), lineWidth: 1.2)
            if battery?.charging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(y: size.height * 0.12)
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: colors[0].opacity(battery == nil ? 0 : 0.45), radius: 12, y: 2)
        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: battery?.percent)
    }
}

/// A Control Center-style square: round icon, title and current value. Tapping toggles it.
struct Tile: View {
    let symbol: String
    let title: String
    let value: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
                    .frame(width: 30, height: 30)
                    .background {
                        Circle().fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.fillStrong))
                    }
                    .shadow(color: Color(red: 0.4, green: 0.5, blue: 1.0).opacity(isOn ? 0.45 : 0), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(value).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .animation(.snappy(duration: 0.25), value: isOn)
    }
}

/// A chunky Control Center-style slider with an icon inside the track.
/// `onCommit` fires when the drag ends.
struct PillSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let symbol: String
    var onCommit: (Double) -> Void = { _ in }

    private let height: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: height + fraction * (width - height))
                Circle()
                    .fill(.white)
                    .frame(width: height - 6, height: height - 6)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: 3 + fraction * (width - height))
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.50, blue: 1.0))
                    .frame(width: height - 6)
                    .offset(x: 3 + fraction * (width - height))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in value = snapped(drag.location.x, width: width) }
                    .onEnded { _ in onCommit(value) })
        }
        .frame(height: height)
    }

    private func snapped(_ x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max((x - height / 2) / max(width - height, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
    }
}
