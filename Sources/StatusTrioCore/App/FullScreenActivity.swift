import AppKit
import CoreGraphics

/// One on-screen window's geometry, normalized out of the CoreGraphics window
/// list dictionary so the classification stays testable without the window
/// server.
struct FullScreenWindowInfo: Equatable {
    var ownerPID: pid_t
    var ownerName: String?
    var layer: Int
    var alpha: Double
    var bounds: CGRect
}

/// Decides whether another application currently owns a whole display — a
/// full-screen Space, a game running full-screen, a borderless-window game, or
/// a full-screen video player.
///
/// The updater must not push a scheduled update alert onto that screen, so it
/// consults this before starting a background check. The probe reads only
/// window geometry/owner/layer from the window server; it needs no Screen
/// Recording permission and never captures pixels.
enum FullScreenActivity {
    /// Owner names that float above a full-screen app and must not be mistaken
    /// for the app that owns the screen.
    private static let ignoredOwnerNames: Set<String> = [
        "Window Server", "Dock", "Control Center", "Notification Center",
    ]

    /// A full-screen window's bounds match a display's bounds exactly; allow a
    /// couple of points for backing-store rounding and notch layouts.
    private static let boundsTolerance: CGFloat = 2

    /// Pure classification used by tests and the live probe.
    ///
    /// `frontmostPID`, when known, is the active application: only its window
    /// counts. This keeps a full-screen game on another display from
    /// suppressing reminders while the user is actively working elsewhere, and
    /// avoids treating a background maximized window as full screen.
    static func isActive(
        windows: [FullScreenWindowInfo],
        displayBounds: [CGRect],
        ownPID: pid_t,
        frontmostPID: pid_t? = nil
    ) -> Bool {
        guard !displayBounds.isEmpty else { return false }
        return windows.contains { window in
            window.layer == 0
                && window.ownerPID != ownPID
                && (frontmostPID.map { window.ownerPID == $0 } ?? true)
                && !(window.ownerName.map { ignoredOwnerNames.contains($0) } ?? false)
                && window.alpha > 0.01
                && displayBounds.contains { covers(window.bounds, $0) }
        }
    }

    private static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        abs(window.minX - display.minX) <= boundsTolerance
            && abs(window.minY - display.minY) <= boundsTolerance
            && abs(window.width - display.width) <= boundsTolerance
            && abs(window.height - display.height) <= boundsTolerance
    }

    /// Live probe. `windows` comes from the on-screen window list (current
    /// Space only), `displays` from CoreGraphics so both share the same global
    /// coordinate space (origin top-left of the main display).
    static func isActive() -> Bool {
        let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return isActive(
            windows: rawWindows.compactMap(windowInfo(from:)),
            displayBounds: activeDisplayBounds(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
    }

    private static func windowInfo(from raw: [String: Any]) -> FullScreenWindowInfo? {
        guard
            let layer = (raw[kCGWindowLayer as String] as? NSNumber)?.intValue,
            let ownerPID = (raw[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            let bounds = rect(from: raw[kCGWindowBounds as String])
        else { return nil }
        return FullScreenWindowInfo(
            ownerPID: ownerPID,
            ownerName: raw[kCGWindowOwnerName as String] as? String,
            layer: layer,
            alpha: (raw[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            bounds: bounds
        )
    }

    private static func rect(from value: Any?) -> CGRect? {
        if let rect = value as? CGRect { return rect }
        guard let dictionary = value as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }
}
