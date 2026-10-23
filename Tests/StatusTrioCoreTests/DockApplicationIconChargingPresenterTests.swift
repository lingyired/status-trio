import AppKit
import Testing
@testable import StatusTrioCore

/// The A/B prototype that pushes whole-tile frames through
/// `applicationIconImage`. It is measurement-only, but the counters it reports
/// are what the CPU comparison reads, so they are pinned here.
@MainActor
struct DockApplicationIconChargingPresenterTests {
    @Test func restoreStaticIconKeepsCachedFramesAndAFailedVariant() {
        let application = DockIconApplicationSpy()
        let renderControl = DockApplicationRenderControl()
        var renderedSteps: [Int] = []
        let presenter = DockApplicationIconChargingPresenter(
            application: application,
            renderTile: { _, phase, _, _ in
                renderedSteps.append(phase.step)
                if renderControl.failedMultiplier == phase.heartbeatMultiplier { return nil }
                return NSImage(size: NSSize(width: 256, height: 256))
            }
        )

        #expect(presenter.present(
            phase: steadyPhase(7),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(renderedSteps == Array(0..<36))

        renderControl.failedMultiplier = 1.35
        #expect(!presenter.present(
            phase: steadyPhase(7, multiplier: 1.35),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        presenter.restoreStaticIcon()

        #expect(!presenter.isInstalled)
        #expect(presenter.cachedVariantCount == 1)
        #expect(!presenter.present(
            phase: steadyPhase(7, multiplier: 1.35),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(renderedSteps.count == 37)
        #expect(presenter.cachedVariantCount == 1)

        #expect(presenter.present(
            phase: steadyPhase(7),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(presenter.isInstalled)
        #expect(presenter.cachedVariantCount == 1)
        #expect(renderedSteps.count == 37)
    }

    @Test func cachesOneSteadySetAndSkipsDuplicateFrames() {
        let application = DockIconApplicationSpy()
        var renderedSteps: [Int] = []
        let presenter = DockApplicationIconChargingPresenter(
            application: application,
            renderTile: { _, phase, _, _ in
                renderedSteps.append(phase.step)
                return NSImage(size: NSSize(width: 256, height: 256))
            }
        )

        #expect(presenter.present(
            phase: steadyPhase(7),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(renderedSteps == Array(0..<36))
        #expect(application.assignments == 1)
        #expect(presenter.cachedVariantCount == 1)

        // The same phase must not reassign, and a different step must come from
        // the same cached set.
        #expect(presenter.present(
            phase: steadyPhase(7),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(application.assignments == 1)
        #expect(presenter.present(
            phase: steadyPhase(8),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(renderedSteps == Array(0..<36))
        #expect(application.assignments == 2)
    }

    @Test func aNewSceneRebuildsInsteadOfAccumulatingSets() {
        let application = DockIconApplicationSpy()
        let presenter = DockApplicationIconChargingPresenter(
            application: application,
            renderTile: { _, _, _, _ in NSImage(size: NSSize(width: 256, height: 256)) }
        )

        _ = presenter.present(
            phase: steadyPhase(0, multiplier: 1),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        )
        _ = presenter.present(
            phase: steadyPhase(0, multiplier: 1.35),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        )
        #expect(presenter.cachedVariantCount == 2)

        _ = presenter.present(
            phase: steadyPhase(0, multiplier: 0),
            scene: scene,
            backgroundStyle: .light,
            pixelLength: 512
        )
        #expect(presenter.cachedVariantCount == 2)
        #expect(presenter.cachedResidentByteCount > 0)
    }

    @Test func aFailedRasterFallsBackAndClearReleasesTheTile() {
        let application = DockIconApplicationSpy()
        let presenter = DockApplicationIconChargingPresenter(
            application: application,
            renderTile: { _, _, _, _ in nil }
        )

        #expect(!presenter.present(
            phase: steadyPhase(0),
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(application.assignments == 0)
        #expect(!presenter.isInstalled)

        presenter.clear()
        #expect(presenter.cachedVariantCount == 0)
        #expect(presenter.cachedResidentByteCount == 0)
    }

    /// The measurement switch only exists inside a development bundle, so a
    /// shipped build always animates through the tile's content view.
    @Test func theApplicationIconPrototypeIsDevOnly() {
        #expect(DockChargingAnimationRendererMode.usesApplicationIconFrames(
            bundleIdentifier: "com.lingsmbp.StatusTrio.dev.dock-anim",
            environment: [DockChargingAnimationRendererMode.environmentKey: "applicationIcon"]
        ))
        #expect(!DockChargingAnimationRendererMode.usesApplicationIconFrames(
            bundleIdentifier: "com.lingsmbp.StatusTrio",
            environment: [DockChargingAnimationRendererMode.environmentKey: "applicationIcon"]
        ))
        #expect(!DockChargingAnimationRendererMode.usesApplicationIconFrames(
            bundleIdentifier: "com.lingsmbp.StatusTrio.dev.dock-anim",
            environment: [:]
        ))
    }

    private var scene: IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: 62,
                        isPresent: true,
                        isCharging: true,
                        isLowPowerMode: false,
                        isConnectedToPower: true
                    ),
                    wifi: WiFiStatus(state: .connected, rssi: -50),
                    connection: .wifi,
                    volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
                ),
                audioIcon: nil
            ),
            configuration: .standard
        )
    }

    private func steadyPhase(_ step: Int, multiplier: Double = 1) -> ChargingEffectPhase {
        ChargingEffectPhase(
            step: step,
            stepsPerCycle: 36,
            kind: .steady,
            heartbeatMultiplier: multiplier
        )
    }
}

@MainActor
private final class DockApplicationRenderControl {
    var failedMultiplier: Double?
}

@MainActor
private final class DockIconApplicationSpy: ApplicationDockIconApplying {
    private(set) var assignments = 0
    private(set) var applicationIconImage: NSImage?

    func setApplicationIconImage(_ image: NSImage?) {
        assignments += 1
        applicationIconImage = image
    }
}
