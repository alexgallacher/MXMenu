import ServiceManagement
import SwiftUI

// Local UI state lives in a small ObservableObject rather than `@State`, which
// needs SwiftUI's macro plugin that Command Line Tools-only setups lack.
final class PanelState: ObservableObject {
    @Published var dpi: Double = 1000
    @Published var threshold: Double = 30
}

struct MenuView: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var buttons: ButtonRemapper
    @EnvironmentObject private var updater: Updater
    @StateObject private var ui = PanelState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header()
            if mouse.state == .connected {
                PointerCard(ui: ui)
                WheelCard(ui: ui)
            } else {
                NotConnectedView(searching: mouse.state == .searching)
            }
            ButtonsCard()
            Footer()
        }
        .padding(16)
        .frame(width: 340)
        .background(background)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onReceive(mouse.$dpi) { if let dpi = $0 { ui.dpi = Double(dpi) } }
        .onReceive(mouse.$wheel) { wheel in
            if let wheel, wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                ui.threshold = Double(wheel.autoDisengage)
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(mouse.state == .connected ? 0.20 : 0.07), .clear],
                           center: UnitPoint(x: 0.2, y: 0.0), startRadius: 0, endRadius: 260)
                .animation(.easeInOut(duration: 0.8), value: mouse.state)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Header

private struct Header: View {
    @EnvironmentObject private var mouse: MouseController

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 44, height: 44)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 10, y: 3)
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mouse.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                statusPill
            }
            Spacer(minLength: 8)
            if mouse.state == .connected {
                BatteryRing(battery: mouse.battery)
            }
        }
    }

    private var statusPill: some View {
        let (color, symbol, text): (Color, String, String) = {
            switch mouse.state {
            case .connected:
                let receiver = mouse.connection.localizedCaseInsensitiveContains("receiver")
                return (Theme.good, receiver ? "cable.connector" : "dot.radiowaves.left.and.right", mouse.connection)
            case .searching: return (Theme.warn, "magnifyingglass", "Searching…")
            case .notFound: return (Theme.tertiary, "powersleep", "Not connected")
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.8), radius: 3)
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke))
    }
}

// MARK: - Pointer speed

private struct PointerCard: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    private static let presets = [800, 1200, 1600, 2400, 4000]

    var body: some View {
        if mouse.dpi != nil {
            Card("Pointer speed", symbol: "cursorarrow.motionlines") {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(ui.dpi))")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("DPI").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(speedName).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.tertiary)
                }
                GradientSlider(value: $ui.dpi, range: 200...8000, step: 50) { mouse.setDPI(Int($0)) }
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Chip(title: preset >= 1000 ? "\(preset / 100 / 10).\(preset / 100 % 10)k" : "\(preset)",
                             selected: Int(ui.dpi) == preset) {
                            withAnimation(.snappy) { ui.dpi = Double(preset) }
                            mouse.setDPI(preset)
                        }
                    }
                }
            }
        }
    }

    private var speedName: String {
        switch ui.dpi {
        case ..<900: return "Precise"
        case ..<2000: return "Balanced"
        case ..<4000: return "Fast"
        default: return "Very fast"
        }
    }
}

// MARK: - Scroll wheel

private struct WheelCard: View {
    @EnvironmentObject private var mouse: MouseController
    @ObservedObject var ui: PanelState

