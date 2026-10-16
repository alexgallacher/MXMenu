import AppKit
import SwiftUI

// See docs/DESIGN.md: a light, airy card layout with one blue accent, soft
// tinted tags, and thin-bordered rows. Every colour has a matching dark value.

extension Color {
    /// A colour that switches with the view's light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

enum Theme {
    static let background = Color(light: 0xFAFAFA, dark: 0x17171A)
    static let card = Color(light: 0xFFFFFF, dark: 0x202024)
    static let border = Color(light: 0xE5E7EB, dark: 0x303036)
    static let track = Color(light: 0xE5E7EB, dark: 0x38383F)
    static let text = Color(light: 0x111827, dark: 0xF4F4F5)
    static let muted = Color(light: 0x6B7280, dark: 0x9CA3AF)
    static let blue = Color(light: 0x2563EB, dark: 0x3B82F6)
    static let blueText = Color(light: 0x2563EB, dark: 0x8AB4FF)
    static let blueSoft = Color(light: 0xEFF4FF, dark: 0x1C2742)
    static let red = Color(light: 0xDC2626, dark: 0xF87171)
    static let redSoft = Color(light: 0xFEF2F2, dark: 0x3A1E21)
    static let green = Color(light: 0x16A34A, dark: 0x4ADE80)
    static let greenSoft = Color(light: 0xF0FDF4, dark: 0x163020)
    static let orange = Color(light: 0xD97706, dark: 0xFBBF24)
}

enum Tone {
    case blue, red, green

    var text: Color {
        switch self {
        case .blue: return Theme.blueText
        case .red: return Theme.red
        case .green: return Theme.green
        }
    }

    var fill: Color {
        switch self {
        case .blue: return Theme.blueSoft
        case .red: return Theme.redSoft
        case .green: return Theme.greenSoft
        }
    }
}

enum Battery {
    static func isLow(_ battery: HIDPPDevice.Battery) -> Bool { !battery.charging && battery.percent <= 20 }

    static func tone(_ battery: HIDPPDevice.Battery) -> Tone { isLow(battery) ? .red : .green }

    static func color(_ battery: HIDPPDevice.Battery) -> Color { isLow(battery) ? Theme.red : Theme.blue }
}

/// Small tinted label, like "Required" or a date range.
struct Tag: View {
    let text: String
    var tone: Tone = .blue
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(tone.text)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Bordered pill holding a label and a tinted value, as in a summary bar.
struct Chip: View {
    let label: String
    let value: String
    var tone: Tone = .blue

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
            Tag(text: value, tone: tone)
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border))
    }
}

/// White rounded rectangle with a hairline border.
struct RowCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border))
    }
}

/// Semibold row title with an optional thin line icon.
struct RowTitle: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 16)
            }
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
        }
    }
}

struct BlueSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Theme.blue : Theme.track)
                        .frame(width: 30, height: 17)
                    Circle()
                        .fill(.white)
                        .frame(width: 13, height: 13)
                        .padding(2)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A thin blue slider. `onCommit` fires when the drag ends.
struct LineSlider: View {
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
                Capsule().fill(Theme.blue).frame(width: max(4, knob / 2 + fraction * (width - knob)), height: 4)
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().stroke(Theme.blue, lineWidth: 2))
                    .frame(width: knob, height: knob)
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

/// Filled blue button with a trailing icon ("Next ✓").
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.blue.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Pale blue button ("Add new ⊕").
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.blueText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.blueSoft.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Outlined quiet button ("← Back").
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.background : Theme.card,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Theme.border))
    }
}
