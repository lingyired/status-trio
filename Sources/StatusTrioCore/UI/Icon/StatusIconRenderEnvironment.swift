import CoreGraphics

struct StatusIconRenderEnvironment {
    let size: CGFloat
    let scale: CGFloat
    let foreground: CGColor
    let criticalColor: CGColor
    var statusPalette: BatteryStatusColorPalette? = nil
}
