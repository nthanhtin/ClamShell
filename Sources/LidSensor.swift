import Foundation
import IOKit.hid

final class LidSensor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?

    init() {
        let match: [String: Int] = [
            kIOHIDVendorIDKey: 0x05ac,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8a
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices where IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess {
            device = candidate
            if readAngle() != nil { return }
            IOHIDDeviceClose(candidate, 0)
            device = nil
        }
    }

    deinit {
        if let device { IOHIDDeviceClose(device, 0) }
        IOHIDManagerClose(manager, 0)
    }

    func readAngle() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        var count = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count)
        guard result == kIOReturnSuccess else { return nil }
        return Self.decode(Array(bytes.prefix(count)))
    }

    static func decode(_ report: [UInt8]) -> Double? {
        // Apple's orientation feature report: report ID, then little-endian degrees.
        guard report.count >= 3, report[0] == 1 else { return nil }
        let degrees = Int(report[1]) | Int(report[2]) << 8
        return (0...360).contains(degrees) ? Double(degrees) : nil
    }
}
