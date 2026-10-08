import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectFrameCacheTests {
    @Test func preRendersThirtySixSteadyFramesOnceAndReusesThemAcrossTicks() {
        let cache = StatusBarChargingFrameCache()
        let firstPhase = steadyPhase(step: 4)
        let firstKey = makeKey(phase: firstPhase)
        var renderedSteps: [Int] = []
        var renderedImages: [NSImage] = []

        let firstImage = cache.image(
            for: firstPhase,
            key: firstKey,
            backingScale: 2
        ) { phase in
            renderedSteps.append(phase.step)
            let image = NSImage(size: NSSize(width: 22, height: 22))
            renderedImages.append(image)
            return image
        }

        #expect(renderedSteps == Array(0..<36))
        #expect(firstImage === renderedImages[4])

        let nextPhase = steadyPhase(step: 5)
        let unexpectedRenderer: (ChargingEffectPhase) -> NSImage? = { _ in
            Issue.record("A cached steady frame should not be rasterized again.")
            return nil
        }
        let nextImage = cache.image(
            for: nextPhase,
            key: makeKey(phase: nextPhase),
            backingScale: 2,
            renderFrame: unexpectedRenderer
        )

        #expect(nextImage === renderedImages[5])
        #expect(renderedSteps.count == 36)
    }

    @Test func rebuildsTheFrameSetWhenStatusScaleOrHeartbeatVariantChanges() {
        let cache = StatusBarChargingFrameCache()
        var renderedFrameCount = 0
        let phase = steadyPhase(step: 0)
        let originalKey = makeKey(phase: phase)
        let renderFrame: (ChargingEffectPhase) -> NSImage? = { _ in
            renderedFrameCount += 1
            return NSImage(size: NSSize(width: 22, height: 22))
        }

        _ = cache.image(for: phase, key: originalKey, backingScale: 2, renderFrame: renderFrame)
        #expect(renderedFrameCount == 36)

        let changedStatus = makeKey(phase: phase, volumeScalar: 0.8)
        _ = cache.image(for: phase, key: changedStatus, backingScale: 2, renderFrame: renderFrame)
        #expect(renderedFrameCount == 72)

        _ = cache.image(for: phase, key: changedStatus, backingScale: 1, renderFrame: renderFrame)
        #expect(renderedFrameCount == 108)

        let boostedPhase = steadyPhase(step: 0, heartbeatMultiplier: 1.35)
        _ = cache.image(
            for: boostedPhase,
            key: makeKey(phase: boostedPhase, volumeScalar: 0.8),
            backingScale: 1,
            renderFrame: renderFrame
        )
        #expect(renderedFrameCount == 144)
    }

    @Test func cachedSteadyImageMatchesTheDirectRendererAtTheRequestedStep() throws {
        let cache = StatusBarChargingFrameCache()
        let status = MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Speakers")
        )
        let phase = steadyPhase(step: 7)
        let appearance = try #require(NSAppearance(named: .aqua))
        let key = makeKey(phase: phase)
        let scene = makeIconPresentationScene(status: status)
        var foreground = CGColor(gray: 1, alpha: 1)
        var criticalColor = StatusIconRenderer.defaultCriticalColor
        appearance.performAsCurrentDrawingAppearance {
            foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? foreground
            criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? criticalColor
        }

        let renderFrame: (ChargingEffectPhase) -> NSImage? = { framePhase in
            StatusIconRenderer.preRenderedMenuBarImage(
                scene: scene,
                size: 22,
                scale: 2,
                appearance: appearance,
                phase: framePhase
            )
        }
        let cachedImage = try #require(cache.image(
            for: phase,
            key: key,
            backingScale: 2,
            renderFrame: renderFrame
        ))
        let directCGImage = try #require(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: 22,
                scale: 2,
                foreground: foreground,
                criticalColor: criticalColor
            ),
            phase: phase
        ))
        let cachedCGImage = try #require(cachedImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))

        let cachedPixels = try PixelBuffer(image: cachedCGImage)
        let directPixels = try PixelBuffer(image: directCGImage)
        #expect(cachedPixels.bytes == directPixels.bytes)
    }

    @Test func preRenderedMenuBarImagePreservesPixelsAtTheRequestedBackingScale() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        let status = MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 12,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Speakers")
        )
        let phase = steadyPhase(step: 7, heartbeatMultiplier: 1.35)
        var foreground = CGColor(gray: 1, alpha: 1)
        var criticalColor = CGColor(red: 1, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
        appearance.performAsCurrentDrawingAppearance {
            foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? criticalColor
        }

        let scene = makeIconPresentationScene(status: status)
        let preRendered = try #require(StatusIconRenderer.preRenderedMenuBarImage(
            scene: scene,
            size: 22,
            scale: 2,
            appearance: appearance,
            phase: phase
        ))
        #expect(preRendered.size == NSSize(width: 22, height: 22))
        #expect(preRendered.representations.contains { $0.pixelsWide > 0 && $0.pixelsHigh > 0 })
        let scaleOneImage = try #require(StatusIconRenderer.preRenderedMenuBarImage(
            scene: scene,
            size: 22,
            scale: 1,
            appearance: appearance,
            phase: phase
        ))
        #expect(scaleOneImage.size == NSSize(width: 22, height: 22))
        #expect(scaleOneImage.representations.contains { $0.pixelsWide > 0 && $0.pixelsHigh > 0 })
        let scaleOneCGImage = try #require(scaleOneImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))
        #expect(scaleOneCGImage.width == 22)
        #expect(scaleOneCGImage.height == 22)
        let cachedCGImage = try #require(preRendered.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))
        let environment = StatusIconRenderEnvironment(
            size: 22,
            scale: 2,
            foreground: foreground,
            criticalColor: criticalColor,
        )
        let directCGImage = try #require(StatusIconRenderer.render(
            scene: scene,
            environment: environment,
            phase: phase
        ))

        #expect(cachedCGImage.width == 44)
        #expect(cachedCGImage.height == 44)
        let cachedPixels = try PixelBuffer(image: cachedCGImage)
        let directPixels = try PixelBuffer(image: directCGImage)
        #expect(cachedPixels.bytes == directPixels.bytes)
    }

    @Test func burstPhasesDoNotBuildOrUseSteadyFrameSets() {
        let cache = StatusBarChargingFrameCache()
        let phase = ChargingEffectPhase(step: 0, stepsPerCycle: 12, kind: .burst)
        var renderedFrameCount = 0

        let image = cache.image(
            for: phase,
            key: makeKey(phase: phase),
            backingScale: 2
        ) { _ in
            renderedFrameCount += 1
            return NSImage(size: NSSize(width: 22, height: 22))
        }

        #expect(image == nil)
        #expect(renderedFrameCount == 0)
    }

    private func steadyPhase(step: Int, heartbeatMultiplier: Double = 1) -> ChargingEffectPhase {
        ChargingEffectPhase(
            step: step,
            stepsPerCycle: 36,
            kind: .steady,
            heartbeatMultiplier: heartbeatMultiplier
        )
    }

    private func makeKey(
        phase: ChargingEffectPhase?,
        volumeScalar: Double = 0.5
    ) -> StatusBarRenderKey {
        StatusBarRenderKey(
            scene: makeIconPresentationScene(status: MenuBarStatus(
                battery: .placeholder,
                wifi: .placeholder,
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: volumeScalar,
                    isMuted: false,
                    deviceName: "Speakers"
                )
            )),
            iconSize: 22,
            backingScale: 2,
            appearanceName: "darkAqua",
            phase: phase
        )
    }
}