    var body: some View {
        if mouse.wheel != nil || mouse.wheelReversed != nil {
            Card("Scroll wheel", symbol: "arrow.up.and.down") {
                if let wheel = mouse.wheel {
                    SegmentedControl(
                        options: [SegmentOption(value: false, title: "Ratchet", symbol: "dial.medium"),
                                  SegmentOption(value: true, title: "Free spin", symbol: "wind")],
                        selection: wheel.freeSpin
                    ) { mouse.setWheel(.init(freeSpin: $0, autoDisengage: wheel.autoDisengage)) }

                    let smartShiftOn = wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff
                    Toggle(isOn: Binding(
                        get: { smartShiftOn },
                        set: { on in
                            let value = on ? UInt8(ui.threshold) : HIDPPDevice.WheelSettings.smartShiftOff
                            mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: value))
                        })
                    ) {
                        RowLabel(title: "SmartShift", detail: "Free spin kicks in when you scroll fast", symbol: "bolt.horizontal.fill")
                    }
                    .toggleStyle(SwitchToggleStyle())

                    if smartShiftOn {
                        VStack(spacing: 4) {
                            GradientSlider(value: $ui.threshold, range: 1...50) {
                                mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: UInt8($0)))
                            }
                            HStack {
                                Text("Shifts sooner")
                                Spacer()
                                Text("Shifts later")
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                        }
                        .padding(.leading, 36)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                if let reversed = mouse.wheelReversed {
                    Toggle(isOn: Binding(get: { reversed }, set: mouse.setWheelReversed)) {
                        RowLabel(title: "Reverse direction", detail: "Only this mouse; the trackpad stays as is", symbol: "arrow.up.arrow.down")
                    }
                    .toggleStyle(SwitchToggleStyle())
                }
            }
        }
    }
}

// MARK: - Buttons

private struct ButtonsCard: View {
    @EnvironmentObject private var buttons: ButtonRemapper

    var body: some View {
        Card("Buttons", symbol: "cursorarrow.click.2") {
            VStack(spacing: 8) {
                ForEach(MouseButton.allCases) { button in
                    HStack(spacing: 10) {
                        IconTile(symbol: button.symbol)
                        Text(button.title).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 8)
                        ActionPicker(button: button)
                    }
                }
            }
            if needsAccessibility {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield").foregroundStyle(Theme.warn)
                    Text("Allow Accessibility so button actions work.")
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Allow") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.warn.opacity(0.25), in: Capsule())
                }
                .padding(10)
                .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var needsAccessibility: Bool {
        !buttons.accessibilityGranted && buttons.actions.values.contains { $0 != .unchanged }
    }
}

private struct ActionPicker: View {
    @EnvironmentObject private var buttons: ButtonRemapper
    let button: MouseButton

    var body: some View {
        let action = buttons.action(for: button)
        HStack(spacing: 5) {
            Image(systemName: action.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(action == .unchanged ? Theme.tertiary : Theme.accent)
            if Snapshot.isActive {
                Text(action.title).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
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
                    Text(action.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        }
        .foregroundStyle(action == .unchanged ? Theme.secondary : Color.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.cardActive.opacity(action == .unchanged ? 0.5 : 1), in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke))
    }
}

// MARK: - Not connected

private struct NotConnectedView: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.10)).frame(width: 88, height: 88)
                Circle().stroke(Theme.accent.opacity(0.18), lineWidth: 1).frame(width: 110, height: 110)
                Image(systemName: "computermouse")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: searching)
            }
            .padding(.top, 6)
            Text(searching ? "Looking for your MX Master…" : "Your MX Master isn't connected")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Turn it on and pair it with this Mac over Bluetooth, or plug in its Logi Bolt receiver. Quit Logi Options+ so the two apps don't clash.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            } label: {
                Label("Open Bluetooth Settings", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.accentGradient, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.45), radius: 8, y: 2)
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }
}

// MARK: - Footer

private struct Footer: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var updater: Updater

    var body: some View {
        VStack(spacing: 8) {
            UpdateBanner()
            if let error = mouse.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Text("MXMenu \(updater.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Button {
                    Task { await mouse.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .help("Refresh")
                if Snapshot.isActive {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.secondary)
                } else {
                    SettingsMenu()
                }
            }
            .font(.system(size: 13))
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
            banner(symbol: "arrow.down.circle.fill", text: "MXMenu \(version) is available") {
                Button("Install") { Task { await updater.install() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accentGradient, in: Capsule())
            }
        case .installing(let version):
            banner(symbol: "arrow.triangle.2.circlepath", text: "Installing \(version)…") {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            banner(symbol: "checkmark.circle", text: "You're up to date") { EmptyView() }
        case .failed(let message):
            banner(symbol: "exclamationmark.triangle", text: "Update check failed: \(message)") { EmptyView() }
        case .idle, .checking:
            EmptyView()
        }
    }

    private func banner<Trailing: View>(symbol: String, text: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 11)).lineLimit(2)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
