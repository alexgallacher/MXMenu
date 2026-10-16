import Foundation
import IOKit.hid
import os

let log = Logger(subsystem: "MXMenu", category: "hidpp")

enum HIDPPError: LocalizedError {
    case timeout
    case featureNotSupported(UInt16)
    case deviceError(UInt8)
    case sendFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .timeout: return "The mouse didn't answer."
        case .featureNotSupported(let id): return String(format: "Feature 0x%04X isn't supported by this mouse.", id)
        case .deviceError(let code): return "The mouse returned error \(code)."
        case .sendFailed(let code): return String(format: "Couldn't talk to the mouse (IOReturn 0x%08X).", code)
        }
    }
}

/// HID++ 2.0 feature IDs used by this app.
enum HIDPPFeature: UInt16 {
    case root = 0x0000
    case deviceName = 0x0005
    case batteryStatus = 0x1000
    case unifiedBattery = 0x1004
    case reprogControls = 0x1B04
    case smartShift = 0x2110
    case smartShiftEnhanced = 0x2111
    case hiResWheel = 0x2121
    case adjustableDPI = 0x2201
}

/// One HID++ capable HID interface: a Bluetooth mouse, or a Logi Bolt / Unifying receiver.
@MainActor
final class HIDPPTransport {
    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let longReportLength = 20
    /// Non-zero so our responses can be told apart from device notifications (which use 0).
    private static let softwareID: UInt8 = 0x0A

    let hid: IOHIDDevice
    let isReceiver: Bool
    let transportName: String
    var onNotification: (([UInt8]) -> Void)?

    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var pending: [UUID: Pending] = [:]
    private var queue: Task<Void, Never>?

    private struct Pending {
        let deviceIndex: UInt8
        let featureIndex: UInt8
        let functionByte: UInt8
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    init(hid: IOHIDDevice) {
        self.hid = hid
        let transport = IOHIDDeviceGetProperty(hid, kIOHIDTransportKey as CFString) as? String ?? ""
        let product = IOHIDDeviceGetProperty(hid, kIOHIDProductKey as CFString) as? String ?? ""
        let bluetooth = transport.localizedCaseInsensitiveContains("bluetooth")
        isReceiver = !bluetooth && product.localizedCaseInsensitiveContains("receiver")
        transportName = bluetooth ? "Bluetooth" : (isReceiver ? "Logi Bolt receiver" : "USB")
    }

    deinit {
        inputBuffer.deallocate()
    }

    func open() -> Bool {
        guard IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(hid, inputBuffer, 64, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let transport = Unmanaged<HIDPPTransport>.fromOpaque(context).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            let id = UInt8(truncatingIfNeeded: reportID)
            if bytes.first != id { bytes.insert(id, at: 0) }
            MainActor.assumeIsolated { transport.handleInput(bytes) }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return true
    }

    func close() {
        IOHIDDeviceUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        for id in pending.keys { fail(id, with: .timeout) }
    }

    /// Sends a long HID++ request and returns the response parameters (bytes 4…19).
    /// Requests are serialized so responses can't be confused with each other.
    func request(device: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) async throws -> [UInt8] {
        let previous = queue
        let task = Task { () throws -> [UInt8] in
            await previous?.value
            return try await self.send(device: device, feature: feature, function: function, params: params)
        }
        queue = Task { _ = try? await task.value }
        return try await task.value
    }

    private func send(device: UInt8, feature: UInt8, function: UInt8, params: [UInt8]) async throws -> [UInt8] {
        let functionByte = (function << 4) | Self.softwareID
        var report = [Self.longReportID, device, feature, functionByte] + params
        report += Array(repeating: 0, count: max(0, Self.longReportLength - report.count))
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = Pending(deviceIndex: device, featureIndex: feature, functionByte: functionByte, continuation: continuation)
            let result = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, CFIndex(Self.longReportID), $0.baseAddress!, $0.count)
            }
            guard result == kIOReturnSuccess else {
                fail(id, with: .sendFailed(result))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.fail(id, with: .timeout)
            }
        }
    }

    private func fail(_ id: UUID, with error: HIDPPError) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }

    private func handleInput(_ r: [UInt8]) {
        guard r.count >= 7, r[0] == Self.shortReportID || r[0] == Self.longReportID else { return }
        for (id, p) in pending where r[1] == p.deviceIndex {
            if r[2] == p.featureIndex && r[3] == p.functionByte {
                pending[id] = nil
                p.continuation.resume(returning: Array(r[4...]))
                return
            }
            // 0xFF = HID++ 2.0 error, 0x8F = HID++ 1.0 error (receiver, e.g. empty pairing slot).
            if (r[2] == 0xFF || r[2] == 0x8F) && r[3] == p.featureIndex && r[4] == p.functionByte {
                pending[id] = nil
                p.continuation.resume(throwing: HIDPPError.deviceError(r[5]))
                return
            }
        }
        onNotification?(r)
    }
}

/// A HID++ 2.0 device behind a transport: index 0xFF for Bluetooth, 1…6 behind a receiver.
@MainActor
final class HIDPPDevice {
    let transport: HIDPPTransport
    let index: UInt8
    private var featureIndexes: [HIDPPFeature: UInt8] = [:]

