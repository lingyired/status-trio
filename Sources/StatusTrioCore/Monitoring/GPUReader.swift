import Foundation
import IOKit

struct GPUReading: Equatable, Sendable {
    /// Percent, 0...100, for the busiest online device with a valid reading.
    let usage: Double
    let deviceName: String?
    let sampledAt: Date
}

struct GPUDeviceReading: Sendable {
    let deviceName: String?
    let statistics: [String: Double]
    /// Explicit override for tests and for accelerators that report power state.
    var isOnline: Bool = true
}

struct GPUReader: Sendable {
    func read(at date: Date = Date()) -> GPUReading? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var devices: [GPUDeviceReading] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let raw = Self.property(service, "PerformanceStatistics") as? NSDictionary else { continue }
            var statistics: [String: Double] = [:]
            for key in ["Device Utilization %", "GPU Activity(%)"] {
                guard let number = raw[key] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
                statistics[key] = number.doubleValue
            }
            let online = (Self.property(service, "IOAcceleratorOnline") as? NSNumber)?.boolValue ?? true
            var name = Self.property(service, "IOClass") as? String
            if let model = Self.property(service, "model") as? String, !model.isEmpty {
                name = model
            } else if let data = Self.property(service, "model") as? Data,
                      let decoded = String(data: data, encoding: .utf8) {
                name = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            devices.append(GPUDeviceReading(deviceName: name, statistics: statistics, isOnline: online))
        }
        return Self.select(devices, at: date)
    }

    /// Explicit multi-GPU policy: show the highest valid utilization of an
    /// online device. "Device Utilization %" wins over the legacy
    /// "GPU Activity(%)" field so Apple Silicon is never compared across units.
    /// Never averages unrelated devices, and missing/invalid data is nil, not 0.
    static func select(_ devices: [GPUDeviceReading], at date: Date) -> GPUReading? {
        var selected: GPUReading?
        for device in devices where device.isOnline {
            let usage = ["Device Utilization %", "GPU Activity(%)"].lazy.compactMap { key -> Double? in
                guard let value = device.statistics[key], value.isFinite, (0...100).contains(value) else { return nil }
                return value
            }.first
            guard let usage else { continue }
            if let current = selected, current.usage >= usage { continue }
            selected = GPUReading(usage: usage, deviceName: device.deviceName, sampledAt: date)
        }
        return selected
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
