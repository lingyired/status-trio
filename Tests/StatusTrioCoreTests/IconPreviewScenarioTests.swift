import Foundation

import Testing
@testable import StatusTrioCore

@Suite("Icon preview scenarios")
struct IconPreviewScenarioTests {
    private var liveInput: IconResolutionInputs {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 63, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.72, isMuted: false, deviceName: "Live output")
        )
        return IconResolutionInputs(
            system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            sources: .empty
        )
    }

    @Test func liveReturnsTheExactLatestInput() {
        let input = liveInput
        #expect(IconPreviewScenario.live.makeInputs(basedOn: input) == input)
    }

    @Test func simulatedResolverIsIndependentOfLiveFixturesAndLiveModeUsesLatestInput() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        configuration.composition.footer = SlotSelection(primary: .systemVolume)
        var samples = IconPreviewSampleValues()
        samples.macBattery.percentage = 42
        samples.systemVolume.percentage = 37

        let firstLive = liveInput
        let secondLive = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(rawPercentage: 4, isPresent: false, isCharging: true,
                                           isLowPowerMode: false, isConnectedToPower: true),
                    wifi: WiFiStatus(state: .off, rssi: nil),
                    connection: .offline,
                    volume: VolumeStatus(scalar: 0.01, isMuted: true, deviceName: "Other")
                ),
                audioIcon: .symbol(name: "speaker.slash", variableValue: nil, fallback: nil)
            ),
            sources: IconSourceSnapshot(availability: [
                RingSource.systemBattery.rawValue: .unavailable(.disconnected),
                CenterSource.systemBatteryPercentage.rawValue: .unavailable(.disconnected),
                FooterSource.systemVolume.rawValue: .unavailable(.unknown)
            ])
        )

        let firstSimulated = IconDesignerPreviewResolver.resolve(
            liveInputs: firstLive, configuration: configuration, mode: .simulated,
            samples: samples, target: .currentAudioOutput, now: now
        )
        let secondSimulated = IconDesignerPreviewResolver.resolve(
            liveInputs: secondLive, configuration: configuration, mode: .simulated,
            samples: samples, target: .currentAudioOutput, now: now
        )
        #expect(firstSimulated == secondSimulated)

        let liveOutput = IconDesignerPreviewResolver.resolve(
            liveInputs: secondLive, configuration: configuration, mode: .live,
            samples: samples, target: .currentAudioOutput, now: now
        )
        #expect(liveOutput == IconCompositionResolver.resolve(
            inputs: secondLive, configuration: configuration, now: now
        ))
        #expect(firstLive == liveInput)
        #expect(secondLive.system.snapshot.battery.isPresent == false)
    }

    @Test(arguments: [
        IconPreviewScenario.networkHealthy,
        .networkNoInternet,
        .wifiOffEthernetConnected,
        .batteryCharging,
        .batteryCriticallyLow,
        .volumeMuted
    ])
    func scenariosAreDeterministicAndDoNotMutateTheirBase(_ scenario: IconPreviewScenario) {
        let input = liveInput
        let first = scenario.makeInputs(basedOn: input)
        let second = scenario.makeInputs(basedOn: input)
        #expect(first == second)
        #expect(input == liveInput)
        #expect(scenario != .live)
    }

    @Test func mutedScenarioPreservesBluetoothPrimaryAndReturningToLiveUsesLatestInput() {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 63, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.72, isMuted: false, deviceName: "AirPods",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        let live = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: .symbol(name: "airpodspro", variableValue: nil, fallback: "headphones")
            ),
            sources: .empty
        )
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)

        let liveOutput = IconCompositionResolver.resolve(inputs: live, configuration: configuration)
        let mutedInput = IconPreviewScenario.volumeMuted.makeInputs(basedOn: live)
        let mutedOutput = IconCompositionResolver.resolve(inputs: mutedInput, configuration: configuration)
        #expect(mutedInput.system.snapshot.volume == VolumeStatus(
            scalar: 0, isMuted: true, deviceName: snapshot.volume.deviceName,
            currentDevice: snapshot.volume.currentDevice,
            outputDevices: snapshot.volume.outputDevices,
            canSetVolume: snapshot.volume.canSetVolume,
            canMute: snapshot.volume.canMute
        ))
        #expect(mutedInput.system.audioIcon == live.system.audioIcon)
        #expect(mutedOutput.scene.center == liveOutput.scene.center)
        #expect(mutedOutput.scene.footer != liveOutput.scene.footer)

        let latestSnapshot = StatusSnapshot(
            battery: snapshot.battery,
            wifi: snapshot.wifi,
            connection: snapshot.connection,
            volume: VolumeStatus(scalar: 0.38, isMuted: false, deviceName: "AirPods",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        let latest = IconResolutionInputs(system: IconPresentationInputs(
            snapshot: latestSnapshot, audioIcon: live.system.audioIcon
        ), sources: .empty)
        let restored = IconPreviewScenario.live.makeInputs(basedOn: latest)
        #expect(restored == latest)
        #expect(IconCompositionResolver.resolve(inputs: restored, configuration: configuration).scene.center == liveOutput.scene.center)
    }

    @Test func airPodsScenariosReachProductionResolverWithoutClaimingLiveAvailability() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        configuration.behaviors.airPodsRing = .dual

        let connected = IconPreviewScenario.airPodsConnected.makeInputs(basedOn: liveInput, now: now)
        let connectedOutput = IconCompositionResolver.resolve(inputs: connected, configuration: configuration, now: now)
        #expect(connected.sources.airPodsBattery != nil)
        #expect(connectedOutput.trace.outerRing.selectedSourceID == RingSource.airPodsBattery.rawValue)
        #expect(connectedOutput.scene.outerRing?.layout == .leftRight)

        let disconnected = IconPreviewScenario.airPodsDisconnected.makeInputs(basedOn: connected, now: now)
        let disconnectedOutput = IconCompositionResolver.resolve(inputs: disconnected, configuration: configuration, now: now)
        #expect(disconnected.sources.airPodsBattery == nil)
        #expect(disconnectedOutput.trace.outerRing.selectedSourceID == RingSource.systemBattery.rawValue)
        #expect(disconnectedOutput.trace.outerRing.role == .fallback)
    }

    @Test func wiredScenarioUsesExistingConnectionValueWithoutReachabilityState() {
        let result = IconPreviewScenario.wifiOffEthernetConnected.makeInputs(basedOn: liveInput)
        #expect(result.system.snapshot.wifi.state == .off)
        #expect(result.system.snapshot.connection == .ethernet)
    }

    @Test func previewInputsExerciseFallbackAndNetworkOverrideResolution() {
        let base = liveInput
        let sample = IconPreviewScenario.networkNoInternet.makeInputs(basedOn: base)

        var fallbackConfiguration = IconConfigurationV1.classic
        fallbackConfiguration.composition.center = SlotSelection(primary: .network, fallback: .pinnedBluetoothGlyph)
        var unavailableNetwork = sample
        unavailableNetwork.sources.availability[CenterSource.network.rawValue] = .unavailable(.disconnected)
        let fallback = IconCompositionResolver.resolve(inputs: unavailableNetwork, configuration: fallbackConfiguration)
        #expect(fallback.trace.center.role == .fallback)
        #expect(fallback.trace.center.selectedSourceID == CenterSource.pinnedBluetoothGlyph.rawValue)

        let bluetoothSnapshot = StatusSnapshot(
            battery: sample.system.snapshot.battery,
            wifi: sample.system.snapshot.wifi,
            connection: sample.system.snapshot.connection,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Bluetooth",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        var bluetoothInput = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: bluetoothSnapshot, audioIcon: sample.system.audioIcon),
            sources: sample.sources
        )
        bluetoothInput.sources.availability[CenterSource.bluetoothAudioOutput.rawValue] = .available
        var overrideConfiguration = IconConfigurationV1.classic
        overrideConfiguration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        overrideConfiguration.composition.centerOverride.networkProblemOverridesPrimary = true
        let overridden = IconCompositionResolver.resolve(inputs: bluetoothInput, configuration: overrideConfiguration)
        #expect(overridden.trace.center.reason == .overridden(.networkProblem))
    }

    @Test func previewAndProductionUseTheSameCompositionResolver() {
        let input = IconPreviewScenario.networkNoInternet.makeInputs(basedOn: liveInput)
        let previewOutput = IconCompositionResolver.resolve(inputs: input, configuration: .classic)
        let productionInputs = IconPresentationInputs(
            snapshot: input.system.snapshot,
            audioIcon: input.system.audioIcon
        )
        let productionScene = IconPresentationMapper.scene(
            inputs: productionInputs,
            configuration: IconConfigurationV1.classic.legacyPresentationConfiguration
        )
        #expect(previewOutput.scene == productionScene)
        #expect(previewOutput.trace.center.role == .primary)
    }
}

