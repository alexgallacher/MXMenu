import AppKit
import SwiftUI

/// `MXMenu --snapshot <file.png> [--disconnected] [--light]` renders the panel with sample data and exits.
/// It draws through a real NSHostingView so native controls (switches, sliders, pop-ups) appear
/// as they do in the app. CI uses it to produce screenshots without a mouse attached.
enum Snapshot {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let appearance = NSAppearance(named: args.contains("--light") ? .aqua : .darkAqua)!
        _ = NSApplication.shared

        // The real panel sits on the menu's translucent material; stand in with the window colour.
        let root = MenuView()
            .environmentObject(MouseController(demoConnected: !args.contains("--disconnected")))
            .environmentObject(ButtonRemapper(demo: ()))
            .environmentObject(Updater())
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        // Render at 2x regardless of the machine's display.
        let bounds = host.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { exit(1) }
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        exit(0)
    }
}
