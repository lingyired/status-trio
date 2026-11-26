import AppKit

/// The outcome of preparing the right-click context menu (#302).
enum StatusMenuPresentationDecision: Equatable {
    /// The status item's screen geometry is trustworthy: pop the menu now.
    case present
    /// The status item geometry is briefly unusable (AppKit lifecycle churn, a
    /// display reconfiguration, or a status-bar visibility toggle). Wait one
    /// run-loop turn and try again instead of popping the menu at a stale spot.
    case retry
}

/// Guards the right-click context menu against the transient, wrong geometry
/// AppKit reports around status-item and menu-bar lifecycle changes.
///
/// The panel presentation path already validates the status item's screen rect
/// through `StatusPanelShortcutPresentationPolicy`; the context menu used the
/// button's local bounds directly, so it had no way to notice that the rect was
/// momentarily wrong and could pop up offset from the icon (#302). This policy
/// reuses the same validation and, instead of presenting at a bad anchor, asks
/// for one more frame until the geometry settles.
enum StatusMenuPresentationPolicy {
    /// Extra run-loop turns to wait before presenting with whatever geometry is
    /// available. A status item that received a click is laid out again within a
    /// frame or two, so this only caps the pathological case; it is not a
    /// user-visible delay on the normal path.
    static let maximumRetries = 2

    static func decision(
        menuBarRect: NSRect?,
        isStatusItemVisible: Bool,
        screens: [StatusPanelShortcutScreen],
        attempt: Int
    ) -> StatusMenuPresentationDecision {
        if isStatusItemVisible,
           let menuBarRect,
           StatusPanelShortcutPresentationPolicy.isUsableMenuBarRect(
               menuBarRect,
               screens: screens
           ) {
            return .present
        }
        // After the retry budget the menu is presented anyway rather than
        // swallowing the click; a clickable status item never reaches this
        // branch in practice.
        return attempt < maximumRetries ? .retry : .present
    }

    /// The screen point for the menu's top-left corner: just below the status
    /// item, never inside the menu bar.
    ///
    /// The menu used to be anchored in the status button's own coordinates at
    /// `button.bounds.maxY + 4`. The status item is vertically centred inside
    /// the menu bar, so on macOS 15 (a 38pt notched bar) that point still fell
    /// inside the bar: the menu's top edge started under the menu bar, its first
    /// row (the version line) was clipped, and AppKit turned the menu into a
    /// scrollable one with a chevron — the "version only appears after hovering,
    /// and the menu drops down" bug. macOS 26/27's menu-bar geometry differs, so
    /// the same offset happened to land below the bar. Screen coordinates plus a
    /// clamp to the bar bottom are geometry-independent.
    static func anchorPoint(
        for statusItemScreenRect: NSRect,
        gap: CGFloat = 4,
        menuBarBottom: CGFloat? = nil
    ) -> NSPoint {
        var y = statusItemScreenRect.minY - max(0, gap)
        // Never let the menu's top edge start inside the menu bar strip. The
        // status item is vertically centred in the bar, so "a few points below
        // its bottom" can still land above the bar's lower edge (macOS 15's
        // 38pt bar with a notch). Clamping to the bar bottom guarantees the
        // first row — the version line — is never clipped into a scroll menu.
        if let menuBarBottom {
            y = min(y, menuBarBottom)
        }
        return NSPoint(x: statusItemScreenRect.minX, y: y)
    }
}
