import CoreGraphics

struct StatusIconRenderEnvironment {
    let size: CGFloat
    let scale: CGFloat
    let foreground: CGColor
    let criticalColor: CGColor
    var statusPalette: BatteryStatusColorPalette? = nil
    /// >1 renders onto a larger grid then resamples once to the target pixel
    /// size. Used by the menu-bar path so the SF Symbol does not snap its ink to
    /// the final small pixel grid differently per icon size (#30 residual).
    var supersample: Int = 1
}
