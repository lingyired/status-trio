import Combine
import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Icon designer preview session")
@MainActor
struct IconDesignerPreviewSessionTests {
    @Test func previewBackgroundChangesPublishFromTheInMemorySession() {
        let session = IconDesignerPreviewSession()
        var publishedValues: [Bool] = []
        let cancellable = session.$isDarkBackground.dropFirst().sink { publishedValues.append($0) }
        defer { cancellable.cancel() }

        #expect(session.isDarkBackground)
        session.isDarkBackground = false

        #expect(publishedValues == [false])
        #expect(!session.isDarkBackground)
        #expect(session.mode == .live)
    }

    @Test func defaultSamplesMatchTheDesignerSpecification() {
        let samples = IconPreviewSampleValues()
        #expect(samples.macBattery.isPresent)
        #expect(samples.macBattery.percentage == 76)
        #expect(!samples.macBattery.isCharging)
        #expect(samples.airPods.leftBattery == 73)
        #expect(samples.airPods.rightBattery == 68)
        #expect(samples.network.kind == .wifi)
        #expect(samples.bluetoothTarget.isOnline)
        #expect(samples.bluetoothTarget.isAudio)
        #expect(samples.systemVolume.percentage == 62)
        #expect(!samples.systemVolume.isMuted)
        #expect(samples.systemVolume.isAvailable)
    }

    @Test func selectingSlotDoesNotResetSharedAirPodsSample() {
        let session = IconDesignerPreviewSession()
        session.setAirPodsBattery(.left, 25)
        session.selectedSlot = .center
        session.selectedSlot = .outerRing

        #expect(session.samples.airPods.leftBattery == 25)
        #expect(session.mode == .live)
    }

    @Test func availabilityEditsBelongToTheSharedPreviewSession() {
        let session = IconDesignerPreviewSession()
        session.setAirPodsAvailability(.left, isAvailable: false)
        session.setAirPodsBattery(.left, 29)
        session.selectedSlot = .center
        session.mode = .live

        #expect(!session.samples.airPods.leftAvailable)
        #expect(session.samples.airPods.leftBattery == 29)
        #expect(session.selectedSlot == .center)
        #expect(session.mode == .live)
    }

    @Test func hiddenSampleRemainsAvailableWhenItsSourceIsShownAgain() {
        let session = IconDesignerPreviewSession()
        session.setAirPodsBattery(.right, 41)
        session.applyAirPodsPreset(.unavailable)
        session.applyAirPodsPreset(.rightOnly)

        #expect(session.samples.airPods.rightAvailable)
        #expect(session.samples.airPods.rightBattery == 41)
    }

    @Test func quickFillChangesSamplesWithoutChangingTheSelectedMode() {
        let session = IconDesignerPreviewSession()
        session.mode = .live
        session.applyQuickFill(.batteryCriticallyLow)
        #expect(session.samples.macBattery.percentage == 8)
        #expect(session.mode == .live)

        session.setMacBatteryPercentage(31)
        #expect(session.samples.macBattery.percentage == 31)
        session.mode = .simulated
        #expect(session.samples.macBattery.percentage == 31)
    }

    @Test func nonFiniteSampleValuesUseTheDocumentedSafeDefault() {
        let session = IconDesignerPreviewSession()
        session.setAirPodsBattery(.left, .nan)
        session.setAirPodsBattery(.right, .infinity)

        #expect(session.samples.airPods.leftBattery == 0)
        #expect(session.samples.airPods.rightBattery == 100)
    }

    @Test func previewSamplesAreNotEncodableForPersistence() {
        func isEncodable<Value>(_ value: Value) -> Bool {
            value is any Encodable
        }

        #expect(!isEncodable(IconPreviewSampleValues()))
    }

    @Test func usedSourcesIncludeSharedAndRuleDependentSamples() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput)
        configuration.composition.footer = SlotSelection(primary: .none)
        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true

        let used = IconDesignerPreviewSession.usedSources(
            configuration: configuration,
            target: .currentAudioOutput,
            devices: []
        )

        #expect(used == [.macBattery, .bluetoothTarget, .systemVolume])
    }

    @Test func networkSampleIsVisibleWhenNetworkErrorCanOverrideBluetoothPrimary() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.composition.footer = SlotSelection(primary: .none)

        let used = IconDesignerPreviewSession.usedSources(
            configuration: configuration,
            target: .currentAudioOutput,
            devices: []
        )

        #expect(used == [.bluetoothTarget, .network])
    }

    @Test func inputSourceSampleIsUsedForAnInputSourceCentre() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.center = SlotSelection(primary: .inputSource)
        configuration.composition.footer = SlotSelection(primary: .none)

        let used = IconDesignerPreviewSession.usedSources(
            configuration: configuration,
            target: .currentAudioOutput,
            devices: []
        )

        #expect(used == [.inputSource])
    }

    @Test func globalNetworkOverrideKeepsNetworkSampleReachableForEveryCentreSource() {
        for primary in CenterSource.allCases {
            var configuration = IconConfigurationV1.classic
            configuration.composition.outerRing = SlotSelection(primary: .none)
            configuration.composition.center = SlotSelection(primary: primary)
            configuration.composition.centerOverride.networkProblemOverridesPrimary = true
            configuration.composition.footer = SlotSelection(primary: .none)

            let used = IconDesignerPreviewSession.usedSources(
                configuration: configuration,
                target: .currentAudioOutput,
                devices: []
            )

            #expect(used.contains(.network), "Global rule must expose the network sample for \(primary)")
        }
    }

    @Test func switchingUsedSourcesHidesButKeepsSampleValues() {
        let session = IconDesignerPreviewSession()
        session.setMacBatteryPercentage(41)
        session.updateSamples { $0.inputSource.shortLabel = "拼" }
        session.updateSamples { $0.inputSource.isAvailable = false }

        #expect(session.samples.macBattery.percentage == 41)
        #expect(session.samples.inputSource.shortLabel == "拼")
        #expect(!session.samples.inputSource.isAvailable)
    }
}

