import Foundation
import Testing
@testable import StatusTrioCore

/// The dropdown's contents, decided outside the view.
///
/// A SwiftUI menu `Picker` cannot be inspected from a test — macOS 26 renders it
/// without an AppKit control — so the list it draws is built here instead of
/// inside the view body, and pinned here. That is also what keeps the menu flat:
/// a `Section` inside the picker's content was dropped on macOS, which left the
/// menu showing the audio entry alone.
struct BluetoothNetworkIconSourceOptionTests {
    @Test func audioIconChoiceIsShownOnlyWhenAudioIsTheEffectiveNetworkSource() {
        #expect(BluetoothNetworkIconSource.shouldShowAudioIconChoice(
            replacingNetworkIcon: true,
            selectedSource: .audioDevices
        ))
        #expect(!BluetoothNetworkIconSource.shouldShowAudioIconChoice(
            replacingNetworkIcon: false,
            selectedSource: .audioDevices
        ))
        #expect(!BluetoothNetworkIconSource.shouldShowAudioIconChoice(
            replacingNetworkIcon: true,
            selectedSource: .device(address: "AABB")
        ))
        #expect(!BluetoothNetworkIconSource.shouldShowAudioIconChoice(
            replacingNetworkIcon: false,
            selectedSource: .device(address: "AABB")
        ))
    }

    @Test func optionsLeadWithTheAudioDevice() {
        let options = BluetoothNetworkIconSourceOption.options(
            devices: [device("MX Keys", kind: .peripheral(.keyboard), isConnected: false)],
            order: []
        )

        #expect(options.first?.source == .audioDevices)
        #expect(options.first?.title == nil, "the audio entry's title comes from localization")
        #expect(options.count == 2)
    }

    @Test func optionsFollowThePanelOrderAndPinTheDeviceGlyph() {
        let airPods = device("AirPods Pro", kind: .audio, isConnected: true, id: "AC:90:85:C2:9C:1F")
        let mouse = device("MX Master 3", kind: .peripheral(.mouse), isConnected: false, id: "AA:BB:CC:DD:EE:FF")

        let options = BluetoothNetworkIconSourceOption.options(
            devices: [mouse, airPods],
            order: []
        )

        // Connected devices lead, exactly as the panel list orders them.
        #expect(options.map(\.source) == [
            .audioDevices,
            .device(address: "AC9085C29C1F"),
            .device(address: "AABBCCDDEEFF")
        ])
        #expect(options[1].symbolName == BluetoothDeviceRowIcon.symbolName(for: airPods))
        #expect(options[2].symbolName == "computermouse")
    }

    @Test func appleWatchModelPinsItsIconForTheSharedNetworkSource() {
        let watch = BluetoothDevice(
            id: "watch-id",
            name: "Kitchen timer",
            kind: .mobile(.watch),
            isConnected: false,
            appleMobileModel: "Watch7,1"
        )

        let option = BluetoothNetworkIconSourceOption.options(devices: [watch], order: [watch.id])[1]

        #expect(option.symbolName == "applewatch")
    }

    /// A ghost has no class, so it carries no glyph worth pinning; the menu
    /// offers only devices the user can see in System Settings.
    @Test func optionsSkipGhostDevices() {
        let ghost = BluetoothDevice(
            id: "11:22:33:44:55:66",
            name: "Ghost",
            kind: .unknown,
            isConnected: false,
            isUnpairedGhost: true
        )

        let options = BluetoothNetworkIconSourceOption.options(devices: [ghost], order: [])

        #expect(options.map(\.source) == [.audioDevices])
    }

    /// The address is the same fingerprint the store persists (hex digits,
    /// uppercased), so the menu's tag and the saved choice can never disagree.
    @Test func optionsAddressIsNormalizedForBothPickerAndStore() {
        let device = device("MX Keys", kind: .peripheral(.keyboard), isConnected: false, id: "D3:6D:6C:40:A3:2E")

        let options = BluetoothNetworkIconSourceOption.options(devices: [device], order: [])

        #expect(options[1].source == .device(address: "D36D6C40A32E"))
        #expect(options[1].source.id == "D36D6C40A32E")
    }

    /// Whether the menu can offer a device at all. The pane uses this to
    /// explain the single-entry menu: without a readable device — no grant yet,
    /// nothing paired — the audio entry is the only row there is, and saying so
    /// is what keeps that from reading as a broken menu.
    @Test func listsDevicesIgnoresGhostsAndEmptyLists() {
        #expect(BluetoothNetworkIconSourceOption.listsDevices(devices: []) == false)
        #expect(
            BluetoothNetworkIconSourceOption.listsDevices(devices: [
                BluetoothDevice(
                    id: "11:22:33:44:55:66",
                    name: "Ghost",
                    kind: .unknown,
                    isConnected: false,
                    isUnpairedGhost: true
                )
            ]) == false
        )
        #expect(
            BluetoothNetworkIconSourceOption.listsDevices(devices: [
                device("MX Keys", kind: .peripheral(.keyboard), isConnected: false)
            ])
        )
    }

    private func device(
        _ name: String,
        kind: BluetoothDeviceKind,
        isConnected: Bool,
        id: String = "AC:90:85:C2:9C:1F"
    ) -> BluetoothDevice {
        BluetoothDevice(id: id, name: name, kind: kind, isConnected: isConnected)
    }
}
