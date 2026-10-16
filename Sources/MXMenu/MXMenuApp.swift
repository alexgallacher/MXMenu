import SwiftUI

@main
struct MXMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var mouse: MouseController
    @StateObject private var buttons: ButtonRemapper
    @StateObject private var updater: Updater

    init() {
        let mouse = MouseController()
        let buttons = ButtonRemapper()
        mouse.gestureEnabled = buttons.gestureEnabled
        mouse.onGesturePress = { [weak buttons] in buttons?.performGesture() }
        buttons.onGestureMappingChanged = { [weak mouse] enabled in mouse?.gestureEnabled = enabled }
        _mouse = StateObject(wrappedValue: mouse)
        _buttons = StateObject(wrappedValue: buttons)
        let updater = Updater()
        updater.start()
        _updater = StateObject(wrappedValue: updater)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(mouse)
                .environmentObject(buttons)
                .environmentObject(updater)
        } label: {
            MenuBarLabel(mouse: mouse)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when run straight from Xcode / `swift run`.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var mouse: MouseController

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: mouse.state == .connected ? "computermouse.fill" : "computermouse")
            if let battery = mouse.battery {
                Text("\(battery.percent)%")
            }
        }
    }
}
