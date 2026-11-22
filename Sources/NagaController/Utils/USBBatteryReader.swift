import Foundation
import IOKit.hid

enum USBBatteryReader {
    private static let reportSize = 90
    private static let busyStatus: UInt8 = 0x01
    private static let successStatus: UInt8 = 0x02

    // Call on a background queue. This uses the app's existing Input Monitoring grant.
    static func readPercentage() -> Int? {
        guard PermissionManager.shared.hasInputMonitoringPermission() else { return nil }

        let options = IOOptionBits(kIOHIDOptionsTypeNone)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x1532,
            kIOHIDProductIDKey: 0x00b4,
            kIOHIDPrimaryUsagePageKey: 0x01,
            kIOHIDPrimaryUsageKey: 0x02
        ] as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        let receivers = devices.filter { device in
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
            let featureSize = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? NSNumber
            return transport == "USB" && featureSize?.intValue == reportSize
        }
        guard receivers.count == 1, let receiver = receivers.first else { return nil }
        guard IOHIDDeviceOpen(receiver, options) == kIOReturnSuccess else { return nil }
        defer { IOHIDDeviceClose(receiver, options) }

        return readPercentage(from: receiver)
    }

    private static func readPercentage(from receiver: IOHIDDevice) -> Int? {
        // Naga V2 HyperSpeed battery query, class 0x07 and command 0x80.
        // The feature report sends a read request with two zero arguments.
        // Protocol reference: OpenNaga v2.7.0, RazerProtocol.swift.
        var request = [UInt8](repeating: 0, count: reportSize)
        request[1] = 0x1f
        request[5] = 2
        request[6] = 0x07
        request[7] = 0x80
        request[88] = checksum(request)

        let sent = IOHIDDeviceSetReport(receiver, kIOHIDReportTypeFeature, 0, request, request.count)
        guard sent == kIOReturnSuccess else { return nil }

        Thread.sleep(forTimeInterval: 0.035)
        var response = [UInt8](repeating: 0, count: reportSize)
        for attempt in 0..<5 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.025) }
            var length = reportSize
            let received = IOHIDDeviceGetReport(receiver, kIOHIDReportTypeFeature, 0, &response, &length)
            guard received == kIOReturnSuccess, length == reportSize,
                  checksum(response) == response[88] else { return nil }

            // The receiver can still be processing the command or expose a previous response.
            guard response[1] == request[1], response[6] == request[6], response[7] == request[7],
                  response[0] != busyStatus else { continue }
            guard response[0] == successStatus, response[5] == request[5],
                  response[2] == 0, response[3] == 0, response[4] == 0, response[89] == 0 else { return nil }

            return (Int(response[9]) * 100 + 127) / 255
        }
        return nil
    }

    private static func checksum(_ report: [UInt8]) -> UInt8 {
        report[2..<88].reduce(0, ^)
    }
}
