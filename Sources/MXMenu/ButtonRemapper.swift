import AppKit
import ApplicationServices

enum MouseButton: String, CaseIterable, Identifiable {
    case middle, back, forward, gesture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .middle: return "Middle"
        case .back: return "Back"
        case .forward: return "Forward"
        case .gesture: return "Gesture"
        }
    }

    var symbol: String {
        switch self {
        case .middle: return "circle.circle"
        case .back: return "arrow.backward"
        case .forward: return "arrow.forward"
        case .gesture: return "hand.draw"
        }
    }

    /// CGEvent button number. The gesture button isn't a normal mouse button; it comes in over HID++.
    var cgButtonNumber: Int64? {
        switch self {
        case .middle: return 2
        case .back: return 3
        case .forward: return 4
        case .gesture: return nil
        }
    }
}

enum MouseAction: String, CaseIterable, Identifiable {
    case unchanged, missionControl, appExpose, showDesktop, previousSpace, nextSpace
    case back, forward, playPause, screenshot, copy, paste, undo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unchanged: return "Default"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .previousSpace: return "Previous Desktop"
        case .nextSpace: return "Next Desktop"
        case .back: return "Back"
        case .forward: return "Forward"
        case .playPause: return "Play / Pause"
        case .screenshot: return "Screenshot"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .undo: return "Undo"
        }
    }

    var symbol: String {
        switch self {
        case .unchanged: return "computermouse"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "rectangle.stack"
        case .showDesktop: return "menubar.dock.rectangle"
        case .previousSpace: return "chevron.left.2"
        case .nextSpace: return "chevron.right.2"
        case .back: return "arrow.uturn.backward"
        case .forward: return "arrow.uturn.forward"
        case .playPause: return "playpause"
        case .screenshot: return "camera.viewfinder"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .undo: return "arrow.counterclockwise"
        }
    }

    func perform() {
        let arrow: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
        switch self {
        case .unchanged: break
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .appExpose: postKey(125, arrow.union(.maskControl))
        case .showDesktop: postKey(103, [.maskSecondaryFn])
        case .previousSpace: postKey(123, arrow.union(.maskControl))
        case .nextSpace: postKey(124, arrow.union(.maskControl))
        case .back: postKey(33, .maskCommand)
        case .forward: postKey(30, .maskCommand)
        case .playPause: postMediaKey(16)
        case .screenshot: postKey(21, [.maskCommand, .maskShift])
        case .copy: postKey(8, .maskCommand)
        case .paste: postKey(9, .maskCommand)
        case .undo: postKey(6, .maskCommand)
        }
    }

    private func postKey(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func postMediaKey(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (key << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// Remaps middle/back/forward with an event tap, and runs the gesture button's action.
/// Needs Accessibility permission, which is only requested once something is remapped.
@MainActor
final class ButtonRemapper: ObservableObject {
    @Published private(set) var actions: [MouseButton: MouseAction] = [:]
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()

    var onGestureMappingChanged: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var trustTimer: Timer?

    init() {
        for button in MouseButton.allCases {
            let raw = UserDefaults.standard.string(forKey: "action.\(button.rawValue)") ?? ""
            actions[button] = MouseAction(rawValue: raw) ?? .unchanged
        }
        startIfNeeded(prompt: false)
    }

    /// Sample mappings for `--snapshot`; never touches permissions or event taps.
    init(demo: Void) {
        actions = [.middle: .missionControl, .back: .back, .forward: .forward, .gesture: .appExpose]
        accessibilityGranted = true
    }

    var gestureEnabled: Bool { actions[.gesture, default: .unchanged] != .unchanged }

    func action(for button: MouseButton) -> MouseAction { actions[button, default: .unchanged] }

    func setAction(_ action: MouseAction, for button: MouseButton) {
        actions[button] = action
        UserDefaults.standard.set(action.rawValue, forKey: "action.\(button.rawValue)")
        if button == .gesture { onGestureMappingChanged?(action != .unchanged) }
        startIfNeeded(prompt: true)
    }

    func performGesture() {
        action(for: .gesture).perform()
    }

    private func startIfNeeded(prompt: Bool) {
        guard actions.values.contains(where: { $0 != .unchanged }) else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        guard accessibilityGranted else {
            waitForTrust()
            return
        }
        installTap()
    }

    private func waitForTrust() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.trustTimer = nil
                self.accessibilityGranted = true
                self.installTap()
            }
        }
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let remapper = Unmanaged<ButtonRemapper>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { remapper.handle(type: type, event: event) }
            },
            userInfo: context)
        else {
            log.error("Couldn't create mouse event tap")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        guard let button = MouseButton.allCases.first(where: { $0.cgButtonNumber == number }),
              action(for: button) != .unchanged
        else { return Unmanaged.passUnretained(event) }
        if type == .otherMouseDown { action(for: button).perform() }
        return nil
    }
}
