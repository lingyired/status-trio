import Foundation
import IOKit

/// Enumerates every IOAccelerator client and sums its cumulative GPU time.
/// This intentionally keeps clients with an unparseable creator: their time is
/// still part of the attribution denominator, just not attributable to an app.
struct ApplicationGPUClientReader: Sendable {
    enum Outcome: Sendable {
        case unsupported
        case failed
        case clients([RawGPUClient])
    }

    struct RawGPUClient: Equatable, Sendable {
        let entryID: UInt64
        let pid: Int32?
        let name: String
        let gpuTime: UInt64
        let queueCount: Int
    }

    let isSupported: @Sendable () -> Bool

    init(isSupported: @escaping @Sendable () -> Bool = Self.supportsGPUUsageClients) {
        self.isSupported = isSupported
    }

    static func supportsGPUUsageClients() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    func read() -> Outcome {
        guard isSupported() else { return .unsupported }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else {
            return .failed
        }
        defer { IOObjectRelease(iterator) }

        var clients: [RawGPUClient] = []
        var seenEntryIDs: Set<UInt64> = []
        var sawAccelerator = false
        var sawUsageField = false
        var accelerator = IOIteratorNext(iterator)
        while accelerator != 0 {
            sawAccelerator = true
            let service = accelerator
            defer { IOObjectRelease(service) }

            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == kIOReturnSuccess else {
                return .failed
            }
            defer { IOObjectRelease(children) }

            var child = IOIteratorNext(children)
            while child != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                var entryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(child, &entryID) == kIOReturnSuccess,
                   IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                    if dictionary["AppUsage"] != nil { sawUsageField = true }
                    if let client = Self.parseClient(properties: dictionary, entryID: entryID),
                       seenEntryIDs.insert(entryID).inserted {
                        clients.append(client)
                    }
                }
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
            guard IOIteratorIsValid(children) != 0 else { return .failed }
            accelerator = IOIteratorNext(iterator)
        }
        guard IOIteratorIsValid(iterator) != 0 else { return .failed }
        guard sawAccelerator, sawUsageField else { return .unsupported }
        return .clients(clients)
    }

    static func parseClient(properties: [String: Any], entryID: UInt64) -> RawGPUClient? {
        guard let usage = properties["AppUsage"] as? [Any] else { return nil }
        var totalTime: UInt64 = 0
        var queueCount = 0
        for element in usage {
            guard let entry = element as? [String: Any] else { continue }
            if let value = numberValue(entry["accumulatedGPUTime"]) {
                totalTime &+= value
            }
            if let value = numberValue(entry["accumulatedGPUQueueCount"]) {
                queueCount += Int(clamping: value)
            }
        }
        guard totalTime > 0 || queueCount > 0 else { return nil }

        let creator = properties["IOUserClientCreator"] as? String
        let parsed = creator.flatMap(GPUClientParser.parseCreator)
        return RawGPUClient(entryID: entryID,
                            pid: parsed?.pid,
                            name: parsed?.name ?? "GPU Client",
                            gpuTime: totalTime,
                            queueCount: queueCount)
    }

    private static func numberValue(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return value >= 0 ? UInt64(value) : nil }
        return nil
    }
}
