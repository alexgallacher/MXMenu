import Foundation
import IOKit.hid

/// Finds the MX Master over Bluetooth or a Logi Bolt receiver and exposes its state to the UI.
@MainActor
final class MouseController: ObservableObject {
    enum State: Equatable { case searching, connected, notFound }

    /// Thumb gesture button on MX Master 3/3S/4.
    static let gestureCID: UInt16 = 0x00C3

    @Published private(set) var state: State = .searching
    @Published private(set) var name = "MX Master"
    @Published private(set) var connection = ""
    @Published private(set) var battery: HIDPPDevice.Battery?
    @Published private(set) var dpi: Int?
    @Published private(set) var wheel: HIDPPDevice.WheelSettings?
    @Published private(set) var wheelReversed: Bool?
    @Published var lastError: String?

    var onGesturePress: (() -> Void)?
    var gestureEnabled = false {
        didSet { Task { await applyGestureDiversion() } }
    }

    private let manager: IOHIDManager
    private var transports: [HIDPPTransport] = []
    private var mouse: HIDPPDevice?
    private var gestureDown = false
    private var pollTimer: Timer?

    private enum Keys {
        static let dpi = "mouse.dpi"
        static let freeSpin = "mouse.freeSpin"
        static let autoDisengage = "mouse.autoDisengage"
        static let reversed = "mouse.reversed"
    }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // HID++ lives on vendor usage page 0xFF00 (receivers) or 0xFF43 (Bluetooth).
        let matching = [0xFF00, 0xFF43].map {
            [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsagePageKey: $0] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let controller = Unmanaged<MouseController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.attach(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let controller = Unmanaged<MouseController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.detach(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBattery() }
        }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if mouse == nil { state = .notFound }
        }
    }

    // MARK: Discovery

    private func attach(_ hid: IOHIDDevice) {
        guard !transports.contains(where: { $0.hid === hid }) else { return }
        let transport = HIDPPTransport(hid: hid)
        guard transport.open() else {
            log.error("Couldn't open Logitech HID interface")
            return
        }
        transports.append(transport)
        transport.onNotification = { [weak self, weak transport] report in
            guard let self, let transport else { return }
            self.handleNotification(report, from: transport)
        }
        Task { await discover(on: transport) }
    }

    private func detach(_ hid: IOHIDDevice) {
        guard let i = transports.firstIndex(where: { $0.hid === hid }) else { return }
        let transport = transports.remove(at: i)
        transport.close()
        if mouse?.transport === transport { forgetMouse() }
    }

    private func discover(on transport: HIDPPTransport) async {
        let indexes: [UInt8] = transport.isReceiver ? Array(1...6) : [0xFF]
        for index in indexes {
            let device = HIDPPDevice(transport: transport, index: index)
            guard let name = try? await device.name() else { continue }
            log.info("Found \(name) on \(transport.transportName), index \(index)")
            let isMXMaster = name.localizedCaseInsensitiveContains("MX Master")
            if isMXMaster || (mouse == nil && (await device.supports(.adjustableDPI))) {
                await use(device, name: name)
                if isMXMaster { return }
            }
        }
    }

    private func use(_ device: HIDPPDevice, name: String) async {
        mouse = device
        self.name = name
        connection = device.transport.transportName
        state = .connected
        await refresh()
        await device.logControls()
    }

    private func forgetMouse() {
        mouse = nil
        battery = nil
        dpi = nil
        wheel = nil
        wheelReversed = nil
        gestureDown = false
        state = .notFound
    }

    // MARK: Reading state

    func refresh() async {
        guard let mouse else { return }
        await refreshBattery()
        dpi = try? await mouse.dpi()
        wheel = try? await mouse.wheel()
        wheelReversed = try? await mouse.wheelReversed()
        await reapplySavedSettings(to: mouse)
        await applyGestureDiversion()
    }

    func refreshBattery() async {
        guard let mouse else { return }
        if let battery = try? await mouse.battery() { self.battery = battery }
    }

    /// The mouse forgets these when it powers off, so put back what the user chose.
    private func reapplySavedSettings(to mouse: HIDPPDevice) async {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Keys.dpi) as? Int, let current = dpi, current != saved,
           (try? await mouse.setDPI(saved)) != nil {
            dpi = saved
        }
        if let current = wheel, defaults.object(forKey: Keys.freeSpin) != nil {
            let saved = HIDPPDevice.WheelSettings(
                freeSpin: defaults.bool(forKey: Keys.freeSpin),
                autoDisengage: UInt8(clamping: defaults.integer(forKey: Keys.autoDisengage)))
            if saved != current, (try? await mouse.setWheel(saved)) != nil { wheel = saved }
        }
        if let current = wheelReversed, defaults.object(forKey: Keys.reversed) != nil {
            let saved = defaults.bool(forKey: Keys.reversed)
            if saved != current, (try? await mouse.setWheelReversed(saved)) != nil { wheelReversed = saved }
        }
    }

    private func applyGestureDiversion() async {
        guard let mouse else { return }
        do {
            try await mouse.setDiverted(cid: Self.gestureCID, gestureEnabled)
        } catch {
            log.info("Gesture button diversion unavailable: \(error.localizedDescription)")
        }
    }

    private func handleNotification(_ r: [UInt8], from transport: HIDPPTransport) {
        // Receiver says a paired device connected or disconnected (HID++ 1.0 notification 0x41).
        if transport.isReceiver && r[2] == 0x41 {
            let linkUp = r[4] & 0x40 == 0
            let isOurs = mouse?.transport === transport && mouse?.index == r[1]
            if linkUp {
                Task { if isOurs { await refresh() } else if mouse == nil { await discover(on: transport) } }
            } else if isOurs {
                battery = nil
                state = .notFound
            }
            return
        }
        guard let mouse, mouse.transport === transport, r[1] == mouse.index, r[3] & 0x0F == 0 else { return }
        if r[2] == mouse.cachedIndex(of: .reprogControls) {
            // Diverted button event: up to four pressed CIDs, two bytes each.
            let pressed = stride(from: 4, to: min(r.count - 1, 12), by: 2).map { UInt16(r[$0]) << 8 | UInt16(r[$0 + 1]) }
            let down = pressed.contains(Self.gestureCID)
            if down && !gestureDown { onGesturePress?() }
            gestureDown = down
        } else if r[2] == mouse.cachedIndex(of: .unifiedBattery) || r[2] == mouse.cachedIndex(of: .batteryStatus) {
            Task { await refreshBattery() }
        }
        if state != .connected { state = .connected }
    }

    // MARK: Changing settings

    func setDPI(_ value: Int) {
        UserDefaults.standard.set(value, forKey: Keys.dpi)
        perform { try await $0.setDPI(value); self.dpi = value }
    }

    func setWheel(_ settings: HIDPPDevice.WheelSettings) {
        UserDefaults.standard.set(settings.freeSpin, forKey: Keys.freeSpin)
        UserDefaults.standard.set(Int(settings.autoDisengage), forKey: Keys.autoDisengage)
        perform { try await $0.setWheel(settings); self.wheel = settings }
    }

    func setWheelReversed(_ reversed: Bool) {
        UserDefaults.standard.set(reversed, forKey: Keys.reversed)
        perform { try await $0.setWheelReversed(reversed); self.wheelReversed = reversed }
    }

    private func perform(_ operation: @escaping (HIDPPDevice) async throws -> Void) {
        guard let mouse else { return }
        Task {
            do {
                try await operation(mouse)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
