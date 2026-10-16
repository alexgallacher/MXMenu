import SwiftUI

// See docs/DESIGN.md: native controls and system colours, laid out like
// macOS's own Bluetooth and Battery menus.

enum Battery {
    static func symbol(_ battery: HIDPPDevice.Battery) -> String {
        if battery.charging { return "battery.100percent.bolt" }
        switch battery.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Red when low, like the system Battery menu; otherwise the normal label colour.
    static func tint(_ battery: HIDPPDevice.Battery) -> Color {
        !battery.charging && battery.percent <= 20 ? .red : .primary
    }
}

/// Small heading above a group, as in the system menus.
struct GroupHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 2)
    }
}

struct GroupDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 5)
    }
}

/// Tracks the pointer for one row (an ObservableObject rather than `@State`; see MenuView.swift).
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// A clickable row that highlights on hover like a real menu item.
struct MenuItemRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(hover.isHovering ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(hover.isHovering ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if hover.isHovering {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .onHover { hover.isHovering = $0 }
    }
}

/// A settings row: optional round icon, a label, and a native control on the right.
struct SettingRow<Control: View>: View {
    var symbol: String?
    var isOn = false
    let title: String
    let control: Control

    init(_ title: String, symbol: String? = nil, isOn: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 9) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
            }
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}