@Suite("Icon preview live data gating")
struct IconPreviewDataLiveStatusTests {
    @Test func airPodsLiveStatusNeverExposesPayloadWhenSourceIsUnavailable() {
        let freshPayload = AirPodsBatteryIconSnapshot(
            deviceAddress: "AA:BB:CC:DD:EE:FF", model: .airPodsPro,
            main: 71, left: 73, right: 69, caseLevel: nil, observedAt: .now
        )
        let denied = IconSourceSnapshot(
            availability: [RingSource.airPodsBattery.rawValue: .unavailable(.permissionDenied)],
            airPodsBattery: freshPayload
        )

        #expect(IconPreviewDataLiveStatus.airPodsBattery(from: denied) == nil)
    }

    @Test func airPodsLiveStatusShowsOnlyResolverApprovedPayload() {
        let freshPayload = AirPodsBatteryIconSnapshot(
            deviceAddress: "AA:BB:CC:DD:EE:FF", model: .airPodsPro,
            main: 71, left: 73, right: 69, caseLevel: nil, observedAt: .now
        )
        let available = IconSourceSnapshot(
            availability: [RingSource.airPodsBattery.rawValue: .available],
            airPodsBattery: freshPayload
        )

        #expect(IconPreviewDataLiveStatus.airPodsBattery(from: available) == freshPayload)
    }

    @Test func selectedBluetoothAddressNeverFallsThroughToCurrentAudioOutput() {
        let output = AudioOutputDevice(id: 1, name: "Current AirPods", isCurrent: true, transport: .bluetooth)
        let selectedAddress = "AA:BB:CC:DD:EE:FF"
        let anotherConnected = BluetoothDevice(
            id: "11:22:33:44:55:66", name: "Other headset", kind: .audio, isConnected: true
        )
        let unavailableOutput: IconSourceAvailability = .available

        let mismatched = IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: selectedAddress, devices: [anotherConnected], bluetoothAvailability: .available,
            audioOutputAvailability: unavailableOutput, currentOutput: output
        )
        let offline = IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: selectedAddress,
            devices: [BluetoothDevice(id: selectedAddress, name: "Offline", kind: .audio, isConnected: false)],
            bluetoothAvailability: .available, audioOutputAvailability: unavailableOutput, currentOutput: output
        )
        let ghost = IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: selectedAddress,
            devices: [BluetoothDevice(id: selectedAddress, name: "Ghost", kind: .audio, isConnected: true, isUnpairedGhost: true)],
            bluetoothAvailability: .available, audioOutputAvailability: unavailableOutput, currentOutput: output
        )
        let overAir = IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: selectedAddress,
            devices: [BluetoothDevice(id: selectedAddress, name: "Nearby", kind: .audio, isConnected: true, isReadOverTheAir: true)],
            bluetoothAvailability: .available, audioOutputAvailability: unavailableOutput, currentOutput: output
        )

        #expect(mismatched == nil)
        #expect(offline == nil)
        #expect(ghost == nil)
        #expect(overAir == nil)
    }

    @Test func bluetoothLiveStatusUsesSelectedOnlineDeviceOrUnselectedCurrentOutputOnly() {
        let selectedAddress = "AA:BB:CC:DD:EE:FF"
        let selected = BluetoothDevice(id: "aa:bb:cc:dd:ee:ff", name: "Selected headset", kind: .audio, isConnected: true)
        let output = AudioOutputDevice(id: 1, name: "Current AirPods", isCurrent: true, transport: .bluetooth)

        #expect(IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: selectedAddress, devices: [selected], bluetoothAvailability: .available,
            audioOutputAvailability: .available, currentOutput: output
        ) == "Selected headset")
        #expect(IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: nil, devices: [], bluetoothAvailability: .available,
            audioOutputAvailability: .available, currentOutput: output
        ) == "Current AirPods")
        #expect(IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: nil, devices: [], bluetoothAvailability: .available,
            audioOutputAvailability: .unavailable(.permissionDenied), currentOutput: output
        ) == nil)
        #expect(IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: nil, devices: [], bluetoothAvailability: .authorizationDenied,
            audioOutputAvailability: .available, currentOutput: output
        ) == nil)
    }
}
