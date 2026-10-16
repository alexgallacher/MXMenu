import ServiceManagement
import SwiftUI

// Local UI state lives in a small ObservableObject rather than `@State`, which
// needs SwiftUI's macro plugin that Command Line Tools-only setups lack.
final class PanelState: ObservableObject {
    @Published var dpi: Double = 1000
    @Published var threshold: Double = 30
}

/// The menu bar item: the mouse with its battery percentage beside it.
struct MenuBarLabel: View {
    @ObservedObject var mouse: MouseController

    var body: some View {
        if let battery = mouse.battery, mouse.state == .connected {
            Text("\(Image(systemName: "computermouse.fill")) \(battery.percent)%")
        } else {
            Image(systemName: "computermouse")
        }
    }
}

struct MenuView: View {
    @EnvironmentObject private var mouse: MouseController
    @StateObject private var ui = PanelState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Hero()
            if mouse.state == .connected {
                if mouse.dpi != nil { PointerSection(ui: ui) }
                if mouse.wheel != nil || mouse.wheelReversed != nil { WheelSection(ui: ui) }
            }
            ButtonsSection()
            Footer()
        }
        .padding(14)
        .frame(width: 316)
        .background(alignment: .top) {
            RadialGradient(colors: [Color(red: 0.40, green: 0.45, blue: 1.0).opacity(0.16), .clear],
                           center: .top, startRadius: 0, endRadius: 240)
                .frame(height: 260)
                .allowsHitTesting(false)
        }
        .onReceive(mouse.$dpi) { if let dpi = $0 { ui.dpi = Double(dpi) } }
        .onReceive(mouse.$wheel) { wheel in
            if let wheel, wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                ui.threshold = Double(wheel.autoDisengage)
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }
}

// MARK: - Hero

private struct Hero: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        let connected = mouse.state == .connected
        let tint = Theme.batteryColors(connected ? mouse.battery : nil)[0]
        HStack(spacing: 16) {
            BatteryMouse(battery: connected ? mouse.battery : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(mouse.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if connected, let battery = mouse.battery {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(battery.percent)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .animation(.easeOut, value: battery.percent)
                } else {
                    Text(mouse.state == .searching ? "Searching…" : "Not connected")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .padding(.vertical, 4)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(connected ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                        .shadow(color: connected ? Color.green.opacity(0.8) : .clear, radius: 3)
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(connected ? 0.16 : 0.05), Theme.fill.opacity(0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.07)))
        if !connected {
            NotConnectedHelp(searching: mouse.state == .searching)
        }
    }

    private var status: String {
        switch mouse.state {
        case .connected:
            return mouse.battery?.charging == true ? "\(mouse.connection) · Charging" : mouse.connection
        case .searching: return "Looking for your mouse"
        case .notFound: return "Turned off or not paired"
        }
    }
}

private struct NotConnectedHelp: View {
    let searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn on your MX Master and pair it with this Mac, or plug in its Logi Bolt receiver.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            } label: {
                Text("Open Bluetooth Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.accentGradient, in: Capsule())
                    .shadow(color: Color(red: 0.4, green: 0.5, blue: 1.0).opacity(0.4), radius: 8, y: 2)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

// MARK: - Pointer speed

private struct PointerSection: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Pointer speed", detail: "\(Int(ui.dpi)) DPI")
            PillSlider(value: $ui.dpi, range: 200...8000, step: 50, symbol: "cursorarrow") { mouse.setDPI(Int($0)) }
        }
    }
}

// MARK: - Scroll wheel

private struct WheelSection: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        let wheel = mouse.wheel
        let smartShiftOn = wheel.map { $0.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff } ?? false
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Scrolling")
            HStack(spacing: 8) {
                if let wheel {
                    Tile(symbol: wheel.freeSpin ? "wind" : "dial.medium",
                         title: "Wheel", value: wheel.freeSpin ? "Free spin" : "Ratchet",
                         isOn: wheel.freeSpin) {
                        mouse.setWheel(.init(freeSpin: !wheel.freeSpin, autoDisengage: wheel.autoDisengage))
                    }
                    Tile(symbol: "bolt.fill", title: "SmartShift", value: smartShiftOn ? "On" : "Off", isOn: smartShiftOn) {
                        let value = smartShiftOn ? HIDPPDevice.WheelSettings.smartShiftOff : UInt8(ui.threshold)
                        mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: value))
                    }
                }
                if let reversed = mouse.wheelReversed {
                    Tile(symbol: "arrow.up.arrow.down", title: "Direction", value: reversed ? "Reversed" : "Standard",
                         isOn: reversed) {
                        mouse.setWheelReversed(!reversed)
                    }
                }
            }
            if let wheel, smartShiftOn {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: "SmartShift sensitivity")
                        .font(.system(size: 11))
                    PillSlider(value: $ui.threshold, range: 1...50, symbol: "bolt.fill") {
                        mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: UInt8($0)))
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Buttons

private struct ButtonsSection: View {
    @EnvironmentObject private var buttons: ButtonRemapper

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Buttons")
            VStack(spacing: 0) {
                ForEach(Array(MouseButton.allCases.enumerated()), id: \.element) { index, button in
                    if index > 0 {
                        Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 40)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: button.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(button.title).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 8)
                        ActionPicker(button: button)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !buttons.accessibilityGranted && buttons.actions.values.contains(where: { $0 != .unchanged }) {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                } label: {
                    Label("Allow Accessibility so button actions work…", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ActionPicker: View {
    @EnvironmentObject private var buttons: ButtonRemapper
    let button: MouseButton

    var body: some View {
        let action = buttons.action(for: button)
        HStack(spacing: 4) {
            if Snapshot.isActive {
                Text(action.title).font(.system(size: 12)).lineLimit(1).fixedSize()
            } else {
                Menu {
                    ForEach(MouseAction.allCases) { option in
                        Button {
                            buttons.setAction(option, for: button)
                        } label: {
                            Label(option.title, systemImage: option.symbol)
                        }
                        if option == .unchanged { Divider() }
                    }
                } label: {
                    Text(action.title).font(.system(size: 12)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Footer

private struct Footer: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            UpdateBanner()
            if let error = mouse.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Text("MXMenu \(updater.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    Task { await mouse.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                if Snapshot.isActive {
                    Image(systemName: "ellipsis.circle")
                } else {
                    SettingsMenu()
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsMenu: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Menu {
            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: setLaunchAtLogin))
            Divider()
            Button("Check for Updates…") { Task { await updater.check() } }
            Toggle("Install Updates Automatically", isOn: Binding(
                get: { updater.autoInstall },
                set: { updater.autoInstall = $0 }))
            Divider()
            Button("Quit MXMenu") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            mouse.lastError = "Launch at login only works from the installed app: \(error.localizedDescription)"
        }
    }
}

private struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.state {
        case .available(let version):
            HStack {
                Text("MXMenu \(version) is available").font(.system(size: 11))
                Spacer()
                Button("Install") { Task { await updater.install() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        case .installing(let version):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Installing \(version)…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .upToDate:
            Text("You're up to date.").font(.system(size: 11)).foregroundStyle(.secondary)
        case .failed(let message):
            Text("Update check failed: \(message)").font(.system(size: 11)).foregroundStyle(.secondary)
        case .idle, .checking:
            EmptyView()
        }
    }
}
