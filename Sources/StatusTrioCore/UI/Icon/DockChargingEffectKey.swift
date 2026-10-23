/// The cropped charging raster depends only on the ring, its palette and size.
/// Unlike a static Dock key, this includes the complete effect configuration.
struct DockChargingEffectKey: Equatable {
    let outerRing: OuterRingState?
    let backgroundStyle: DockIconBackgroundStyle
    let pixelLength: Int

    init(_ key: DockIconRenderKey) {
        outerRing = key.scene.outerRing
        backgroundStyle = key.backgroundStyle
        pixelLength = key.pixelLength
    }
}
