import Foundation
import IOKit

/// One HID interface a device presents, as the I/O Registry describes it.
///
/// `usagePage` 1 is Generic Desktop, where the usages that name an input device
/// live: 2 mouse, 4 joystick, 5 game pad, 6 keyboard, 7 keypad, 8 multi-axis.
/// `usagePage` 0x0D is Digitizer, whose 5 is a touch pad — a trackpad also
/// enumerates as a pointer, so the page is what tells the two apart.
struct BluetoothHIDUsage: Equatable, Sendable {
    let usagePage: Int
    let usage: Int
}

/// Reads the HID usages of every Bluetooth device the system has enumerated.
///
/// The class wording in the system profiler's report is the manufacturer's
/// claim about its product and it can be wrong: a Logitech keyboard reports
/// `Mouse` in `device_minorType`, while the usage it presents is Generic
/// Desktop keyboard — the one macOS actually loads a keyboard driver for. The
/// I/O Registry carries that usage and nothing else in the app reads it.
///
/// The walk runs inside this process: `IORegistryEntryCreateCFProperties` over
/// the services `IOServiceMatching` returns. There is no `ioreg` or `hidutil`
/// subprocess to hang the way `/usr/sbin/system_profiler` can, no Bluetooth
/// grant is involved, and the app is not sandboxed, so the Registry is readable
/// without a permission of any kind.
///
/// Only connected devices have a node. A paired but disconnected device keeps
/// the class the report declared, which is the same answer the app gave before
/// this reader existed.
enum BluetoothHIDUsageReader {
    /// Keyed by `BluetoothBatteryReader.normalizedAddress`, the one
    /// normalization the app joins devices by, so a Registry address written
    /// `d3-6d-6c-40-a3-2e` and a report address written `D3:6D:6C:40:A3:2E`
    /// meet on the same key.
    static func read() -> [String: [BluetoothHIDUsage]] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var usages: [String: [BluetoothHIDUsage]] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            guard let value = readUsages(from: service, using: registryProperty) else {
                continue
            }

            let key = BluetoothBatteryReader.normalizedAddress(value.address)
            guard !key.isEmpty else { continue }
            usages[key, default: []].append(contentsOf: value.usages)
        }
        return usages
    }

    /// Reads the Registry values used to filter and classify a Bluetooth HID
    /// service: the address to join on, plus every top-level usage the device
    /// presents. Transport is checked first so built-in and USB services avoid
    /// the other property lookups entirely.
    ///
    /// A Bluetooth HID device is a single `IOHIDDevice` node whose primary usage
    /// is only the first collection in its report descriptor. `DeviceUsagePairs`
    /// lists them all, so a composite mouse that declares its keyboard or macro
    /// collection first would otherwise be read as a keyboard. Only when the
    /// pairs are absent does the primary usage stand in for the device's one
    /// interface.
    static func readUsages(
        from service: io_registry_entry_t,
        using readProperty: (io_registry_entry_t, CFString) -> Any?
    ) -> (address: String, usages: [BluetoothHIDUsage])? {
        guard let transport = readProperty(service, "Transport" as CFString) as? String,
              transport.lowercased().contains("bluetooth"),
              let address = readProperty(service, "DeviceAddress" as CFString) as? String else {
            return nil
        }

        if let pairs = readProperty(service, "DeviceUsagePairs" as CFString) as? [[String: Any]] {
            let usages = pairs.compactMap { pair -> BluetoothHIDUsage? in
                guard let page = pair["DeviceUsagePage"] as? Int,
                      let usage = pair["DeviceUsage"] as? Int else {
                    return nil
                }
                return BluetoothHIDUsage(usagePage: page, usage: usage)
            }
            if !usages.isEmpty {
                return (address, usages)
            }
        }

        guard let usagePage = readProperty(service, "PrimaryUsagePage" as CFString) as? Int,
              let usage = readProperty(service, "PrimaryUsage" as CFString) as? Int else {
            return nil
        }
        return (address, [BluetoothHIDUsage(usagePage: usagePage, usage: usage)])
    }

    private static func registryProperty(_ service: io_registry_entry_t, _ key: CFString) -> Any? {
        guard let property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0) else {
            return nil
        }
        return property.takeRetainedValue()
    }
}

/// Input roles observed across a device's HID interfaces.
struct BluetoothHIDCapabilities: Equatable, Sendable {
    let hasMouse: Bool
    let hasKeyboard: Bool
    let hasTrackpad: Bool
    let hasGamepad: Bool

    private enum UsagePage {
        static let genericDesktop = 1
        static let digitizer = 0x0D
    }

    private enum GenericDesktopUsage {
        static let pointer = 1
        static let mouse = 2
        static let joystick = 4
        static let gamePad = 5
        static let keyboard = 6
        static let keypad = 7
        static let multiAxisController = 8
    }

    private enum DigitizerUsage {
        static let touchPad = 0x05
        static let finger = 0x22
    }

    init(usages: [BluetoothHIDUsage]) {
        func has(_ page: Int, _ usage: Int) -> Bool {
            usages.contains { $0.usagePage == page && $0.usage == usage }
        }

        hasMouse = has(UsagePage.genericDesktop, GenericDesktopUsage.pointer)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.mouse)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.multiAxisController)
        hasKeyboard = has(UsagePage.genericDesktop, GenericDesktopUsage.keyboard)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.keypad)
        hasTrackpad = has(UsagePage.digitizer, DigitizerUsage.touchPad)
            || has(UsagePage.digitizer, DigitizerUsage.finger)
        hasGamepad = has(UsagePage.genericDesktop, GenericDesktopUsage.joystick)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.gamePad)
    }
}
