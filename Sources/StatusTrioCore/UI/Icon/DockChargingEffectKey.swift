/// The cropped charging raster depends only on the ring, its palette and size.
/// Unlike a static Dock key, this includes the complete effect configuration.
struct DockChargingEffectKey: Equatable {
    let outerRing: OuterRingState?
    let statusColors: BatteryStatusColors
    let backgroundStyle: DockIconBackgroundStyle
    let pixelLength: Int

    init(_ key: DockIconRenderKey) {
        outerRing = key.scene.outerRing
        statusColors = key.scene.statusColors
        backgroundStyle = key.backgroundStyle
        pixelLength = key.pixelLength
    }
}
