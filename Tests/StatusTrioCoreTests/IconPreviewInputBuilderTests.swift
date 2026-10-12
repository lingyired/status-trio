import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Icon preview input builder")
struct IconPreviewInputBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

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

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let ring = try #require(IconCompositionResolver.resolve(
            inputs: inputs, configuration: configuration, now: now
        ).scene.outerRing)

        #expect(ring.isPartial)
        #expect(ring.segments.map(\.progress) == [0.73, 0.73])
    }

    @Test func testBothEarsUnavailableUsesFallback() throws {
        var samples = IconPreviewSampleValues()
        samples.airPods.apply(.unavailable)
        samples.macBattery.percentage = 55
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)

        let inputs = IconPreviewInputBuilder.simulated(
            samples: samples, configuration: configuration, target: .currentAudioOutput, now: now
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)

        #expect(output.trace.outerRing.role == .fallback)
        #expect(try #require(output.scene.outerRing?.segments.first?.progress) == 0.55)
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
}
