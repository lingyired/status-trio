import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconRuntimePresentationOptionsTests: XCTestCase {
    func testLiveViewModelAndDesignerPreviewUseTheSameSupplementalOptions() {
        let snapshot = Self.snapshot(percentage: 80)
        let descriptor = inputSource
        let runtimeOptions = Self.runtimeOptions
        let configuration = Self.v1Configuration(center: .network)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(snapshot)
        let inputSources = CurrentValueSubject<InputSourceDescriptor?, Never>(descriptor)
        let settings = IconPresentationSettings(
            configuration: .standard,
            menuBarSize: 28,
            testsChargingEffect: false,
            designerConfiguration: configuration,
            usesInputSourceInCenter: true,
            runtimeOptions: runtimeOptions
        )
        let model = IconPresentationViewModel(
            snapshot: snapshot,
            settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: Just(settings).eraseToAnyPublisher(),
            inputSources: inputSources.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration
                )
            }
        )
        model.start()
        defer { model.stop() }

        let preview = StatusIconPreviewCard.resolveDesignerScene(
            for: snapshot,
            bluetoothDevices: [],
            batteryLevels: [:],
            batteryLevelsUpdatedAt: nil,
            selectedAirPodsAddress: nil,
            selectedConnectedDeviceAddress: nil,
            configuration: configuration,
            scenario: .live,
            inputSource: descriptor,
            runtimeOptions: runtimeOptions
        )

        for scene in [model.output.scene, preview.scene] {
            XCTAssertEqual(scene.outerRing?.segments.first?.progress, 1)
            guard case let .text(center)? = scene.center else {
                return XCTFail("The V1 network center should draw the current input source")
            }
            XCTAssertEqual(center.text, "E")
        }
    }

    func testInputSourceFailureAndNetworkWarningsUseAutomaticNetworkFallback() {
        let configuration = Self.v1Configuration(center: .network)
        let runtimeOptions = Self.runtimeOptions
        let offline = Self.snapshot(percentage: 80, wifi: .noInternet)
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: offline,
                audioIcon: nil,
                inputSource: inputSource,
                runtimeOptions: runtimeOptions
            ),
            sources: .empty
        )

        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration)

        guard case let .symbol(center)? = output.scene.center else {
            return XCTFail("A network warning must replace input source when priority is enabled")
        }
        XCTAssertEqual(center.source, .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil))

        var unavailable = inputs
        unavailable.system = IconPresentationInputs(
            snapshot: Self.snapshot(percentage: 80),
            audioIcon: nil,
            inputSource: nil,
            runtimeOptions: runtimeOptions
        )
        let fallback = IconCompositionResolver.resolve(inputs: unavailable, configuration: configuration)
        XCTAssertNotEqual(fallback.scene.center, output.scene.center)
        XCTAssertEqual(fallback.scene.center, IconPresentationMapper.scene(
            inputs: unavailable.system,
            configuration: runtimeOptions.applying(to: configuration.compositionLegacyPresentationConfiguration)
        ).center)
    }

    func testSupplementalInputSourceDoesNotReplaceOtherExplicitV1Centers() {
        let snapshot = Self.snapshot(percentage: 80, bluetoothAudio: true)
        let runtimeOptions = Self.runtimeOptions
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                inputSource: inputSource,
                runtimeOptions: runtimeOptions
            ),
            sources: .empty
        )

        let bluetooth = Self.v1Configuration(center: .bluetoothAudioOutput)
        let bluetoothScene = IconCompositionResolver.resolve(inputs: inputs, configuration: bluetooth).scene
        XCTAssertEqual(bluetoothScene.center, .symbol(IconSymbolState(
            source: .symbol(name: "airpods", variableValue: nil, fallback: "headphones"),
            color: .bluetooth,
            scale: bluetooth.behaviors.bluetoothAudioCenter.symbolScale
        )))

        let percentageScene = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: Self.v1Configuration(center: .systemBatteryPercentage)
        ).scene
        XCTAssertEqual(percentageScene.center, .text(IconTextState(
            text: "80",
            color: .primary,
            scale: Self.v1Configuration(center: .systemBatteryPercentage).behaviors.systemBatteryRing.textScale
        )))

        let emptyScene = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: Self.v1Configuration(center: .none)
        ).scene
        XCTAssertNil(emptyScene.center)
    }

    private var inputSource: InputSourceDescriptor {
        InputSourceDescriptor(
            id: "com.example.input-source",
            localizedName: "Example Input Source",
            primaryLanguage: "en",
            iconURL: nil,
            shortLabel: "E"
        )
    }

    private static var runtimeOptions: IconPresentationRuntimeOptions {
        IconPresentationRuntimeOptions(
            connectionCenterSource: .inputSource,
            prioritizesNetworkErrorsOverInputSource: true,
            batteryFullThreshold: 80,
            bluetoothAudioIconChoice: .airpods
        )
    }

    private static func snapshot(
        percentage: Int,
        wifi: WiFiState = .connected,
        bluetoothAudio: Bool = false
    ) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: wifi, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: bluetoothAudio ? "AirPods" : "Output",
                currentDevice: bluetoothAudio
                    ? AudioOutputDevice(id: 42, name: "AirPods", isCurrent: true, transport: .bluetooth)
                    : nil
            )
        )
    }

    private static func v1Configuration(center: CenterSource) -> IconConfigurationV1 {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: center)
        return configuration
    }
}
