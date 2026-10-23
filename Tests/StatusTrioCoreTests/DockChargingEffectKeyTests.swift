import Testing
@testable import StatusTrioCore

@MainActor
struct DockChargingEffectKeyTests {
    @Test func fullRingConfigurationControlsTheEffectIdentity() {
        let normal = OuterRingState(segments: [RingSegmentState(progress: 0.5, color: .powered)],
            gap: .indicator, effect: RingEffectState(pulsesAccessory: true, tintsAccessory: true))
        let base = key(normal)
        let rings = [
            OuterRingState(segments: [RingSegmentState(progress: 0.8, color: .powered)],
                gap: normal.gap, effect: normal.effect),
            OuterRingState(segments: [RingSegmentState(progress: 0.5, color: .critical)],
                gap: normal.gap, effect: normal.effect),
            OuterRingState(segments: normal.segments, gap: .value, effect: normal.effect),
            OuterRingState(segments: normal.segments, gap: normal.gap,
                accessory: .text(IconTextState(text: "42", color: .primary, scale: 1)), effect: normal.effect),
            OuterRingState(segments: normal.segments, gap: normal.gap,
                effect: RingEffectState(pulsesAccessory: false, tintsAccessory: true)),
            OuterRingState(segments: normal.segments, gap: normal.gap, effect: normal.effect, strokeScale: 2),
            OuterRingState(segments: normal.segments, gap: normal.gap)
        ]
        for ring in rings { #expect(key(ring) != base) }
        #expect(key(normal, style: .light) != base)
        #expect(key(normal, length: 256) != base)
    }

    @Test func centreChangesDoNotInvalidateTheRingEffect() {
        let ring = OuterRingState(segments: [], gap: .closed)
        let scene = IconSceneState(outerRing: ring,
            center: .text(IconTextState(text: "A", color: .primary, scale: 1)))
        let changed = DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128)
        #expect(DockChargingEffectKey(changed) == key(ring))
    }

    private func key(_ ring: OuterRingState, style: DockIconBackgroundStyle = .dark,
                     length: Int = 128) -> DockChargingEffectKey {
        DockChargingEffectKey(DockIconRenderKey(scene: IconSceneState(outerRing: ring),
            backgroundStyle: style, pixelLength: length))
    }
}
