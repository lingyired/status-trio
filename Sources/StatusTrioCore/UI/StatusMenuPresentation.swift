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
}
