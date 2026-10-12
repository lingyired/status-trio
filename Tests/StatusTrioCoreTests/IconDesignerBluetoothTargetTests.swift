import Testing
@testable import StatusTrioCore

@Suite("Icon designer Bluetooth target")
struct IconDesignerBluetoothTargetTests {
    private func device(_ address: String, name: String, kind: BluetoothDeviceKind,
                        connected: Bool = true) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: kind, isConnected: connected)
    }

    @Test func currentAudioOutputIsAnAudioTargetWithoutChoosingADevice() {
        #expect(IconDesignerBluetoothTargetModel.isAudioTarget(.currentAudioOutput, devices: []))
    }

    @Test func designatedAirPodsAreRecognizedByNormalizedAddress() {
        let airPods = device("aa:bb:cc:dd:ee:ff", name: "Renamed headset", kind: .audio)
        let target = IconDesignerBluetoothTarget.connectedDevice(address: "AA-BB-CC-DD-EE-FF")

        #expect(IconDesignerBluetoothTargetModel.isAudioTarget(target, devices: [airPods]))
    }

    @Test func sameNamedKeyboardIsNotMistakenForAudioDevice() {
        let audio = device("11:22:33:44:55:66", name: "Studio", kind: .audio)
        let keyboard = device("AA:BB:CC:DD:EE:FF", name: "Studio", kind: .peripheral(.keyboard))
        let target = IconDesignerBluetoothTarget.connectedDevice(address: keyboard.id)

        #expect(!IconDesignerBluetoothTargetModel.isAudioTarget(target, devices: [audio, keyboard]))
    }

    @Test func offlineAudioTargetIsNotPresentedAsOnline() {
        let airPods = device("AA:BB:CC:DD:EE:FF", name: "AirPods", kind: .audio, connected: false)
        let target = IconDesignerBluetoothTarget.connectedDevice(address: airPods.id)

        #expect(!IconDesignerBluetoothTargetModel.isAudioTarget(target, devices: [airPods]))
    }

    @Test func unboundLegacyGlyphIsNeverAssumedToBeAnOnlineAudioTarget() {
        #expect(!IconDesignerBluetoothTargetModel.isAudioTarget(.preservedUnboundGlyph, devices: []))
    }
    @Test func currentAndSpecifiedTargetsMapToTheIntendedRuntimeSources() {
        #expect(IconDesignerBluetoothTargetModel.source(for: .currentAudioOutput) == .bluetoothAudioOutput)
        #expect(IconDesignerBluetoothTargetModel.source(for: .connectedDevice(address: "AA:BB:CC:DD:EE:FF")) == .connectedBluetoothDevice)
        #expect(IconDesignerBluetoothTargetModel.source(for: .preservedUnboundGlyph) == .pinnedBluetoothGlyph)
    }

    @Test func connectedDeviceUsesSingleBluetoothChoiceInTheSourcePicker() {
        #expect(IconDesignerBluetoothTargetModel.displaySource(for: .connectedBluetoothDevice) == .bluetoothAudioOutput)
        #expect(IconDesignerBluetoothTargetModel.displaySource(for: .bluetoothAudioOutput) == .bluetoothAudioOutput)
        #expect(IconDesignerBluetoothTargetModel.displaySource(for: .pinnedBluetoothGlyph) == .pinnedBluetoothGlyph)
    }

    @Test func targetChangeUpdatesPrimaryAndFallbackBluetoothSourcesTogether() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(
            primary: .network,
            fallback: .bluetoothAudioOutput
        )
        configuration = IconDesignerBluetoothTargetModel.applying(
            .connectedDevice(address: "AA:BB:CC:DD:EE:FF"),
            to: configuration
        )

        #expect(configuration.composition.center.primary == .network)
        #expect(configuration.composition.center.fallback == .connectedBluetoothDevice)

        configuration = IconDesignerBluetoothTargetModel.applying(.currentAudioOutput, to: configuration)
        #expect(configuration.composition.center.primary == .network)
        #expect(configuration.composition.center.fallback == .bluetoothAudioOutput)
    }

    @Test func pickerDevicesIncludesConnectedTargetsAndSortsStable() {
        let beta = device("BB:00:00:00:00:02", name: "Beta", kind: .audio)
        let alpha = device("AA:00:00:00:00:01", name: "Alpha", kind: .audio)
        let offline = device("CC:00:00:00:00:03", name: "Offline", kind: .audio, connected: false)
        let keyboard = device("DD:00:00:00:00:04", name: "Keyboard", kind: .peripheral(.keyboard))

        let targets = IconDesignerBluetoothTargetModel.pickerDevices(
            [beta, offline, keyboard, alpha], selectedAddress: nil
        )
        #expect(targets.map(\.id) == [alpha.id, beta.id, keyboard.id])
    }

    @Test func pickerDevicesIncludesConnectedNonAudioTargetsAndExcludesNonLiveRows() {
        let audio = device("AA:00:00:00:00:01", name: "AirPods", kind: .audio)
        let keyboard = device("BB:00:00:00:00:02", name: "Keyboard", kind: .peripheral(.keyboard))
        let offline = device("CC:00:00:00:00:03", name: "Offline mouse", kind: .peripheral(.mouse), connected: false)
        let ghost = BluetoothDevice(
            id: "DD:00:00:00:00:04", name: "Ghost", kind: .peripheral(.mouse),
            isConnected: true, isUnpairedGhost: true
        )
        let remote = BluetoothDevice(
            id: "EE:00:00:00:00:05", name: "Remote", kind: .audio,
            isConnected: true, isReadOverTheAir: true
        )

        let options = IconDesignerBluetoothTargetModel.pickerDevices(
            [remote, keyboard, offline, ghost, audio], selectedAddress: nil
        )

        #expect(options.map(\.id) == [audio.id, keyboard.id])
    }

    @Test func pickerNeverTreatsCachedRowsAsOnlineWithoutBluetoothAvailability() {
        let staleAudio = device("CC:00:00:00:00:03", name: "Cached headset", kind: .audio)
        let staleKeyboard = device("DD:00:00:00:00:04", name: "Cached keyboard", kind: .peripheral(.keyboard))

        let targets = IconDesignerBluetoothTargetModel.pickerDevices(
            [staleAudio, staleKeyboard],
            selectedAddress: staleAudio.id,
            bluetoothAvailability: .authorizationDenied
        )

        #expect(targets.isEmpty)
    }

    @Test func offlineSelectedAudioTargetRemainsVisibleButNotAvailable() {
        let offline = device("CC:00:00:00:00:03", name: "Offline headset", kind: .audio, connected: false)
        let selected = IconDesignerBluetoothTargetModel.pickerDevices(
            [offline], selectedAddress: "cc-00-00-00-00-03"
        )

        #expect(selected.map(\.id) == [offline.id])
        #expect(!IconDesignerBluetoothTargetModel.isAudioTarget(
            .connectedDevice(address: offline.id), devices: [offline]
        ))
    }

}
