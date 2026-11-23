// Collection strategy adapted from Stats (MIT License):
// https://github.com/exelban/stats

import Foundation
import IOKit

struct GPUClientCounter: Equatable, Sendable {
    let entryID: UInt64
    let metadata: ProcessMetadata
    let gpuTime: UInt64
    let queueCount: Int
}

/// Converts cumulative GPU execution time into a percentage of wall time.
/// A client that disappears, changes owner or has a counter reset must not
/// carry its old baseline forward.
struct GPUAppUsageTracker: Sendable {
    private struct Baseline: Sendable {
        let identity: ProcessIdentity
        let gpuTime: UInt64
        let queueCount: Int
    }

    private var baselines: [UInt64: Baseline] = [:]
    private var timestamp: UInt64?

    mutating func reset() {
        baselines.removeAll()
        timestamp = nil
    }

    mutating func sample(_ clients: [GPUClientCounter],
                         at uptimeNanoseconds: UInt64) -> [ProcessUsageSample]? {
        let previous = baselines
        let previousTimestamp = timestamp

        var next: [UInt64: Baseline] = [:]
        for client in clients {
            guard client.metadata.identity.isStable else { continue }
            next[client.entryID] = Baseline(identity: client.metadata.identity,
                                            gpuTime: client.gpuTime,
                                            queueCount: client.queueCount)
        }

        guard let previousTimestamp,
              uptimeNanoseconds > previousTimestamp else {
            timestamp = uptimeNanoseconds
            baselines = next
            return nil
        }
        let elapsed = uptimeNanoseconds - previousTimestamp
        guard elapsed <= 3_000_000_000 else {
            timestamp = uptimeNanoseconds
            baselines = next
            return nil
        }
        guard elapsed >= 250_000_000 else { return nil }

        timestamp = uptimeNanoseconds
        baselines = next

        var samples: [ProcessUsageSample] = []
        for client in clients {
            guard client.metadata.identity.isStable,
                  let baseline = previous[client.entryID],
                  baseline.identity == client.metadata.identity,
                  baseline.queueCount == client.queueCount,
                  client.gpuTime >= baseline.gpuTime else { continue }
            let delta = client.gpuTime - baseline.gpuTime
            let percent = Double(delta) * 100 / Double(elapsed)
            samples.append(ProcessUsageSample(metadata: client.metadata, value: percent))
        }
        return samples
    }
}

enum GPUClientParseResult: Equatable, Sendable {
    case noCreator
    case noUsage
    case client(GPUClientCounter)
}

enum GPUClientParser {
    static func parse(properties: [String: Any],
                      entryID: UInt64,
                      metadataReader: any ProcessMetadataReading) -> GPUClientParseResult {
        guard let creator = properties["IOUserClientCreator"] as? String,
              let parsed = parseCreator(creator) else {
            return .noCreator
        }
        guard let usage = properties["AppUsage"] as? [Any], !usage.isEmpty else {
            return .noUsage
        }

        var totalTime: UInt64 = 0
        var queueCount = 0
        var sawTime = false
        for element in usage {
            guard let entry = element as? [String: Any] else { continue }
            if let value = numberValue(entry["accumulatedGPUTime"]) {
                totalTime &+= value
                sawTime = true
            }
            if let queues = numberValue(entry["accumulatedGPUQueueCount"]) {
                queueCount += Int(queues)
            }
        }
        guard sawTime else { return .noUsage }

        let metadata = metadataReader.metadata(for: parsed.pid, fallbackName: parsed.name)
            ?? ProcessMetadata(identity: ProcessIdentity(pid: parsed.pid, startedAt: nil),
                               name: parsed.name, executablePath: nil, responsiblePID: nil)
        return .client(GPUClientCounter(entryID: entryID,
                                         metadata: metadata,
                                         gpuTime: totalTime,
                                         queueCount: queueCount))
    }

    static func parseCreator(_ creator: String) -> (pid: Int32, name: String)? {
        let trimmed = creator.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("pid "),
              let comma = trimmed.firstIndex(of: ",") else { return nil }
        let pidText = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<comma]
            .trimmingCharacters(in: .whitespaces)
        guard let pid = Int32(pidText) else { return nil }
        let name = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return (pid, name)
    }

    private static func numberValue(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return value >= 0 ? UInt64(value) : nil }
        return nil
    }
}

struct TopAppGPUReader: Sendable {
    let isSupported: @Sendable () -> Bool
    let metadataReader: any ProcessMetadataReading

    init(isSupported: @escaping @Sendable () -> Bool = Self.supportsGPUUsageClients,
         metadataReader: any ProcessMetadataReading = SystemProcessMetadataReader()) {
        self.isSupported = isSupported
        self.metadataReader = metadataReader
    }

    static func supportsGPUUsageClients() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    func read() -> Result<[GPUClientCounter], TopAppReadError> {
        guard isSupported() else { return .failure(.unsupported) }
        return readClients()
    }

    private func readClients() -> Result<[GPUClientCounter], TopAppReadError> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else {
            return .failure(.malformedOutput)
        }
        defer { IOObjectRelease(iterator) }

        var clients: [GPUClientCounter] = []
        var sawAccelerator = false
        var sawUsageField = false
        var accelerator = IOIteratorNext(iterator)
        while accelerator != 0 {
            sawAccelerator = true
            let service = accelerator
            defer { IOObjectRelease(service) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == kIOReturnSuccess else {
                return .failure(.malformedOutput)
            }
            defer { IOObjectRelease(children) }

            var child = IOIteratorNext(children)
            while child != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                var entryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(child, &entryID) == kIOReturnSuccess,
                   IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                    switch GPUClientParser.parse(properties: dictionary,
                                                 entryID: entryID,
                                                 metadataReader: metadataReader) {
                    case .client(let client):
                        clients.append(client)
                        sawUsageField = true
                    case .noUsage:
                        sawUsageField = true
                    case .noCreator:
                        break
                    }
                }
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
            guard IOIteratorIsValid(children) != 0 else { return .failure(.malformedOutput) }
            accelerator = IOIteratorNext(iterator)
        }
        guard IOIteratorIsValid(iterator) != 0 else { return .failure(.malformedOutput) }
        guard sawAccelerator else { return .failure(.unsupported) }
        guard sawUsageField else { return .failure(.unsupported) }
        return .success(clients)
    }
}
