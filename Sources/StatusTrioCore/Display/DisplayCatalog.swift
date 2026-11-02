import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Pure description of one display, used by the brightness monitor.
///
/// `id` is the identity the brightness backend keys on:
/// - External displays: the IORegistry `EDID UUID`, which is exactly the UID the
///   direct-DDC resolver matches a framebuffer by.
/// - Built-in displays: the `CGDisplayCreateUUID` string, which is what
///   BetterDisplay addresses them with.
///
/// Using the DDC UID for externals matters: `CGDisplayCreateUUIDFromDisplayID`
/// and the framebuffer `EDID UUID` are *different* strings on Apple Silicon, so
/// keying DDC by the CG UUID never matches a framebuffer.
struct DisplayDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let isBuiltin: Bool
    let displayID: UInt32

    init(id: String, name: String, isBuiltin: Bool, displayID: UInt32) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.displayID = displayID
    }
}

/// Source of the current display list. Separated from `LiveDisplayCatalog` so
/// the monitor and tests can inject a fixed list without touching CoreGraphics.
protocol DisplayCatalogProviding {
    func currentDisplays() -> [DisplayDescriptor]
}

/// Reads the online display list.
///
/// External displays come from the IORegistry framebuffers (so the `EDID UUID`
/// is available for DDC); built-in displays come from CoreGraphics (name and CG
/// UUID for BetterDisplay). Must be called on the main thread: it reads
/// `NSScreen.localizedName`.
struct LiveDisplayCatalog: DisplayCatalogProviding {
    func currentDisplays() -> [DisplayDescriptor] {
        var displays: [DisplayDescriptor] = []
        displays.append(contentsOf: Self.externalDisplaysFromRegistry())

        let builtin = Self.coreGraphicsDisplays(onlyBuiltin: true)
        displays.append(contentsOf: builtin)

        // If the registry could not describe any external display (unexpected on
        // Apple Silicon), fall back to CoreGraphics so the row still appears.
        // DDC may fail to resolve in that case, which is reported honestly.
        if !displays.contains(where: { !$0.isBuiltin }) {
            displays.append(contentsOf: Self.coreGraphicsDisplays(onlyBuiltin: false))
        }

        return Self.sorted(displays)
    }

    static func sorted(_ displays: [DisplayDescriptor]) -> [DisplayDescriptor] {
        displays.sorted { lhs, rhs in
            if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }
    }

    // MARK: - External (IORegistry)

    private static func externalDisplaysFromRegistry() -> [DisplayDescriptor] {
        #if arch(arm64)
        var result: [DisplayDescriptor] = []
        FramebufferEnumeration.forEach { entry in
            guard let ioNameMatched = stringProperty("IONameMatched", entry: entry),
                  ioNameMatched.hasPrefix("dispext")
            else { return }

            let width = integerProperty("DisplayWidth", entry: entry) ?? 0
            let height = integerProperty("DisplayHeight", entry: entry) ?? 0
            guard width > 0, height > 0,
                  let edidUUID = stringProperty("EDID UUID", entry: entry, recursive: true)
            else { return }

            let name = productName(entry: entry) ?? "External Display (\(width)×\(height))"
            result.append(
                DisplayDescriptor(
                    id: edidUUID,
                    name: name,
                    isBuiltin: false,
                    displayID: 0
                )
            )
        }
        return result
        #else
        return []
        #endif
    }

    #if arch(arm64)
    private static func productName(entry: io_registry_entry_t) -> String? {
        guard let attributes = IORegistryEntryCreateCFProperty(
            entry,
            "DisplayAttributes" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else { return nil }
        guard let product = attributes["ProductAttributes"] as? [String: Any] else {
            return nil
        }
        return product["ProductName"] as? String
    }

    private static func stringProperty(
        _ key: String,
        entry: io_registry_entry_t,
        recursive: Bool = false
    ) -> String? {
        let options = recursive ? IOOptionBits(kIORegistryIterateRecursively) : 0
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            options
        )?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func integerProperty(
        _ key: String,
        entry: io_registry_entry_t
    ) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        return value as? Int
    }
    #endif

    // MARK: - Built-in (CoreGraphics)

    private static func coreGraphicsDisplays(onlyBuiltin: Bool) -> [DisplayDescriptor] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        let names = screenNames()
        var result: [DisplayDescriptor] = []
        for displayID in ids.prefix(Int(count)) {
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            guard isBuiltin == onlyBuiltin else { continue }
            result.append(
                DisplayDescriptor(
                    id: displayUUIDString(displayID),
                    name: names[displayID] ?? fallbackName(displayID: displayID, isBuiltin: isBuiltin),
                    isBuiltin: isBuiltin,
                    displayID: displayID
                )
            )
        }
        return result
    }

    static func displayUUIDString(_ displayID: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-\(displayID)"
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var result: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else {
                continue
            }
            result[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }
        return result
    }

    private static func fallbackName(
        displayID: CGDirectDisplayID,
        isBuiltin: Bool
    ) -> String {
        let width = CGDisplayPixelsWide(displayID)
        let height = CGDisplayPixelsHigh(displayID)
        if width > 0, height > 0 {
            return "\(width)×\(height)"
        }
        return isBuiltin ? "Built-in Display" : "External Display"
    }
}
