import Foundation

/// Keeps the battery details page inside a menu-bar popover even when every
/// optional section is visible. The scrollable middle region is capped so the
/// fixed back row and the action controls below it always stay on screen.
enum BatteryDetailsLayoutPolicy {
    /// Back row, low-power control, Charge to Full Now area, settings buttons,
    /// dividers, and the page's outer padding.
    static let fixedChromeHeight: CGFloat = 300
    /// Never scroll away so much content that the page looks broken.
    static let minimumContentHeight: CGFloat = 260

    static func contentHeightLimit(visibleHeight: CGFloat) -> CGFloat {
        max(minimumContentHeight, visibleHeight - fixedChromeHeight)
    }
}
