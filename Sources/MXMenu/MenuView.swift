import ServiceManagement
import SwiftUI

// Local UI state lives in a small ObservableObject rather than `@State`, which
// needs SwiftUI's macro plugin that Command Line Tools-only setups lack.
final class PanelState: ObservableObject {
    @Published var dpi: Double = 1000
    @Published var threshold: Double = 30
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}

/// The menu bar item: a template mouse symbol with the battery percentage beside it.
struct MenuBarLabel: View {
    @ObservedObject var mouse: MouseController

    var body: some View {
        if let battery = mouse.battery, mouse.state == .connected {
            Text("\(Image(systemName: "computermouse")) \(battery.percent)%")
        } else {
            Image(systemName: "computermouse")
        }
    }
}

struct MenuView: View {
    @EnvironmentObject private var mouse: MouseController
    @StateObject private var ui = PanelState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header()
            GroupDivider()
            if mouse.state == .connected {
                if mouse.dpi != nil {
                    PointerGroup(ui: ui)
                    GroupDivider()
                }
                if mouse.wheel != nil || mouse.wheelReversed != nil {
                    ScrollingGroup(ui: ui)
                    GroupDivider()
                }
            } else {
                NotConnectedGroup(searching: mouse.state == .searching)
                GroupDivider()
            }
            ButtonsGroup()
            GroupDivider()
            AppGroup(ui: ui)
        }
        .padding(.vertical, 8)
        .frame(width: 300)
        .onReceive(mouse.$dpi) { if let dpi = $0 { ui.dpi = Double(dpi) } }
        .onReceive(mouse.$wheel) { wheel in
            if let wheel, wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                ui.threshold = Double(wheel.autoDisengage)
            }
        }
    }
}

// MARK: - Header

private struct Header: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        let connected = mouse.state == .connected
        HStack(spacing: 9) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(connected ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(connected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
            VStack(alignment: .leading, spacing: 0) {
                Text(mouse.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if connected, let battery = mouse.battery {
                HStack(spacing: 5) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: Battery.symbol(battery))
                        .font(.system(size: 15))
                        .foregroundStyle(Battery.tint(battery))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var subtitle: String {
        switch mouse.state {
        case .connected:
            return mouse.battery?.charging == true ? "\(mouse.connection) · Charging" : mouse.connection
        case .searching: return "Searching…"
        case .notFound: return "Not Connected"
        }
    }
}

// MARK: - Pointer speed

private struct PointerGroup: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                GroupHeading("Pointer Speed")
                Spacer()
                Text("\(Int(ui.dpi).formatted()) DPI")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
                    .padding(.bottom, 2)
            }
            HStack(spacing: 8) {
                Image(systemName: "tortoise.fill")
                Slider(value: $ui.dpi, in: 200...8000, step: 50) { editing in
                    if !editing { mouse.setDPI(Int(ui.dpi)) }
                }
                Image(systemName: "hare.fill")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Scrolling

private struct ScrollingGroup: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GroupHeading("Scrolling")
            if let wheel = mouse.wheel {
                let smartShiftOn = wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff
                SettingRow("SmartShift", symbol: "bolt.fill", isOn: smartShiftOn) {
                    Toggle("SmartShift", isOn: Binding(
                        get: { smartShiftOn },
                        set: { on in
                            let value = on ? UInt8(ui.threshold) : HIDPPDevice.WheelSettings.smartShiftOff
                            mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: value))
                        }))
                }
                if smartShiftOn {
                    HStack(spacing: 8) {
                        Text("Sensitivity").font(.system(size: 11)).foregroundStyle(.secondary)
                        Slider(value: $ui.threshold, in: 1...50) { editing in
                            if !editing {
                                mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: UInt8(ui.threshold)))
                            }
                        }
                        .controlSize(.mini)
                    }
                    .padding(.leading, 49)
                    .padding(.trailing, 14)
                    .padding(.bottom, 2)
                }
                SettingRow("Free Spin", symbol: "wind", isOn: wheel.freeSpin) {
                    Toggle("Free Spin", isOn: Binding(
                        get: { wheel.freeSpin },
                        set: { mouse.setWheel(.init(freeSpin: $0, autoDisengage: wheel.autoDisengage)) }))
                }
            }
            if let reversed = mouse.wheelReversed {
                SettingRow("Reverse Direction", symbol: "arrow.up.arrow.down", isOn: reversed) {
                    Toggle("Reverse Direction", isOn: Binding(get: { reversed }, set: mouse.setWheelReversed))
                }
            }
        }
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(.mini)
    }
}

// MARK: - Not connected

private struct NotConnectedGroup: View {
    let searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(searching ? "Looking for your MX Master…" : "Turn on your MX Master and pair it with this Mac, or plug in its Logi Bolt receiver.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
            MenuItemRow(title: "Bluetooth Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            }
        }
    }
}

// MARK: - Buttons

private struct ButtonsGroup: View {
    @EnvironmentObject private var buttons: ButtonRemapper

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GroupHeading("Buttons")
            ForEach(MouseButton.allCases) { button in
                SettingRow(button.title, symbol: button.symbol, isOn: buttons.action(for: button) != .unchanged) {
                    ActionPicker(button: button)
                }
            }
            if !buttons.accessibilityGranted && buttons.actions.values.contains(where: { $0 != .unchanged }) {
                MenuItemRow(title: "Allow Accessibility for Button Actions…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }
}

// MARK: - App

private struct AppGroup: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var updater: Updater
    @ObservedObject var ui: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = mouse.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            SettingRow("Launch at Login") {
                Toggle("Launch at Login", isOn: Binding(get: { ui.launchAtLogin }, set: setLaunchAtLogin))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .padding(.bottom, 2)
            UpdateRow()
            MenuItemRow(title: "Quit MXMenu", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            mouse.lastError = "Launch at Login only works from the installed app."
        }
        ui.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct UpdateRow: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.state {
        case .available(let version):
            MenuItemRow(title: "Install MXMenu \(version)…") { Task { await updater.install() } }
        case .installing(let version):
            SettingRow("Installing \(version)…") { ProgressView().controlSize(.mini) }
        case .checking:
            SettingRow("Checking for Updates…") { ProgressView().controlSize(.mini) }
        case .upToDate:
            MenuItemRow(title: "MXMenu \(updater.currentVersion) Is Up to Date") { Task { await updater.check() } }
        case .failed:
            MenuItemRow(title: "Couldn't Check for Updates. Try Again…") { Task { await updater.check() } }
        case .idle:
            MenuItemRow(title: "Check for Updates…") { Task { await updater.check() } }
        }
    }
}

private struct ActionPicker: View {
    @EnvironmentObject private var buttons: ButtonRemapper
    let button: MouseButton

    var body: some View {
        let action = buttons.action(for: button)
        HStack(spacing: 4) {
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
                    Text(action.title).font(.system(size: 13)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }
}
