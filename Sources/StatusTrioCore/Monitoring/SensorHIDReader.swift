import Foundation
import CoreFoundation
import Darwin
import OSLog

private let hidTemperatureLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "hardware-temperature"
)

/// One discovered HID temperature service. `index` is the position in the
/// cached service array; the transport uses it to fetch the matching service.
struct HIDServiceDescriptor: Equatable, Sendable {
    let index: Int
    let name: String
}

/// Thin, injectable seam over the HID event system. The live implementation
/// resolves the private IOKit symbols at runtime; tests supply a fake.
protocol HIDTemperatureTransport: AnyObject {
    func open() -> Bool
    func discoverServices() -> [HIDServiceDescriptor]?
    func readTemperature(of service: HIDServiceDescriptor) -> Double?
    func close()
}

/// Reads the CPU/GPU die temperatures from the Apple HID event system.
///
/// This type exists only to serve the confirmed-broken SMC path on base Apple
/// M1. It lazily opens one event-system client, caches the service list,
/// re-discovers it at most every 60 seconds (5 seconds after a missing event),
/// and only touches the services a caller actually asked for. All calls run
/// off the main actor, on HardwareSampler's utility queue.
final class SensorHIDReader: @unchecked Sendable {
    static let temperatureEventType: Int64 = 15
    static let temperatureField: Int32 = 15 << 16
    static let usagePage: Int32 = 0xff00
    static let usage: Int32 = 0x0005
    /// Reject obviously bogus values so one bad sensor cannot poison the mean.
    static let validTemperatureRange: ClosedRange<Double> = -40...150
    static let normalDiscoveryInterval: TimeInterval = 60
    static let missingEventDiscoveryInterval: TimeInterval = 5

    private let transport: HIDTemperatureTransport
    private var services: [HIDServiceDescriptor] = []
    private var lastDiscovery: Date?
    private var missingEvents = false
    private var isOpen = false

    init(transport: HIDTemperatureTransport = LiveHIDTemperatureTransport()) {
        self.transport = transport
    }

    deinit {
        if isOpen { transport.close() }
    }

    /// Returns the arithmetic mean of every valid CPU/GPU sensor that belongs
    /// to a requested target. Sensors for a target not in `targets` are never
    /// read, so a CPU-only demand issues zero GPU event calls.
    func read(targets: Set<TemperatureMetric>,
              at date: Date) -> [TemperatureMetric: TemperatureMeasurement] {
        guard !targets.isEmpty else { return [:] }
        guard ensureOpen() else { return [:] }
        refreshServicesIfNeeded(at: date)
        guard !services.isEmpty else { return [:] }

        missingEvents = false
        var cpuValues: [Double] = []
        var gpuValues: [Double] = []
        for service in services {
            if targets.contains(.cpu), Self.isCPUSensor(service.name) {
                if let value = validTemperature(service) {
                    cpuValues.append(value)
                } else {
                    missingEvents = true
                }
            } else if targets.contains(.gpu), Self.isGPUSensor(service.name) {
                if let value = validTemperature(service) {
                    gpuValues.append(value)
                } else {
                    missingEvents = true
                }
            }
        }

        var result: [TemperatureMetric: TemperatureMeasurement] = [:]
        if targets.contains(.cpu), let value = Self.average(cpuValues) {
            result[.cpu] = TemperatureMeasurement(value: value, count: cpuValues.count)
        }
        if targets.contains(.gpu), let value = Self.average(gpuValues) {
            result[.gpu] = TemperatureMeasurement(value: value, count: gpuValues.count)
        }
        return result
    }

    /// Releases the client and cached services. Safe to call repeatedly.
    func release() {
        if isOpen { transport.close() }
        isOpen = false
        services = []
        lastDiscovery = nil
        missingEvents = false
    }

    private func ensureOpen() -> Bool {
        if isOpen { return true }
        guard transport.open() else { return false }
        isOpen = true
        return true
    }

