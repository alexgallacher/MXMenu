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
        VStack(alignment: .leading, spacing: 0) {
            Header()
                .padding(.bottom, 12)
            if mouse.state == .connected {
                if mouse.dpi != nil {
                    Separator()
                    PointerSection(ui: ui)
                }
                if mouse.wheel != nil || mouse.wheelReversed != nil {
                    Separator()
                    WheelSection(ui: ui)
                }
            } else {
                Separator()
                NotConnectedSection(searching: mouse.state == .searching)
            }
            Separator()
            ButtonsSection()
            Separator()
            Footer()
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(width: 300)
        .onReceive(mouse.$dpi) { if let dpi = $0 { ui.dpi = Double(dpi) } }
        .onReceive(mouse.$wheel) { wheel in
            if let wheel, wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                ui.threshold = Double(wheel.autoDisengage)
            }
        }
    }
}

private struct Separator: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }
}

/// Small grey heading followed by its rows.
private struct PanelSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Header

private struct Header: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 15))
                .foregroundStyle(mouse.state == .connected ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .background(Theme.fill, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(mouse.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let battery = mouse.battery, mouse.state == .connected {
                HStack(spacing: 5) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Image(systemName: Theme.batterySymbol(battery))
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.batteryColor(battery))
                }
                .animation(.easeOut, value: battery.percent)
            }
        }
    }

    private var status: String {
        switch mouse.state {
        case .connected:
            return mouse.battery?.charging == true ? "\(mouse.connection) · Charging" : mouse.connection
        case .searching: return "Searching…"
        case .notFound: return "Not connected"
        }
    }
}

// MARK: - Pointer speed

private struct PointerSection: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        PanelSection("Pointer speed") {
            HStack(spacing: 10) {
                AccentSlider(value: $ui.dpi, range: 200...8000, step: 50) { mouse.setDPI(Int($0)) }
                Text("\(Int(ui.dpi)) DPI")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 66, alignment: .trailing)
            }
        }
    }
}

// MARK: - Scroll wheel

private struct WheelSection: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        PanelSection("Scrolling") {
            if let wheel = mouse.wheel {
                HStack {
                    Text("Wheel").font(.system(size: 12))
                    Spacer()
                    SegmentedControl(
                        options: [SegmentOption(value: false, title: "Ratchet"),
                                  SegmentOption(value: true, title: "Free spin")],
                        selection: wheel.freeSpin
                    ) { mouse.setWheel(.init(freeSpin: $0, autoDisengage: wheel.autoDisengage)) }
                    .frame(width: 150)
                }

                let smartShiftOn = wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff
                Toggle(isOn: Binding(
                    get: { smartShiftOn },
                    set: { on in
                        let value = on ? UInt8(ui.threshold) : HIDPPDevice.WheelSettings.smartShiftOff
                        mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: value))
                    })
                ) {
                    Text("SmartShift").font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .help("Switches to free spin when you scroll fast")

                if smartShiftOn {
                    HStack(spacing: 10) {
                        Text("Sensitivity").font(.system(size: 11)).foregroundStyle(.secondary)
                        AccentSlider(value: $ui.threshold, range: 1...50) {
                            mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: UInt8($0)))
                        }
                    }
                    .padding(.leading, 12)
                    .transition(.opacity)
                }
            }
            if let reversed = mouse.wheelReversed {
                Toggle(isOn: Binding(get: { reversed }, set: mouse.setWheelReversed)) {
                    Text("Reverse direction").font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .help("Only this mouse; the trackpad keeps its own setting")
            }
        }
    }
}

// MARK: - Buttons

private struct ButtonsSection: View {
    @EnvironmentObject private var buttons: ButtonRemapper

    var body: some View {
        PanelSection("Buttons") {
            ForEach(MouseButton.allCases) { button in
                HStack {
                    Text(button.title).font(.system(size: 12))
                    Spacer(minLength: 8)
                    ActionPicker(button: button)
                }
            }
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

// MARK: - Not connected

private struct NotConnectedSection: View {
    let searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(searching ? "Looking for your MX Master…" : "Turn on your MX Master and pair it with this Mac, or plug in its Logi Bolt receiver.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Bluetooth Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 11)
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
