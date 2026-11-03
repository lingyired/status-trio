import IOKit

/// Finds the framebuffer node of each display.
///
/// The node's class name is not the same on every Apple Silicon Mac, and the
/// split follows the chip rather than the macOS version. Measured across the
/// community corpus (Monitor Control, Lunar, AppleSiliconDDC, WhatCable):
///
/// - `AppleCLCD2` on the M1 family, M2 and M3 (e.g. the MacBook Air M3 /
///   t8122 on macOS 27, which publishes no `IOMobileFramebufferShim` at all).
/// - `IOMobileFramebufferShim` on M2 Pro/Max/Ultra, M3 Pro/Max, and every M4/M5.
///
/// Matching only one name finds no display on the other half of the fleet and
/// DDC cannot resolve one. All three community implementations above accept
/// exactly these two names.
///
/// There is no stable common ancestor class to match instead: older macOS hung
/// both leaves under `IOMobileFramebufferAP` (Stillcolor relies on that), but on
/// macOS 27 the nodes hang directly off `AppleARMIODevice`, so an ancestor match
/// returns nothing here. To keep a future rename from silently breaking DDC
/// again, `forEach` matches the known class names first and, only when that
/// finds no node at all, falls back to a name-agnostic scan that recognizes an
/// external framebuffer by property (`IONameMatched` is a `dispextN` branch and
/// the node reports a non-zero display size).
enum FramebufferEnumeration {
    /// Known framebuffer class names. Used both as registry names
    /// (`IORegistryEntryGetName`) and as class names (`IOServiceMatching`);
    /// on the Macs observed they are the same.
    static let nodeNames = ["IOMobileFramebufferShim", "AppleCLCD2"]

    /// Calls `body` once per framebuffer entry, de-duplicated by registry entry
    /// ID. The entry is released after `body` returns, so `body` must not keep it.
    ///
    /// Fast path: services whose class is one of `nodeNames`. If that finds no
    /// node at all on this Mac, the class was renamed, so a property-based scan
    /// of the whole IOService plane takes over.
    static func forEach(_ body: (io_registry_entry_t) -> Void) {
        var seen: Set<UInt64> = []
        var matchedKnownClass = false
        for name in nodeNames {
            enumerateServices(matching: name) { entry in
                guard record(entry, in: &seen) else { return }
                matchedKnownClass = true
                body(entry)
            }
        }
        guard !matchedKnownClass else { return }

        // Fallback: no node of a known class exists, so find external
        // framebuffers by the properties they publish instead of by name.
        // External DDC is Apple-Silicon-only, so build the scan for arm64 only.
        #if arch(arm64)
        enumerateAllServices { entry in
            guard isExternalFramebuffer(entry), record(entry, in: &seen) else { return }
            body(entry)
        }
        #endif
    }

    /// A node is an external-display framebuffer when its matched name is a
    /// `dispextN` branch and it reports a non-zero display size. Empty external
    /// slots publish `dispextN` without a size and are excluded. This is the
    /// name-agnostic predicate the fallback relies on.
    static func isExternalFramebuffer(_ entry: io_registry_entry_t) -> Bool {
        isExternalFramebuffer(
            ioNameMatched: stringProperty("IONameMatched", entry: entry),
            displayWidth: integerProperty("DisplayWidth", entry: entry),
            displayHeight: integerProperty("DisplayHeight", entry: entry)
        )
    }

    /// Value-based overload, kept free of IOKit so it can be unit-tested.
    static func isExternalFramebuffer(
        ioNameMatched: String?,
        displayWidth: Int?,
        displayHeight: Int?
    ) -> Bool {
        guard let ioNameMatched, ioNameMatched.hasPrefix("dispext"),
              let displayWidth, let displayHeight else { return false }
        return displayWidth > 0 && displayHeight > 0
    }

    // MARK: - IOKit plumbing

    private static func record(_ entry: io_registry_entry_t, in seen: inout Set<UInt64>) -> Bool {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS else { return false }
        return seen.insert(entryID).inserted
    }

    private static func enumerateServices(
        matching className: String,
        _ body: (io_registry_entry_t) -> Void
    ) {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(className), &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            body(entry)
            IOObjectRelease(entry)
        }
    }

    #if arch(arm64)
    private static func enumerateAllServices(_ body: (io_registry_entry_t) -> Void) {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryCreateIterator(
            root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            body(entry)
            IOObjectRelease(entry)
        }
    }
    #endif

    private static func stringProperty(_ key: String, entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func integerProperty(_ key: String, entry: io_registry_entry_t) -> Int? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}
