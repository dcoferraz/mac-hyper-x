import Foundation
import IOKit.hid

/// Watches the mic's own controls: the tap-to-mute sensor and the polar
/// pattern dial.
///
/// They sit on a vendor-defined HID interface (usage page 0xFFFF). macOS
/// doesn't gate that page behind Input Monitoring, so this needs no permission
/// and no prompt. Both report through an 8-byte input report with ID 5, where
/// byte 1 says which control moved and byte 2 carries its new value:
///
///     05 10 00 …   mute sensor: muted
///     05 10 01 …   mute sensor: not muted
///     05 11 00 …   pattern dial: 0...3, see PolarPattern
///
/// The mic refuses a request for the current state (GetReport returns
/// 0xe0005000), so nothing is known until the user touches a control. That is
/// why both values are optional everywhere above this class.
///
/// The gain dial is analog and reports nothing at all.
final class StatusMonitor {
    private static let reportID: UInt32 = 5
    private static let reportSize = 64
    /// Byte 1: which control the report is about.
    private static let muteTopic: UInt8 = 0x10
    private static let patternTopic: UInt8 = 0x11
    /// Byte 2 of a mute report when the mic is muted. Confirmed on hardware: a
    /// tap that mutes the mic reports 0, and the tap that unmutes it reports 1.
    private static let mutedValue: UInt8 = 0
    private static let rescanInterval: DispatchTimeInterval = .seconds(2)

    /// These controls live on the same units the lighting does.
    private static let supportedIDs: [(vendor: Int, product: Int)] = [
        (0x0951, 0x171F),
        (0x03F0, 0x0F8B),
        (0x03F0, 0x028C),
        (0x03F0, 0x048C),
        (0x03F0, 0x068C),
        (0x03F0, 0x098C),
    ]

    /// A watched interface. The report buffer has to stay put for as long as
    /// the callback is registered, so it lives here rather than on the stack.
    private final class Watch {
        let device: IOHIDDevice
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: StatusMonitor.reportSize)

        init(_ device: IOHIDDevice) {
            self.device = device
            buffer.initialize(repeating: 0, count: StatusMonitor.reportSize)
        }

        deinit { buffer.deallocate() }
    }

    private let queue = DispatchQueue(label: "QuadCastControl.status")
    private let manager: IOHIDManager
    private var watches: [Watch] = []
    private var timer: DispatchSourceTimer?

    /// Called on the monitor's queue when the mic reports a new state.
    var onMuteChange: ((Bool) -> Void)?
    var onPatternChange: ((PolarPattern) -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = Self.supportedIDs.map {
            [kIOHIDVendorIDKey: $0.vendor, kIOHIDProductIDKey: $0.product] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// The manager is used only to enumerate. Letting it manage the devices
    /// instead activates them before a report callback can be attached, which
    /// IOHIDFamily treats as a programming error.
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.rescanInterval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.rescan() }
        timer.resume()
        self.timer = timer
    }

    private func rescan() {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            watches.removeAll()
            return
        }
        watches.removeAll { watch in !devices.contains(watch.device) }
        for device in devices where !watches.contains(where: { $0.device === device }) {
            attach(device)
        }
    }

    private func attach(_ device: IOHIDDevice) {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else { return }

        let watch = Watch(device)
        let context = Unmanaged.passUnretained(self).toOpaque()
        // The callback has to be in place before the device is activated.
        IOHIDDeviceRegisterInputReportCallback(
            device, watch.buffer, Self.reportSize,
            { context, _, _, _, reportID, report, length in
                guard let context, reportID == StatusMonitor.reportID, length >= 3 else { return }
                let monitor = Unmanaged<StatusMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.handle(topic: report[1], value: report[2])
            }, context)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)
        watches.append(watch)
    }

    private func handle(topic: UInt8, value: UInt8) {
        switch topic {
        case Self.muteTopic:
            onMuteChange?(value == Self.mutedValue)
        case Self.patternTopic:
            if let pattern = PolarPattern(rawValue: value) { onPatternChange?(pattern) }
        default:
            break   // the mic may report things this app doesn't use
        }
    }
}
