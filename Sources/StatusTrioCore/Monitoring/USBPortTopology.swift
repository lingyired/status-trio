import Foundation
import IOKit

/// Which accessory sits behind each SMC output channel, and which port the
/// Mac is charging from. Read-only IORegistry properties; no user client, no
/// notifications, no polling of its own.
///
/// Channel mapping: the SMC `Dn` rails and `PowerOutDetails.PortIndex` are
/// numbered 1…n over the USB-C ports in `PortNumber` order (MagSafe, HDMI and
/// the SD slot are not output channels). Measured on Mac16,1 / macOS 27.3: a
/// sustained read from the bus-powered SSD on `Port-USB-C@4` lifted D3 from
/// 0.85 W to 2.7–3.5 W while D1 (Apple Watch charger on `@1`) and D2 (display
/// adapter on `@2`) stayed flat. That machine's `hpm` index order gives the
/// same result, so the two orderings are not yet told apart on any model.
struct USBPortTopology: Equatable, Sendable {
    struct Port: Equatable, Sendable {
        let channel: Int
        let portDescription: String
        /// Accessory names reported by USB, hubs and Billboard devices removed.
        let deviceNames: [String]
    }

    /// A `Port-*` service as it appears in IORegistry.
    struct PortNode: Equatable, Sendable {
        let portDescription: String
        let portNumber: Int
        /// "USB-C", "MagSafe 3", …
        let typeDescription: String
    }

    /// An `IOUSBHostDevice` and the port its host controller serves.
    struct DeviceNode: Equatable, Sendable {
        let portDescription: String
        let name: String
        let deviceClass: Int?
        let locationID: Int
    }

    let ports: [Port]
    /// User-facing type of the port the adapter feeds ("MagSafe 3", "USB-C").
    let inputPortType: String?
    /// Output channel of the charging port when it is a USB-C port. Its rail
    /// is not power delivered to an accessory.
    let inputChannel: Int?

    static let empty = USBPortTopology(ports: [], inputPortType: nil, inputChannel: nil)

    /// The accessory name for a channel: the first device, with "+N" when the
    /// port carries more than one (a hub's downstream devices).
    func name(forChannel channel: Int) -> String? {
        guard let names = ports.first(where: { $0.channel == channel })?.deviceNames,
              let first = names.first else { return nil }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }

    /// USB class codes that name plumbing rather than the accessory itself.
    private static let hubClass = 0x09
    private static let billboardClass = 0x11

    static func make(usbCPorts: [PortNode], devices: [DeviceNode], inputPort: PortNode?) -> USBPortTopology {
        let ordered = usbCPorts.sorted { $0.portNumber < $1.portNumber }
        let sortedDevices = devices.sorted { $0.locationID < $1.locationID }
        let ports = ordered.enumerated().map { offset, node -> Port in
            var names: [String] = []
            for device in sortedDevices where device.portDescription == node.portDescription {
                if let deviceClass = device.deviceClass,
                   deviceClass == hubClass || deviceClass == billboardClass { continue }
                let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !names.contains(name) { names.append(name) }
            }
            return Port(channel: offset + 1, portDescription: node.portDescription, deviceNames: names)
        }
        let inputChannel = inputPort.flatMap { input in
            ports.first { $0.portDescription == input.portDescription }?.channel
        }
        let inputType = inputPort.flatMap { $0.typeDescription.isEmpty ? nil : $0.typeDescription }
        return USBPortTopology(ports: ports, inputPortType: inputType, inputChannel: inputChannel)
    }
}

enum USBPortTopologyReader {
    static func read() -> USBPortTopology {
        let usbCPorts = services(IOServiceNameMatching("Port-USB-C"), portNode)
        let devices = services(IOServiceMatching("IOUSBHostDevice"), deviceNode)
        // The adapter's winning source option marks the port the Mac is
        // drawing from; the power-source feature sits under that port.
        let inputPort = services(IOServiceMatching("IOPortFeaturePowerSource")) { entry in
            property(entry, "WinningPowerSourceOption") == nil
                ? nil
                : ancestor(of: entry, maxDepth: 3, where: portNode)
        }.first
        return USBPortTopology.make(usbCPorts: usbCPorts, devices: devices, inputPort: inputPort)
    }

    private static func portNode(_ entry: io_registry_entry_t) -> USBPortTopology.PortNode? {
        guard let description = property(entry, "PortDescription") as? String,
              let number = (property(entry, "PortNumber") as? NSNumber)?.intValue else { return nil }
        let type = property(entry, "PortTypeDescription") as? String ?? ""
        return .init(portDescription: description, portNumber: number, typeDescription: type)
    }

    private static func deviceNode(_ entry: io_registry_entry_t) -> USBPortTopology.DeviceNode? {
        guard let name = property(entry, "USB Product Name") as? String,
              let path = ancestor(of: entry, maxDepth: 8, where: { property($0, "UsbIOPort") as? String }),
              let portDescription = path.split(separator: "/").last.map(String.init) else { return nil }
        return .init(
            portDescription: portDescription,
            name: name,
            deviceClass: (property(entry, "bDeviceClass") as? NSNumber)?.intValue,
            locationID: (property(entry, "locationID") as? NSNumber)?.intValue ?? 0
        )
    }

    /// Maps every matched service and releases it before moving on.
    private static func services<T>(_ matching: CFMutableDictionary?,
                                    _ transform: (io_registry_entry_t) -> T?) -> [T] {
        guard let matching else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var results: [T] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if let value = transform(entry) { results.append(value) }
            IOObjectRelease(entry)
        }
        return results
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Checks the entry itself, then up to `maxDepth` service-plane parents.
    private static func ancestor<T>(of entry: io_registry_entry_t, maxDepth: Int,
                                    where match: (io_registry_entry_t) -> T?) -> T? {
        IOObjectRetain(entry)
        var current = entry
        defer { IOObjectRelease(current) }
        for _ in 0...maxDepth {
            if let found = match(current) { return found }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
        }
        return nil
    }
}