    private func refreshServicesIfNeeded(at date: Date) {
        let interval = missingEvents ? Self.missingEventDiscoveryInterval : Self.normalDiscoveryInterval
        if !services.isEmpty, let lastDiscovery,
           date.timeIntervalSince(lastDiscovery) < interval {
            return
        }
        guard let discovered = transport.discoverServices(), !discovered.isEmpty else {
            release()
            return
        }
        services = discovered
        lastDiscovery = date
        #if DEBUG
        hidTemperatureLogger.debug("HID service discovery count=\(discovered.count)")
        #endif
    }

    private func validTemperature(_ service: HIDServiceDescriptor) -> Double? {
        guard let raw = transport.readTemperature(of: service),
              raw.isFinite,
              Self.validTemperatureRange.contains(raw) else { return nil }
        return raw
    }

    static func isCPUSensor(_ name: String) -> Bool {
        guard !isExcluded(name) else { return false }
        return name.contains("pACC MTR Temp Sensor") || name.contains("eACC MTR Temp Sensor")
    }

    static func isGPUSensor(_ name: String) -> Bool {
        guard !isExcluded(name) else { return false }
        return name.contains("GPU MTR Temp Sensor")
    }

    private static func isExcluded(_ name: String) -> Bool {
        let excluded = ["PMU", "SOC", "NAND", "Battery", "gas gauge", "ANE"]
        return excluded.contains { name.localizedCaseInsensitiveContains($0) }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// Runtime-resolved bridge to the HID event system. The symbols are private
/// IOKit exports, so they are loaded with `dlsym` instead of linked; if the
/// platform does not expose them, `open()` fails and the caller stays on the
/// unavailable path without crashing.
final class LiveHIDTemperatureTransport: HIDTemperatureTransport, @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int64, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer, Int32) -> Double

    private let create: CreateFn?
    private let setMatching: SetMatchingFn?
    private let copyServices: CopyServicesFn?
    private let copyProperty: CopyPropertyFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?

    private var client: UnsafeMutableRawPointer?
    private var serviceArray: CFArray?

    init() {
        create = Self.load("IOHIDEventSystemClientCreate", as: CreateFn.self)
        setMatching = Self.load("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self)
        copyServices = Self.load("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self)
        copyProperty = Self.load("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self)
        copyEvent = Self.load("IOHIDServiceClientCopyEvent", as: CopyEventFn.self)
        getFloat = Self.load("IOHIDEventGetFloatValue", as: GetFloatFn.self)
    }

    deinit {
        close()
    }

    func open() -> Bool {
        if client != nil { return true }
        guard let create, let setMatching else { return false }
        guard let created = create(kCFAllocatorDefault) else { return false }
        let matching = [
            "PrimaryUsagePage": SensorHIDReader.usagePage,
            "PrimaryUsage": SensorHIDReader.usage
        ] as CFDictionary
        setMatching(created, matching)
        client = created
        return true
    }

    func discoverServices() -> [HIDServiceDescriptor]? {
        guard let client, let copyServices else { return nil }
        guard let array = copyServices(client)?.takeRetainedValue() else { return nil }
        serviceArray = array
        let count = CFArrayGetCount(array)
        var result: [HIDServiceDescriptor] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
            let service = UnsafeRawPointer(raw)
            var name = ""
            if let property = copyProperty?(service, "Product" as CFString)?.takeRetainedValue(),
               let text = property as? String {
                name = text
            }
            result.append(HIDServiceDescriptor(index: index, name: name))
        }
        return result
    }

    func readTemperature(of service: HIDServiceDescriptor) -> Double? {
        guard let array = serviceArray, let copyEvent, let getFloat else { return nil }
        guard service.index < CFArrayGetCount(array),
              let raw = CFArrayGetValueAtIndex(array, service.index) else { return nil }
        guard let event = copyEvent(UnsafeRawPointer(raw),
                                    SensorHIDReader.temperatureEventType, 0, 0) else { return nil }
        let value = getFloat(UnsafeRawPointer(event), SensorHIDReader.temperatureField)
        Unmanaged<CFTypeRef>.fromOpaque(event).release()
        return value
    }

    func close() {
        serviceArray = nil
        if let client {
            Unmanaged<CFTypeRef>.fromOpaque(client).release()
            self.client = nil
        }
    }

    private static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