    init(transport: HIDPPTransport, index: UInt8) {
        self.transport = transport
        self.index = index
    }

    func featureIndex(_ feature: HIDPPFeature) async throws -> UInt8 {
        if feature == .root { return 0 }
        if let cached = featureIndexes[feature] { return cached }
        let id = feature.rawValue
        let r = try await transport.request(device: index, feature: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)])
        guard r[0] != 0 else { throw HIDPPError.featureNotSupported(id) }
        featureIndexes[feature] = r[0]
        return r[0]
    }

    func cachedIndex(of feature: HIDPPFeature) -> UInt8? { featureIndexes[feature] }

    func supports(_ feature: HIDPPFeature) async -> Bool {
        (try? await featureIndex(feature)) != nil
    }

    func call(_ feature: HIDPPFeature, _ function: UInt8, _ params: [UInt8] = []) async throws -> [UInt8] {
        let featureIndex = try await featureIndex(feature)
        return try await transport.request(device: index, feature: featureIndex, function: function, params: params)
    }

    // MARK: Name (0x0005)

    func name() async throws -> String {
        let count = Int(try await call(.deviceName, 0)[0])
        var bytes: [UInt8] = []
        while bytes.count < count {
            let chunk = try await call(.deviceName, 1, [UInt8(bytes.count)])
            bytes += chunk.prefix(count - bytes.count)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Battery (0x1004, falling back to 0x1000)

    struct Battery: Equatable {
        let percent: Int
        let charging: Bool
    }

    func battery() async throws -> Battery {
        if let r = try? await call(.unifiedBattery, 1) {
            var percent = Int(r[0])
            if percent == 0 {
                // Device only reports coarse levels: bit3 full, bit2 good, bit1 low, bit0 critical.
                percent = r[1] & 0x08 != 0 ? 100 : r[1] & 0x04 != 0 ? 50 : r[1] & 0x02 != 0 ? 20 : 5
            }
            return Battery(percent: percent, charging: (1...3).contains(r[2]))
        }
        let r = try await call(.batteryStatus, 0)
        return Battery(percent: Int(r[0]), charging: (1...4).contains(r[2]))
    }

    // MARK: Pointer speed (0x2201)

    func dpi() async throws -> Int {
        let r = try await call(.adjustableDPI, 2, [0])
        return Int(r[1]) << 8 | Int(r[2])
    }

    func setDPI(_ dpi: Int) async throws {
        _ = try await call(.adjustableDPI, 3, [0, UInt8(dpi >> 8), UInt8(dpi & 0xFF)])
    }

    // MARK: Scroll wheel mode / SmartShift (0x2111, falling back to 0x2110)

    struct WheelSettings: Equatable {
        static let smartShiftOff: UInt8 = 0xFF
        var freeSpin: Bool
        /// Scroll speed at which the wheel leaves ratchet mode. 0xFF keeps it in ratchet.
        var autoDisengage: UInt8
    }

    func wheel() async throws -> WheelSettings {
        let r: [UInt8]
        if await supports(.smartShiftEnhanced) {
            r = try await call(.smartShiftEnhanced, 1)
        } else {
            r = try await call(.smartShift, 0)
        }
        return WheelSettings(freeSpin: r[0] == 1, autoDisengage: r[1])
    }

    func setWheel(_ s: WheelSettings) async throws {
        let mode: UInt8 = s.freeSpin ? 1 : 2
        if await supports(.smartShiftEnhanced) {
            _ = try await call(.smartShiftEnhanced, 2, [mode, s.autoDisengage, 0])
        } else {
            _ = try await call(.smartShift, 1, [mode, s.autoDisengage, 0])
        }
    }

    // MARK: Wheel direction (0x2121)

    private static let invertFlag: UInt8 = 0x04

    func wheelReversed() async throws -> Bool {
        try await call(.hiResWheel, 1)[0] & Self.invertFlag != 0
    }

    func setWheelReversed(_ reversed: Bool) async throws {
        let flags = try await call(.hiResWheel, 1)[0]
        _ = try await call(.hiResWheel, 2, [reversed ? flags | Self.invertFlag : flags & ~Self.invertFlag])
    }

    // MARK: Button diversion (0x1B04)

    /// Diverted buttons stop doing their normal job and are reported to us as HID++ notifications.
    func setDiverted(cid: UInt16, _ diverted: Bool) async throws {
        _ = try await call(.reprogControls, 3, [UInt8(cid >> 8), UInt8(cid & 0xFF), diverted ? 0x03 : 0x02, 0, 0])
    }

    /// Logs every control the mouse exposes, handy for finding the MX Master 4's extra buttons.
    func logControls() async {
        guard let count = try? await call(.reprogControls, 0)[0] else { return }
        for i in 0..<count {
            guard let r = try? await call(.reprogControls, 1, [i]) else { continue }
            let cid = UInt16(r[0]) << 8 | UInt16(r[1])
            let divertable = r[4] & 0x20 != 0
            log.info("Control \(i): CID 0x\(String(cid, radix: 16)) divertable=\(divertable)")
        }
    }
}
