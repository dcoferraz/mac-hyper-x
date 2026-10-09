import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

/// Finds the QuadCast S over USB and streams lighting frames to it.
///
/// How the mic works (protocol documented by the open-source QuadcastRGB
/// project, github.com/Ors1mer/QuadcastRGB):
///  - The mic has no memory for custom colors. If the host stops sending
///    frames, it falls back to its built-in rainbow. So the host has to keep
///    streaming, about every 55 ms.
///  - Each frame is two 64-byte HID SET_REPORT control transfers:
///      1. header: 04 F2 00 00 00 00 00 00 01 00 …
///      2. colors: 81 RR GG BB 81 RR GG BB 00 …   (upper ring, lower ring)
///
/// The reports go out as raw USB control transfers rather than through
/// IOHIDManager. macOS leaves the lighting interface unclaimed and never
/// publishes an IOHIDDevice for it, so IOHIDManager cannot see it at all. The
/// HID interfaces macOS *does* publish are the mute/volume controls, whose
/// feature reports are one byte long and reject a 64-byte write.
final class QuadCastDevice {
    private typealias DeviceRef = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>
    private typealias InterfaceRef = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>

    /// Known VID/PID pairs for the QuadCast S (Kingston- and HP-era units)
    /// and the DuoCast, which uses the same protocol.
    private static let supportedIDs: [(vendor: Int32, product: Int32)] = [
        (0x0951, 0x171F),
        (0x03F0, 0x0F8B),
        (0x03F0, 0x028C),
        (0x03F0, 0x048C),
        (0x03F0, 0x068C),
        (0x03F0, 0x098C), // DuoCast
    ]

    private static let frameInterval: DispatchTimeInterval = .milliseconds(55)
    private static let rescanInterval: CFTimeInterval = 1
    private static let reportSize = 64

    private let queue = DispatchQueue(label: "QuadCastControl.usb")
    private var device: DeviceRef?
    private var interface: InterfaceRef?
    private var interfaceNumber: UInt16 = 0
    private var timer: DispatchSourceTimer?
    private var lastScan: CFAbsoluteTime = 0
    private var config = LightingConfig()
    private var isConnected = false

    /// Called on the USB queue whenever the connection state changes.
    var onConnectionChange: ((Bool) -> Void)?

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.frameInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func update(_ newConfig: LightingConfig) {
        queue.async { self.config = newConfig }
    }

    // MARK: - Streaming

    private func tick() {
        if interface == nil { rescan() }
        guard let interface else { return }

        let colors = currentColors()
        if !sendFrame(colors, to: interface, interfaceNumber: interfaceNumber) {
            // The mic went away, or another process took the interface.
            releaseDevice()
            setConnected(false)
        }
    }

    /// Both ring colors for right now. The on-screen preview uses the same
    /// clock and the same function, so the two stay in phase.
    private func currentColors() -> (upper: RGB, lower: RGB) {
        let t = CFAbsoluteTimeGetCurrent()
        return (Effects.color(for: config.upper, ring: .upper, time: t),
                Effects.color(for: config.effectiveLower, ring: .lower, time: t))
    }

    private func sendFrame(_ colors: (upper: RGB, lower: RGB),
                           to interface: InterfaceRef,
                           interfaceNumber: UInt16) -> Bool {
        var header = [UInt8](repeating: 0, count: Self.reportSize)
        header[0] = 0x04
        header[1] = 0xF2
        header[8] = 0x01

        var payload = [UInt8](repeating: 0, count: Self.reportSize)
        payload[0] = 0x81
        (payload[1], payload[2], payload[3]) = colors.upper.bytes
        payload[4] = 0x81
        (payload[5], payload[6], payload[7]) = colors.lower.bytes

        return setReport(header, to: interface, interfaceNumber: interfaceNumber)
            && setReport(payload, to: interface, interfaceNumber: interfaceNumber)
    }

    private func setReport(_ bytes: [UInt8], to interface: InterfaceRef, interfaceNumber: UInt16) -> Bool {
        var bytes = bytes
        return bytes.withUnsafeMutableBufferPointer { buffer in
            var request = IOUSBDevRequest()
            request.bmRequestType = 0x21   // host to device, class request, interface recipient
            request.bRequest = 0x09        // SET_REPORT
            request.wValue = 0x0300        // feature report, report ID 0
            request.wIndex = interfaceNumber
            request.wLength = UInt16(buffer.count)
            request.pData = UnsafeMutableRawPointer(buffer.baseAddress)
            return interface.pointee?.pointee.ControlRequest(interface, 0, &request) == kIOReturnSuccess
        }
    }

    // MARK: - Finding the mic

    /// Looks for a supported mic, at most once a second so that an unplugged
    /// mic doesn't cost a scan on every frame.
    private func rescan() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastScan >= Self.rescanInterval else { return }
        lastScan = now

