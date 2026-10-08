import Testing
@testable import StatusTrioCore

struct ChargingEffectRenderCacheTests {
    @Test func menuBarCacheInvalidatesForEachSteadyPhase() {
        var cache = StatusBarRenderCache()
        let first = menuBarKey(phase: .init(step: 2, stepsPerCycle: 36, kind: .steady))
        let second = menuBarKey(phase: .init(step: 3, stepsPerCycle: 36, kind: .steady))

        #expect(cache.needsRender(first))
        cache.recordSuccessfulRender(first)
        #expect(cache.needsRender(second))
        cache.recordSuccessfulRender(second)
        #expect(cache.needsRender(second) == false)
    }

    @Test func nilMenuBarPhasePreservesStaticKeyDeduplication() {
        var cache = StatusBarRenderCache()
        let omittedPhase = menuBarKey()
        let explicitNilPhase = menuBarKey(phase: nil)

        let rendersStaticKey = cache.needsRender(omittedPhase)
        cache.recordSuccessfulRender(omittedPhase)
        let suppressesDuplicateStaticKey = cache.needsRender(explicitNilPhase)
        #expect(omittedPhase == explicitNilPhase)
        #expect(rendersStaticKey)
        #expect(suppressesDuplicateStaticKey == false)
    }

    @Test func dockCacheDeduplicatesStaticState() {
        var cache = DockIconRenderCache()
        let first = dockKey()
        let second = dockKey()

        let rendersFirst = cache.needsRender(first)
        cache.recordSuccessfulRender(first)
        let suppressesDuplicate = cache.needsRender(second)
        #expect(rendersFirst)
        #expect(!suppressesDuplicate)
    }

    private func menuBarKey(phase: ChargingEffectPhase? = nil) -> StatusBarRenderKey {
        StatusBarRenderKey(
            scene: IconPresentationMapper.scene(
                inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
                configuration: .standard
            ),
            iconSize: 28,
            backingScale: 2,
            appearanceName: "darkAqua",
            phase: phase
        )
    }

    private func dockKey() -> DockIconRenderKey {
        DockIconRenderKey(
            scene: IconPresentationMapper.scene(
                inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
                configuration: .standard
            ),
            backgroundStyle: .dark,
            pixelLength: 512
        )
    }
}
