import Foundation

/// Decides whether a wheel event that reached the panel-wide fallback should
/// change the output volume.
///
/// Sliders, self-handling controls and scrollable views are routed earlier in
/// `StatusBarController` and never reach this decision. This only covers
/// "scroll an empty area of the panel": it is opt-in, summary-only (detail pages
/// must never change volume, issue #324), and still needs a usable output volume
/// control.
enum PanelScrollVolumeFallback {
    static func allows(
        panelScrollEnabled: Bool,
        route: StatusPanelRoute,
        isVolumeControlAvailable: Bool,
        canAdjustVolume: Bool
    ) -> Bool {
        panelScrollEnabled
            && route == .summary
            && isVolumeControlAvailable
            && canAdjustVolume
    }
}
