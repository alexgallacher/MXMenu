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
        VStack(spacing: 0) {
            BatteryStrip()
            VStack(alignment: .leading, spacing: 12) {
                TopBar()
                VStack(alignment: .leading, spacing: 10) {
                    DeviceHeading()
                    if mouse.state == .connected {
                        if mouse.dpi != nil { PointerCard(ui: ui) }
                        if mouse.wheel != nil || mouse.wheelReversed != nil { ScrollingCard(ui: ui) }
                    } else {
                        ConnectCard()
                    }
                    ButtonsCard()
                    GeneralCard(ui: ui)
                    Notes()
                    FooterButtons()
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
            }
            .padding(12)
        }
        .frame(width: 340)
        .background(Theme.background)
        .onReceive(mouse.$dpi) { if let dpi = $0 { ui.dpi = Double(dpi) } }
        .onReceive(mouse.$wheel) { wheel in
            if let wheel, wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                ui.threshold = Double(wheel.autoDisengage)
            }
        }
    }
}

// MARK: - Top

/// Thin bar along the top edge showing the battery level.
private struct BatteryStrip: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        GeometryReader { geo in
            let battery = mouse.state == .connected ? mouse.battery : nil
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track.opacity(0.6))
                Rectangle()
                    .fill(battery.map(Battery.color) ?? Theme.track)
                    .frame(width: geo.size.width * CGFloat(battery?.percent ?? 0) / 100)
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.6), value: mouse.battery?.percent)
    }
}

private struct TopBar: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
            Text("MXMenu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.blue)
            Spacer()
            if mouse.state == .connected, let battery = mouse.battery {
                Chip(label: "Battery", value: "\(battery.percent)%", tone: Battery.tone(battery))
            }
        }
    }
}

private struct DeviceHeading: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        let connected = mouse.state == .connected
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Tag(text: connected ? mouse.connection : (mouse.state == .searching ? "Searching" : "Not connected"),
                    tone: connected ? .blue : .red)
                Spacer()
                if connected, let battery = mouse.battery {
                    if battery.charging {
                        Tag(text: "Charging", tone: .green, symbol: "bolt.fill")
                    } else if Battery.isLow(battery) {
                        Tag(text: "Low battery", tone: .red, symbol: "asterisk")
                    }
                }
            }
            Text(connected ? mouse.name : "Connect your MX Master")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var subtitle: String {
        switch mouse.state {
        case .connected:
            guard let battery = mouse.battery else { return "Changes apply straight to the mouse." }
            return "Battery at \(battery.percent)%. Changes apply straight to the mouse."
        case .searching:
            return "Looking for your mouse over Bluetooth and Logi Bolt."
        case .notFound:
            return "Turn it on and pair it with this Mac, or plug in its Logi Bolt receiver."
        }
    }
}

// MARK: - Settings

private struct PointerCard: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        RowCard {
            HStack {
                RowTitle(title: "Pointer speed", symbol: "cursorarrow")
                Spacer()
                Tag(text: "\(Int(ui.dpi).formatted()) DPI")
            }
            LineSlider(value: $ui.dpi, range: 200...8000, step: 50) { mouse.setDPI(Int($0)) }
        }
    }
}

private struct ScrollingCard: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        RowCard {
            if let wheel = mouse.wheel {
                let smartShiftOn = wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff
                Toggle(isOn: Binding(
                    get: { wheel.freeSpin },
                    set: { mouse.setWheel(.init(freeSpin: $0, autoDisengage: wheel.autoDisengage)) })
                ) { RowTitle(title: "Free spin", symbol: "wind") }

                Toggle(isOn: Binding(
                    get: { smartShiftOn },
                    set: { on in
                        let value = on ? UInt8(ui.threshold) : HIDPPDevice.WheelSettings.smartShiftOff
                        mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: value))
                    })
                ) { RowTitle(title: "SmartShift", symbol: "bolt") }

                if smartShiftOn {
                    HStack(spacing: 10) {
                        Text("Sensitivity").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        LineSlider(value: $ui.threshold, range: 1...50) {
                            mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: UInt8($0)))
                        }
                    }
                    .padding(.leading, 24)
                }
            }
            if let reversed = mouse.wheelReversed {
                Toggle(isOn: Binding(get: { reversed }, set: mouse.setWheelReversed)) {
                    RowTitle(title: "Reverse direction", symbol: "arrow.up.arrow.down")
                }
            }
        }
        .toggleStyle(BlueSwitchStyle())
    }
}

private struct ConnectCard: View {
    var body: some View {
        HStack {
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            } label: {
                Label("Open Bluetooth Settings", systemImage: "plus.circle")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(SoftButtonStyle())
            Spacer()
        }
    }
}

private struct ButtonsCard: View {
    @EnvironmentObject private var buttons: ButtonRemapper

    var body: some View {
        RowCard {
            ForEach(MouseButton.allCases) { button in
                HStack {
                    RowTitle(title: button.title, symbol: button.symbol)
                    Spacer(minLength: 8)
                    ActionPicker(button: button)
                }
            }
        }
    }
}

private struct GeneralCard: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var updater: Updater
    @ObservedObject var ui: PanelState

    var body: some View {
        RowCard {
            Toggle(isOn: Binding(get: { ui.launchAtLogin }, set: setLaunchAtLogin)) {
                RowTitle(title: "Launch at login", symbol: "power")
            }
            Toggle(isOn: Binding(get: { updater.autoInstall }, set: { updater.autoInstall = $0 })) {
                RowTitle(title: "Install updates automatically", symbol: "arrow.down.circle")
            }
        }
        .toggleStyle(BlueSwitchStyle())
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            mouse.lastError = "Launch at login only works from the installed app."
        }
        ui.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Bottom

private struct Notes: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var buttons: ButtonRemapper

    var body: some View {
        VStack(spacing: 3) {
            Text("Changes save automatically.")
                .foregroundStyle(Theme.muted)
            if !buttons.accessibilityGranted && buttons.actions.values.contains(where: { $0 != .unchanged }) {
                Button("Allow Accessibility in System Settings so button actions work.") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.orange)
            }
            if let error = mouse.lastError {
                Text(error).foregroundStyle(Theme.orange)
            }
        }
        .font(.system(size: 11))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

private struct FooterButtons: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        HStack {
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "arrow.left")
            }
            .buttonStyle(GhostButtonStyle())
            .keyboardShortcut("q")
            Spacer()
            updateButton
        }
    }

    @ViewBuilder private var updateButton: some View {
        switch updater.state {
        case .available(let version):
            Button { Task { await updater.install() } } label: {
                Label("Install \(version)", systemImage: "checkmark").labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(PrimaryButtonStyle())
        case .installing(let version):
            Button {} label: { Text("Installing \(version)…") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
        case .checking:
            Button {} label: { Text("Checking…") }
                .buttonStyle(SoftButtonStyle())
                .disabled(true)
        case .upToDate:
            Button { Task { await updater.check() } } label: {
                Label("Up to date", systemImage: "checkmark").labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(SoftButtonStyle())
        case .idle, .failed:
            Button { Task { await updater.check() } } label: {
                Label("Check for updates", systemImage: "arrow.clockwise").labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(SoftButtonStyle())
        }
    }
}

/// Title first, icon after it ("Next ✓", "Add new ⊕").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .semibold))
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
                Text(action.title).font(.system(size: 12)).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Theme.muted)
    }
}
