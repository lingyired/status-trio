import IOKit

/// Finds the framebuffer node of each display.
///
/// The node is not called the same on every Mac. Some expose
/// `IOMobileFramebufferShim`; a MacBook Air M3 (t8122) on macOS 27 exposes
/// `AppleCLCD2` instead and has no `IOMobileFramebufferShim` node at all, so
/// matching only the first name finds no display and DDC cannot resolve one.
/// MonitorControl and Lunar accept the same two names as alternatives.
///
/// The list only adds a name: every node the single-name lookup used to find is
/// still found, so Macs that already worked see the same nodes as before.
enum FramebufferEnumeration {
    /// Used both as registry names (`IORegistryEntryGetName`) and as class
    /// names (`IOServiceMatching`); on the Macs observed they are the same.
    static let nodeNames = ["IOMobileFramebufferShim", "AppleCLCD2"]

    /// Calls `body` once per framebuffer entry, de-duplicated by registry entry
    /// ID across the names. The entry is released after `body` returns, so
    /// `body` must not keep it.
    static func forEach(_ body: (io_registry_entry_t) -> Void) {
        var seen: Set<UInt64> = []
        for name in nodeNames {
            var iterator: io_iterator_t = IO_OBJECT_NULL
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(name), &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while true {
                let entry = IOIteratorNext(iterator)
                guard entry != IO_OBJECT_NULL else { break }
                defer { IOObjectRelease(entry) }
                var entryID: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS,
                      seen.insert(entryID).inserted else { continue }
                body(entry)
            }
        }
    }
}
