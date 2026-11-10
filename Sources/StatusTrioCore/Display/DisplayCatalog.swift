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
///
/// `displayID` is the real `CGDirectDisplayID` that BetterDisplay and
/// DisplayServices need. For externals it is resolved by correlating the EDID
/// product identity with the online CG display list (`DisplayIDMapper`).
/// `0` means "not reliably resolvable": callers must then treat any backend
/// that needs a CG display id as unavailable rather than defaulting to 0, which
/// CoreGraphics resolves to the built-in display.
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
        let online = onlineDisplayIdentities()
        FramebufferEnumeration.forEach { entry in
            guard let ioNameMatched = stringProperty("IONameMatched", entry: entry),
                  ioNameMatched.hasPrefix("dispext")
            else { return }

            let width = integerProperty("DisplayWidth", entry: entry) ?? 0
            let height = integerProperty("DisplayHeight", entry: entry) ?? 0
            guard width > 0, height > 0,
                  let edidUUID = stringProperty("EDID UUID", entry: entry, recursive: true)
            else { return }

            let product = productInfo(entry: entry)
            let name = product?.name ?? "External Display (\(width)×\(height))"
            result.append(
                mappedExternalDescriptor(
                    edidUUID: edidUUID,
                    name: name,
                    vendorID: product?.vendorID ?? 0,
                    productID: product?.productID ?? 0,
                    serialNumber: product?.serialNumber ?? 0,
                    among: online
                )
            )
        }
        return result
        #else
        return []
        #endif
    }

    /// Builds an external descriptor, resolving its real `CGDirectDisplayID`
    /// from the EDID product identity. Pure and testable: `among` is the online
    /// display snapshot. When the identity cannot be matched (e.g. serial `0`),
    /// a safe single-external fallback applies; otherwise the `0` sentinel is
    /// kept so the monitor reports the display but never guesses another screen.
    static func mappedExternalDescriptor(
        edidUUID: String,
        name: String,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32,
        among online: [DisplayIDMapper.OnlineDisplay]
    ) -> DisplayDescriptor {
        let identity = DisplayIDMapper.ExternalIdentity(
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            edidUUID: edidUUID
        )
        let displayID = DisplayIDMapper.resolvedDisplayID(for: identity, among: online) ?? 0
        return DisplayDescriptor(id: edidUUID, name: name, isBuiltin: false, displayID: displayID)
    }

    /// Snapshot of the online CG displays used to correlate an external
    /// framebuffer with its CG id. Built-in displays are included so the mapper
    /// can explicitly exclude them.
    static func onlineDisplayIdentities() -> [DisplayIDMapper.OnlineDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }
        return ids.prefix(Int(count)).map { displayID in
            DisplayIDMapper.OnlineDisplay(
                displayID: displayID,
                vendorID: CGDisplayVendorNumber(displayID),
                productID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                isBuiltin: CGDisplayIsBuiltin(displayID) != 0
            )
        }
    }

    #if arch(arm64)
    private struct ProductInfo {
        let name: String?
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32
    }

    private static func productInfo(entry: io_registry_entry_t) -> ProductInfo? {
        guard let attributes = IORegistryEntryCreateCFProperty(
            entry,
            "DisplayAttributes" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else { return nil }
        guard let product = attributes["ProductAttributes"] as? [String: Any] else {
            return nil
        }
        return ProductInfo(
            name: product["ProductName"] as? String,
            vendorID: unsignedValue(product["LegacyManufacturerID"]),
            productID: unsignedValue(product["ProductID"]),
            serialNumber: unsignedValue(product["SerialNumber"])
        )
    }

    private static func unsignedValue(_ value: Any?) -> UInt32 {
        if let number = value as? NSNumber { return number.uint32Value }
        if let string = value as? String, let parsed = UInt32(string) { return parsed }
        return 0
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
        // Zero aliases the main display in CG; never turn an unresolved id into
        // another screen's UUID, even if a caller bypasses the monitor's guard.
        guard displayID != 0,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
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
