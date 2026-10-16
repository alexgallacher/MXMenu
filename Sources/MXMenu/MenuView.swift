import ServiceManagement
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var mouse: MouseController
    @EnvironmentObject private var buttons: ButtonRemapper
    @EnvironmentObject private var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var threshold: Double = 30

    private static let dpiPresets = [400, 800, 1000, 1200, 1600, 2000, 3200, 4000, 8000]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            switch mouse.state {
            case .connected:
                pointerSection
                wheelSection
            case .searching:
                Text("Looking for your MX Master…").foregroundStyle(.secondary)
            case .notFound:
                Text("No MX Master found. Make sure it's switched on and paired over Bluetooth or a Logi Bolt receiver, and quit Logi Options+ if it's running.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            buttonsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 310)
        .onAppear {
            if let autoDisengage = mouse.wheel?.autoDisengage, autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                threshold = Double(autoDisengage)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse.fill").font(.title2)
            VStack(alignment: .leading) {
                Text(mouse.name).font(.headline)
                if !mouse.connection.isEmpty {
                    Text(mouse.connection).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let battery = mouse.battery {
                Label("\(battery.percent)%", systemImage: batterySymbol(battery))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(battery.percent <= 15 && !battery.charging ? .red : .primary)
            }
        }
    }

    @ViewBuilder private var pointerSection: some View {
        if let dpi = mouse.dpi {
            Picker("Pointer speed", selection: Binding(get: { dpi }, set: mouse.setDPI)) {
                ForEach((Self.dpiPresets + [dpi]).uniqued().sorted(), id: \.self) { Text("\($0) DPI").tag($0) }
            }
        }
    }

    @ViewBuilder private var wheelSection: some View {
        if let wheel = mouse.wheel {
            Picker("Scroll wheel", selection: Binding(
                get: { wheel.freeSpin },
                set: { mouse.setWheel(.init(freeSpin: $0, autoDisengage: wheel.autoDisengage)) })
            ) {
                Text("Ratchet").tag(false)
                Text("Free spin").tag(true)
            }
            .pickerStyle(.segmented)

            Toggle("SmartShift", isOn: Binding(
                get: { wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff },
                set: { on in
                    let value = on ? UInt8(threshold) : HIDPPDevice.WheelSettings.smartShiftOff
                    mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: value))
                }))
            if wheel.autoDisengage != HIDPPDevice.WheelSettings.smartShiftOff {
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $threshold, in: 1...50) { editing in
                        if !editing { mouse.setWheel(.init(freeSpin: wheel.freeSpin, autoDisengage: UInt8(threshold))) }
                    }
                    Text("Lower switches to free spin sooner").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if let reversed = mouse.wheelReversed {
            Toggle("Reverse scroll direction on this mouse", isOn: Binding(get: { reversed }, set: mouse.setWheelReversed))
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buttons").font(.subheadline.bold())
            ForEach(MouseButton.allCases) { button in
                Picker(button.title, selection: Binding(
                    get: { buttons.action(for: button) },
                    set: { buttons.setAction($0, for: button) })
                ) {
                    ForEach(MouseAction.allCases) { Text($0.title).tag($0) }
                }
            }
            if !buttons.accessibilityGranted && buttons.actions.values.contains(where: { $0 != .unchanged }) {
                Text("Button actions need Accessibility permission.").font(.caption).foregroundStyle(.orange)
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            updateStatus
            if let error = mouse.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Refresh") { Task { await mouse.refresh() } }
                Spacer()
                settingsMenu
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Text("MXMenu \(updater.currentVersion)")
            Button("Check for Updates…") { Task { await updater.check() } }
            Toggle("Install Updates Automatically", isOn: Binding(get: { updater.autoInstall }, set: { updater.autoInstall = $0 }))
            Divider()
            Button("Quit MXMenu") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.state {
        case .available(let version):
            HStack {
                Text("MXMenu \(version) is available").font(.caption)
                Spacer()
                Button("Install") { Task { await updater.install() } }
            }
        case .installing(let version):
            Text("Installing \(version)…").font(.caption).foregroundStyle(.secondary)
        case .upToDate:
            Text("You're up to date (\(updater.currentVersion))").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text("Update check failed: \(message)").font(.caption).foregroundStyle(.secondary)
        case .idle, .checking:
            EmptyView()
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            mouse.lastError = "Launch at login only works from the built .app: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func batterySymbol(_ battery: HIDPPDevice.Battery) -> String {
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

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { Array(Set(self)) }
}