        for id in Self.supportedIDs {
            if claimDevice(vendor: id.vendor, product: id.product) {
                setConnected(true)
                return
            }
        }
        setConnected(false)
    }

    private func claimDevice(vendor: Int32, product: Int32) -> Bool {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return false }
        let filter = matching as NSMutableDictionary
        filter[kUSBVendorID] = vendor
        filter[kUSBProductID] = product

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return false }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let claimed = claim(service)
            IOObjectRelease(service)
            if claimed { return true }
        }
        return false
    }

    private func claim(_ service: io_service_t) -> Bool {
        guard let device: DeviceRef = plugIn(for: service,
                                             type: USBUUID.deviceUserClient,
                                             interface: USBUUID.deviceInterface)
        else { return false }
        _ = device.pointee?.pointee.USBDeviceOpen(device)

        let dontCare = UInt16(kIOUSBFindInterfaceDontCare)
        var request = IOUSBFindInterfaceRequest(bInterfaceClass: dontCare,
                                                bInterfaceSubClass: dontCare,
                                                bInterfaceProtocol: dontCare,
                                                bAlternateSetting: dontCare)
        var iterator: io_iterator_t = 0
        guard device.pointee?.pointee.CreateInterfaceIterator(device, &request, &iterator) == kIOReturnSuccess
        else {
            close(device)
            return false
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let adopted = adopt(service, of: device)
            IOObjectRelease(service)
            if adopted { return true }
        }
        close(device)
        return false
    }

    /// Keeps the first interface that opens and accepts a whole frame. The mic
    /// exposes several; on the units tested that is interface 0, the one macOS
    /// leaves without a driver. The others are held by the system HID driver
    /// and refuse to open.
    private func adopt(_ service: io_service_t, of device: DeviceRef) -> Bool {
        guard let candidate: InterfaceRef = plugIn(for: service,
                                                   type: USBUUID.interfaceUserClient,
                                                   interface: USBUUID.interfaceInterface)
        else { return false }

        guard candidate.pointee?.pointee.USBInterfaceOpen(candidate) == kIOReturnSuccess else {
            _ = candidate.pointee?.pointee.Release(candidate)
            return false
        }

        var number: UInt8 = 0
        _ = candidate.pointee?.pointee.GetInterfaceNumber(candidate, &number)

        if sendFrame(currentColors(), to: candidate, interfaceNumber: UInt16(number)) {
            self.device = device
            self.interface = candidate
            self.interfaceNumber = UInt16(number)
            return true
        }

        _ = candidate.pointee?.pointee.USBInterfaceClose(candidate)
        _ = candidate.pointee?.pointee.Release(candidate)
        return false
    }

    /// The IOKit plug-in dance: ask a service for a COM-style interface.
    private func plugIn<T>(for service: io_service_t, type: CFUUID, interface uuid: CFUUID)
        -> UnsafeMutablePointer<UnsafeMutablePointer<T>?>? {
        var score: Int32 = 0
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        guard IOCreatePlugInInterfaceForService(service, type, USBUUID.plugIn, &plugIn, &score) == KERN_SUCCESS,
              let plugIn
        else { return nil }
        defer { IODestroyPlugInInterface(plugIn) }

        var result: LPVOID?
        guard plugIn.pointee?.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(uuid), &result) == 0,
              let result
        else { return nil }
        return result.assumingMemoryBound(to: UnsafeMutablePointer<T>?.self)
    }

    private func releaseDevice() {
        if let interface {
            _ = interface.pointee?.pointee.USBInterfaceClose(interface)
            _ = interface.pointee?.pointee.Release(interface)
        }
        interface = nil
        if let device { close(device) }
        device = nil
    }

    private func close(_ device: DeviceRef) {
        _ = device.pointee?.pointee.USBDeviceClose(device)
        _ = device.pointee?.pointee.Release(device)
    }

    private func setConnected(_ value: Bool) {
        guard value != isConnected else { return }
        isConnected = value
        onConnectionChange?(value)
    }
}

/// The CFUUIDs IOKit's plug-in API needs. They are C macros, so Swift can't
/// see them; these are the same bytes spelled out.
private enum USBUUID {
    static let plugIn = make(0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
                             0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
    static let deviceUserClient = make(0x9D, 0xC7, 0xB7, 0x80, 0x9E, 0xC0, 0x11, 0xD4,
                                       0xA5, 0x4F, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61)
    static let deviceInterface = make(0x5C, 0x81, 0x87, 0xD0, 0x9E, 0xF3, 0x11, 0xD4,
                                      0x8B, 0x45, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61)
    static let interfaceUserClient = make(0x2D, 0x97, 0x86, 0xC6, 0x9E, 0xF3, 0x11, 0xD4,
                                          0xAD, 0x51, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61)
    static let interfaceInterface = make(0x73, 0xC9, 0x7A, 0xE8, 0x9E, 0xF3, 0x11, 0xD4,
                                         0xB1, 0xD0, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61)

    private static func make(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8,
                             _ b4: UInt8, _ b5: UInt8, _ b6: UInt8, _ b7: UInt8,
                             _ b8: UInt8, _ b9: UInt8, _ b10: UInt8, _ b11: UInt8,
                             _ b12: UInt8, _ b13: UInt8, _ b14: UInt8, _ b15: UInt8) -> CFUUID {
        CFUUIDGetConstantUUIDWithBytes(nil, b0, b1, b2, b3, b4, b5, b6, b7,
                                       b8, b9, b10, b11, b12, b13, b14, b15)
    }
}
