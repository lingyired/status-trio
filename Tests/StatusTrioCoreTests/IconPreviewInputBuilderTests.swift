import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Icon preview input builder")
struct IconPreviewInputBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func wifiSignalSampleDrivesTheResolvedSignalBars() throws {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        for (rssi, expectedFill) in [(-100, 0.0), (-88, 0.33), (-70, 0.66), (-48, 1.0)] {
            var samples = IconPreviewSampleValues()
            samples.network.rssi = rssi
            let inputs = IconPreviewInputBuilder.simulated(
                samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
            )
            let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)
            #expect(inputs.system.snapshot.wifi.rssi == rssi)
            let center = try #require(output.scene.center)
            guard case let .symbol(symbol) = center else {
                Issue.record("Wi-Fi must resolve to a signal symbol")
                return
            }
            #expect(symbol.source == .symbol(name: "wifi", variableValue: expectedFill, fallback: nil))
        }
    }

    @Test func wiredAndDisabledWiFiNeverExposeTheRetainedSignalSample() {
        var samples = IconPreviewSampleValues()
        samples.network.rssi = -80
        for kind in [IconPreviewNetworkKind.off, .ethernet] {
            samples.network.kind = kind
            let inputs = IconPreviewInputBuilder.simulated(
                samples: samples, configuration: .classic, target: .currentAudioOutput, now: now
            )
            #expect(inputs.system.snapshot.wifi.rssi == nil)
        }
    }

    @Test func testSameMacSampleDrivesRingAndCenterPercentage() throws {
        var samples = IconPreviewSampleValues()
        samples.macBattery.percentage = 42
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        configuration.composition.footer = SlotSelection(primary: .none)

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)

        #expect(try #require(output.scene.outerRing?.segments.first?.progress) == 0.42)
        guard case let .text(center)? = output.scene.center else {
            Issue.record("Expected the center battery percentage to use the shared Mac sample")
            return
        }
        #expect(center.text == "42")
    }

    @Test func testAirPodsSingleEarMirrorsForDualRing() throws {
        var samples = IconPreviewSampleValues()
        samples.airPods.apply(.leftOnly)
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery)
        configuration.composition.center = SlotSelection(primary: .none)
        configuration.composition.footer = SlotSelection(primary: .none)
        configuration.behaviors.airPodsRing = .dual
        configuration.behaviors.showsAirPodsTopSymbol = true

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let ring = try #require(IconCompositionResolver.resolve(
            inputs: inputs, configuration: configuration, now: now
        ).scene.outerRing)

        #expect(ring.isPartial)
        #expect(ring.segments.map(\.progress) == [0.73, 0.73])
        #expect(ring.accessory != nil)
    }

    @Test func testBothEarsUnavailableUsesFallback() throws {
        var samples = IconPreviewSampleValues()
        samples.airPods.apply(.unavailable)
        samples.macBattery.percentage = 55
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        configuration.behaviors.airPodsRing = .dual
        configuration.behaviors.showsAirPodsTopSymbol = true

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)

        #expect(output.trace.outerRing.role == .fallback)
        #expect(try #require(output.scene.outerRing?.segments.first?.progress) == 0.55)
        var directMacConfiguration = configuration
        directMacConfiguration.composition.outerRing = SlotSelection(primary: .systemBattery)
        let directMacOutput = IconCompositionResolver.resolve(
            inputs: inputs, configuration: directMacConfiguration, now: now
        )
        #expect(output.scene == directMacOutput.scene)
    }

    @Test func testUnavailableBluetoothSampleDoesNotRequestPermission() {
        var samples = IconPreviewSampleValues()
        samples.bluetoothTarget.isOnline = false
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.composition.footer = SlotSelection(primary: .none)

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples,
            configuration: configuration,
            target: .connectedDevice(address: "AA:BB:CC:DD:EE:FF"),
            now: now
        )

        #expect(inputs.sources.availability[CenterSource.connectedBluetoothDevice.rawValue] == .unavailable(.disconnected))
        #expect(inputs.sources.connectedBluetoothDeviceSymbol == nil)
    }

    @Test func testInputSourceSampleDrawsShortLabelWithoutReadingTheSystem() throws {
        var samples = IconPreviewSampleValues()
        samples.inputSource.isAvailable = true
        samples.inputSource.shortLabel = "拼"
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource)
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.footer = SlotSelection(primary: .none)

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)

        guard case let .text(center)? = output.scene.center else {
            Issue.record("The simulated input source should draw its short label")
            return
        }
        #expect(center.text == "拼")
        #expect(inputs.sources.availability[CenterSource.inputSource.rawValue] == .available)
    }

    @Test func testUnavailableInputSourceFallsBackEvenWhenSampleExistsButDisabled() throws {
        var samples = IconPreviewSampleValues()
        samples.inputSource.isAvailable = false
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource, fallback: .network)
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.footer = SlotSelection(primary: .none)

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)

        #expect(output.trace.center.role == .fallback)
        #expect(output.trace.center.selectedSourceID == CenterSource.network.rawValue)
    }

    @Test func testGlobalRuleOverridesNoneCentreWithSimulatedNetworkErrorThenRecovers() throws {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .none)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.footer = SlotSelection(primary: .none)

        var broken = IconPreviewSampleValues()
        broken.network.kind = .noInternet
        let brokenOutput = IconCompositionResolver.resolve(
            inputs: IconPreviewInputBuilder.simulated(
                samples: broken, configuration: configuration, target: .currentAudioOutput, now: now
            ),
            configuration: configuration, now: now
        )
        #expect(brokenOutput.trace.center.reason == .overridden(.networkProblem))
        #expect(brokenOutput.scene.center != nil)

        var recovered = IconPreviewSampleValues()
        recovered.network.kind = .wifi
        let recoveredOutput = IconCompositionResolver.resolve(
            inputs: IconPreviewInputBuilder.simulated(
                samples: recovered, configuration: configuration, target: .currentAudioOutput, now: now
            ),
            configuration: configuration, now: now
        )
        #expect(recoveredOutput.scene.center == nil, "A none centre recovers to empty once the network is healthy")
    }
}
