import AppKit
import CoreGraphics
import Foundation

/// Pure description of one online display, used by the brightness monitor.
///
/// `id` is the stable `CGDisplayCreateUUIDFromDisplayID` string. On Apple
/// Silicon this matches the IORegistry `EDID UUID` used by the DDC resolver, so
/// the same value addresses both the display and its external framebuffer.
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

/// Reads the online display list from CoreGraphics/AppKit.
///
/// Must be called on the main thread: it reads `NSScreen.localizedName`.
struct LiveDisplayCatalog: DisplayCatalogProviding {
    func currentDisplays() -> [DisplayDescriptor] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        let names = Self.screenNames()
        var descriptors: [DisplayDescriptor] = []
        descriptors.reserveCapacity(Int(count))

        for displayID in ids.prefix(Int(count)) {
            let uuid = Self.displayUUIDString(displayID)
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let name = names[displayID] ?? Self.fallbackName(displayID: displayID, isBuiltin: isBuiltin)
            descriptors.append(
                DisplayDescriptor(
                    id: uuid,
                    name: name,
                    isBuiltin: isBuiltin,
                    displayID: displayID
                )
            )
        }

        // Stable order: built-in first, then by name, then by id so a
        // re-enumeration never reshuffles rows.
        return descriptors.sorted { lhs, rhs in
            if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }
    }

    /// `CGDisplayCreateUUIDFromDisplayID` returns a CFUUID whose string form is
    /// the display identity macOS itself uses; on Apple Silicon it equals the
    /// framebuffer `EDID UUID`.
    static func displayUUIDString(_ displayID: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            // Should not happen for an online display; fall back to the numeric
            // id so the row is still addressable, clearly not an EDID UUID.
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
            let displayID = CGDirectDisplayID(number.uint32Value)
            result[displayID] = screen.localizedName
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
