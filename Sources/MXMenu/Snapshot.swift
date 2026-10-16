import AppKit
import SwiftUI

/// `MXMenu --snapshot <file.png> [--disconnected] [--light]` renders the panel with sample data and exits.
/// CI uses it to produce screenshots of the design without a mouse attached.
enum Snapshot {
    /// True while rendering (AppKit menus can't be drawn offscreen, so views show a stand-in).
    static var isActive = false

    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        isActive = true
        let light = args.contains("--light")
        // The real panel sits on the menu's translucent material; stand in with a flat colour.
        let view = MenuView()
            .environmentObject(MouseController(demoConnected: !args.contains("--disconnected")))
            .environmentObject(ButtonRemapper(demo: ()))
            .environmentObject(Updater())
            .background(light ? Color(white: 0.95) : Color(white: 0.17))
            .environment(\.colorScheme, light ? .light : .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        exit(0)
    }
}
