import XCTest
@testable import StatusTrioCore

final class IconDesignerPreviewAnimationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testResolvedSimulatedChargingStartsAfterAnimationWasAlreadyEnabled() {
        var samples = IconPreviewSampleValues()
        samples.macBattery.isCharging = false
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemBatteryRing.showsChargingEffect = true

        var preview = IconDesignerPreviewState()
        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration), at: now
        )
        XCTAssertFalse(preview.playback.isPlaying)

        samples.macBattery.isCharging = true
        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration),
            at: now.addingTimeInterval(1)
        )

        XCTAssertTrue(preview.playback.isPlaying)
        XCTAssertEqual(preview.playback.startedAt, now.addingTimeInterval(1))
    }

    func testResolvedSimulatedChargingStopsWhenSampleOrAnimationIsCancelled() {
        var samples = IconPreviewSampleValues()
        samples.macBattery.isCharging = true
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemBatteryRing.showsChargingEffect = true
        var preview = IconDesignerPreviewState()

        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration), at: now
        )
        XCTAssertTrue(preview.playback.isPlaying)

        samples.macBattery.isCharging = false
        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration),
            at: now.addingTimeInterval(1)
        )
        XCTAssertFalse(preview.playback.isPlaying)

        samples.macBattery.isCharging = true
        configuration.behaviors.systemBatteryRing.showsChargingEffect = false
        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration),
            at: now.addingTimeInterval(2)
        )
        XCTAssertFalse(preview.playback.isPlaying)
    }

    func testResolvedSimulatedChargingRestartsOnlyWhenVisibleAndMotionIsAllowed() {
        var samples = IconPreviewSampleValues()
        samples.macBattery.isCharging = true
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemBatteryRing.showsChargingEffect = true
        let isEligible = eligibility(samples: samples, configuration: configuration)
        var preview = IconDesignerPreviewState()
        preview.setVisible(false)
        preview.setReduceMotion(true)

        preview.setResolvedSimulatedChargingEffect(isEligible: isEligible, at: now)
        XCTAssertFalse(preview.playback.isPlaying)

        preview.setReduceMotion(false)
        XCTAssertFalse(preview.playback.isPlaying)
        preview.setVisible(true)
        XCTAssertTrue(preview.playback.isPlaying)

        preview.setVisible(false)
        XCTAssertFalse(preview.playback.isPlaying)
    }

    private func resolvedScene(samples: IconPreviewSampleValues, configuration: IconConfigurationV1) -> IconSceneState {
        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples,
            configuration: configuration,
            target: .currentAudioOutput,
            now: now
        )
        let resolved = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: configuration,
            now: now
        )
        return resolved.scene
    }

    private func eligibility(samples: IconPreviewSampleValues, configuration: IconConfigurationV1,
                             mode: IconPreviewDataMode = .simulated) -> Bool {
        IconDesignerPreviewState.simulatedChargingEffectIsEligible(
            mode: mode,
            animationEnabled: configuration.behaviors.systemBatteryRing.showsChargingEffect,
            resolvedScene: resolvedScene(samples: samples, configuration: configuration)
        )
    }

    func testAnimationCanBeEnabledAfterResolvedSimulatedChargingStarts() {
        var samples = IconPreviewSampleValues()
        samples.macBattery.isCharging = true
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemBatteryRing.showsChargingEffect = false
        var preview = IconDesignerPreviewState()

        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration), at: now
        )
        XCTAssertFalse(preview.playback.isPlaying)

        configuration.behaviors.systemBatteryRing.showsChargingEffect = true
        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration),
            at: now.addingTimeInterval(1)
        )
        XCTAssertTrue(preview.playback.isPlaying)
        preview.setResolvedSimulatedChargingEffect(
            isEligible: eligibility(samples: samples, configuration: configuration, mode: .live),
            at: now.addingTimeInterval(2)
        )
        XCTAssertFalse(preview.playback.isPlaying)
    }
}
