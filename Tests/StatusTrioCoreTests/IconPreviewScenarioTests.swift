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
