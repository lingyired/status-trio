import Foundation
import IOKit

enum BetterDisplayFramebufferReader {
    static func readInBackground() async -> [BetterDisplayFramebufferIdentity] {
        await Task.detached(priority: .utility) { read() }.value
    }

    static func read() -> [BetterDisplayFramebufferIdentity] {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [BetterDisplayFramebufferIdentity] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            let name = property("IONameMatched", entry: entry) as? String
            let width = property("DisplayWidth", entry: entry) as? Int
            let height = property("DisplayHeight", entry: entry) as? Int
            guard DDCDisplayTransport.isConnectedExternalFramebuffer(
                ioNameMatched: name, displayWidth: width, displayHeight: height
            ) else { continue }
            var path = [CChar](repeating: 0, count: MemoryLayout<io_string_t>.size)
            guard IORegistryEntryGetPath(entry, "IOService", &path) == KERN_SUCCESS else { continue }
            let bytes = path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            result.append(BetterDisplayFramebufferIdentity(
                registryLocation: String(decoding: bytes, as: UTF8.self),
                edidUUID: property("EDID UUID", entry: entry, recursive: true) as? String
            ))
        }
        return result
    }

    private static func property(
        _ key: String, entry: io_registry_entry_t, recursive: Bool = false
    ) -> CFTypeRef? {
        if recursive {
            return IORegistryEntrySearchCFProperty(
                entry, "IOService", key as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively)
            )
        }
        return IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
    }
}
