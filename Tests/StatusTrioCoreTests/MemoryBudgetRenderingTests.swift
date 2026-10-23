import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct MemoryBudgetRenderingTests {
    @Test func realDockImagesHoldAtMostFourMiBAndReleaseOnReset() throws {
        let cache = DockIconImageCache()
        for level in stride(from: 4, through: 92, by: 8) {
            let scene = scene(level: level)
            let image = try #require(DockIconRenderer.image(scene: scene))
            cache.store(image, for: DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 512))
        }
        #expect(cache.entryCount == 4)
        #expect(cache.residentByteCount == 4 * 1024 * 1024)
        print("MEMORY_BUDGET static cached_bytes=\(cache.residentByteCount)")
        cache.reset()
        #expect(cache.residentByteCount == 0)
    }

    @Test func largeFrameVariantConstructionDoesNotRetainTwoCompleteGroups() throws {
        let scene = scene()
        let key = DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 512)
        let cache = DockChargingFrameCache()
        var frameBytes = 0
        for multiplier in [1.0, 1.35] {
            let frame = try #require(cache.image(for: phase(0, multiplier: multiplier), key: key) { phase in
                DockIconRenderer.chargingEffectImage(scene: scene, phase: phase,
                    backgroundStyle: .dark, pixelLength: 512)
            })
            frameBytes = frame.bytesPerRow * frame.height
        }
        #expect(cache.variantCount == 1)
        #expect(cache.peakResidentByteCount <= cache.residentByteCount + frameBytes)
        print("MEMORY_BUDGET dock512 retained_bytes=\(cache.residentByteCount) peak_building_bytes=\(cache.peakResidentByteCount)")
        cache.reset()
        #expect(cache.residentByteCount == 0)
    }

    @Test func pressureRetainsTheActiveAnimationGroupWithoutTickRebuilds() throws {
        let scene = scene()
        let key = DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128)
        let cache = DockChargingFrameCache()
        for multiplier in [1.0, 1.35] {
            _ = try #require(cache.image(for: phase(0, multiplier: multiplier), key: key) { phase in
                DockIconRenderer.chargingEffectImage(scene: scene, phase: phase,
                    backgroundStyle: .dark, pixelLength: 128)
            })
        }
        #expect(cache.variantCount == 2)
        let rebuilds = cache.rebuildCount
        for step in 0..<100 {
            cache.trimForMemoryPressure()
            _ = try #require(cache.image(for: phase(step % 36, multiplier: 1.35), key: key) { _ in
                Issue.record("Pressure must not rebuild the active group per tick")
                return nil
            })
        }
        #expect(cache.variantCount == 1)
        #expect(cache.rebuildCount == rebuilds)
    }

    @Test func scratchContextsAreBudgetedAndCanBeReleasedWithoutChangingOutput() throws {
        for length in stride(from: 128, through: 512, by: 64) {
            _ = try #require(DockIconRenderer.tileImage(scene: scene(), backgroundStyle: .dark,
                pixelLength: length))
        }
        #expect(DockIconRenderer.scratchResidentByteCount > 0)
        #expect(DockIconRenderer.scratchResidentByteCount <= 4 * 1024 * 1024)
        DockIconRenderer.resetScratchContexts()
        #expect(DockIconRenderer.scratchResidentByteCount == 0)
        _ = try #require(DockIconRenderer.tileImage(scene: scene(), backgroundStyle: .dark))
    }

    private func phase(_ step: Int, multiplier: Double) -> ChargingEffectPhase {
        ChargingEffectPhase(step: step, stepsPerCycle: 36, kind: .steady, heartbeatMultiplier: multiplier)
    }

    private func scene(level: Int = 62) -> IconSceneState {
        IconPresentationMapper.scene(inputs: IconPresentationInputs(snapshot: StatusSnapshot(
            battery: BatteryStatus(rawPercentage: level, isPresent: true, isCharging: true,
                isLowPowerMode: false, isConnectedToPower: true),
            wifi: WiFiStatus(state: .connected, rssi: -50), connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")), audioIcon: nil),
            configuration: .standard)
    }
}
