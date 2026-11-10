import AppKit

/// Decides whether another window in this app becoming key or main should close
/// the status panel.
///
/// Issue #267: the panel is a non-activating, borderless `NSPanel`
/// (`AnchoredStatusPanel`), so it has no native "close when another window is
/// clicked" behaviour the way an `NSPopover` does. `installPopoverDismissMonitor`
/// only catches clicks seen by `NSEvent.addGlobalMonitorForEvents`, which never
/// sees clicks inside the same app (e.g. on the app's own Settings window), so
/// the panel stayed on top of the Settings window.
///
/// The controller wires this policy to `NSWindow.didBecomeKeyNotification` and
/// `NSWindow.didBecomeMainNotification`. When an app window is brought to the
/// front (the Settings window after the panel took key on open), the panel
/// closes and focus falls on that window.
struct PanelFocusDismissPolicy: Equatable {
    /// The window that just became key/main, reduced to the descriptors the
    /// policy needs so the decision stays pure and headless-testable.
    struct FocusedWindow: Equatable {
        /// True when the becoming-key/main window *is* the panel itself.
        var isPanel: Bool
        /// Whether the window is on screen.
        var isVisible: Bool
        /// The window's `NSWindow.Level`.
        var level: NSWindow.Level
        /// True when the window is a sheet attached to another window.
        var hasSheetParent: Bool
        /// True when the window has a parent window.
        var hasParent: Bool
    }

    /// A window transition must only dismiss when it brings a real, normal,
    /// top-level window to the front. Never dismiss on:
    ///
    /// - the panel itself becoming key (internal controls, sliders, pop-up
    ///   buttons can transition it without leaving the panel);
    /// - a sheet or alert attached to the panel (`hasSheetParent`);
    /// - a child window (`hasParent`);
    /// - a floating / modal-level window such as a menu or an alert that always
    ///   runs at a higher-than-`.normal` window level. Only a `.normal`-level
    ///   window is a genuine independent window click (the Settings window).
    func shouldDismiss(for candidate: FocusedWindow) -> Bool {
        guard !candidate.isPanel,
              candidate.isVisible,
              candidate.level == .normal,
              !candidate.hasSheetParent,
              !candidate.hasParent else {
            return false
        }
        return true
    }
}