@Suite("Custom AirPods preview sample")
struct CustomAirPodsPreviewSampleTests {
    private var liveInput: IconResolutionInputs {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 63, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.72, isMuted: false, deviceName: "Live output")
        )
        return IconResolutionInputs(system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil), sources: .empty)
    }

    @Test func independentEarValuesClampAndAvailabilityDoesNotEraseValues() {
        var sample = CustomAirPodsPreviewSample()
        sample.setLeftBattery(0)
        sample.setRightBattery(100)
        sample.leftAvailable = false
        sample.rightAvailable = false

        #expect(sample.leftBattery == 0)
        #expect(sample.rightBattery == 100)
        sample.leftAvailable = true
        sample.rightAvailable = true
        #expect(sample.leftBattery == 0)
        #expect(sample.rightBattery == 100)
    }

    @Test func malformedAndNonfiniteBatteryValuesClampToSafeEndpoints() {
        var sample = CustomAirPodsPreviewSample()
        sample.setLeftBattery(-12)
        sample.setRightBattery(145)
        #expect(sample.leftBattery == 0)
        #expect(sample.rightBattery == 100)

        sample.setLeftBattery(.nan)
        sample.setRightBattery(.infinity)
        #expect(sample.leftBattery == 0)
        #expect(sample.rightBattery == 100)
        sample.setRightBattery(-.infinity)
        #expect(sample.rightBattery == 0)
    }

    @Test func presetsChangeAvailabilityWithoutChangingBatteryValues() {
        var sample = CustomAirPodsPreviewSample()
        sample.setLeftBattery(22)
        sample.setRightBattery(91)

        sample.apply(.leftOnly)
        #expect(sample.leftAvailable)
        #expect(!sample.rightAvailable)
        #expect(sample.leftBattery == 22)
        #expect(sample.rightBattery == 91)
        sample.apply(.rightOnly)
        #expect(!sample.leftAvailable)
        #expect(sample.rightAvailable)
        sample.apply(.both)
        #expect(sample.leftAvailable && sample.rightAvailable)
        sample.apply(.unavailable)
        #expect(!sample.leftAvailable && !sample.rightAvailable)
        #expect(sample.leftBattery == 22)
        #expect(sample.rightBattery == 91)
    }

    @Test func customScenarioResolvesDifferentEarValuesAndMirrorsTheAvailableEar() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        configuration.behaviors.airPodsRing = .dual
        var sample = CustomAirPodsPreviewSample()
        sample.setLeftBattery(25)
        sample.setRightBattery(75)

        let both = IconPreviewScenario.airPodsCustom.makeInputs(
            basedOn: liveInput, customAirPodsSample: sample, now: now
        )
        let bothOutput = IconCompositionResolver.resolve(inputs: both, configuration: configuration, now: now)
        #expect(both.sources.airPodsBattery?.main == nil)
        #expect(both.sources.airPodsBattery?.caseLevel == nil)
        #expect(both.sources.airPodsBattery?.left == 25)
        #expect(both.sources.airPodsBattery?.right == 75)
        #expect(bothOutput.trace.outerRing.selectedSourceID == RingSource.airPodsBattery.rawValue)
        #expect(bothOutput.scene.outerRing?.segments.map(\.progress) == [0.25, 0.75])

        sample.apply(.leftOnly)
        let left = IconPreviewScenario.airPodsCustom.makeInputs(
            basedOn: liveInput, customAirPodsSample: sample, now: now
        )
        let leftOutput = IconCompositionResolver.resolve(inputs: left, configuration: configuration, now: now)
        #expect(left.sources.airPodsBattery?.left == 25)
        #expect(left.sources.airPodsBattery?.right == nil)
        #expect(leftOutput.scene.outerRing?.segments.map(\.progress) == [0.25, 0.25])

        sample.apply(.rightOnly)
        let right = IconPreviewScenario.airPodsCustom.makeInputs(
            basedOn: liveInput, customAirPodsSample: sample, now: now
        )
        let rightOutput = IconCompositionResolver.resolve(inputs: right, configuration: configuration, now: now)
        #expect(right.sources.airPodsBattery?.left == nil)
        #expect(right.sources.airPodsBattery?.right == 75)
        #expect(rightOutput.scene.outerRing?.segments.map(\.progress) == [0.75, 0.75])

        sample.apply(.both)
        sample.setLeftBattery(0)
        sample.setRightBattery(100)
        let endpoints = IconPreviewScenario.airPodsCustom.makeInputs(
            basedOn: liveInput, customAirPodsSample: sample, now: now
        )
        let endpointOutput = IconCompositionResolver.resolve(inputs: endpoints, configuration: configuration, now: now)
        #expect(endpoints.sources.airPodsBattery?.left == 0)
        #expect(endpoints.sources.airPodsBattery?.right == 100)
        #expect(endpointOutput.scene.outerRing?.segments.map(\.progress) == [0, 1])
    }

    @Test func returningToLiveUsesLatestInputsInsteadOfTheCustomSample() {
        var sample = CustomAirPodsPreviewSample()
        sample.setLeftBattery(25)
        sample.setRightBattery(75)
        let latest = liveInput
        let custom = IconPreviewScenario.airPodsCustom.makeInputs(basedOn: latest, customAirPodsSample: sample)
        let restored = IconPreviewScenario.live.makeInputs(basedOn: latest, customAirPodsSample: sample)

        #expect(custom.sources.airPodsBattery?.left == 25)
        #expect(custom.sources.airPodsBattery?.right == 75)
        #expect(restored == latest)
        #expect(restored.system.snapshot.battery.rawPercentage == 63)
    }

    @Test func unavailableCustomSampleUsesTheConfiguredFallbackAndDoesNotMutateLiveInputs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = liveInput
        var sample = CustomAirPodsPreviewSample()
        sample.apply(.unavailable)
        let custom = IconPreviewScenario.airPodsCustom.makeInputs(
            basedOn: live, customAirPodsSample: sample, now: now
        )
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        let output = IconCompositionResolver.resolve(inputs: custom, configuration: configuration, now: now)

        #expect(custom.sources.airPodsBattery?.main == nil)
        #expect(custom.sources.airPodsBattery?.left == nil)
        #expect(custom.sources.airPodsBattery?.right == nil)
        #expect(custom.sources.airPodsBattery?.caseLevel == nil)
        #expect(custom.sources.availability[RingSource.airPodsBattery.rawValue] == .unavailable(.unknown))
        #expect(output.trace.outerRing.role == .fallback)
        #expect(output.trace.outerRing.selectedSourceID == RingSource.systemBattery.rawValue)
        #expect(custom.system.snapshot == live.system.snapshot)
        #expect(live.sources == .empty)
    }
}
