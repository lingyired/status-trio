import SwiftUI

struct IconDesignerBluetoothEditor: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    private var selectedAddress: String? {
        store.connectedBluetoothIconDeviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) }
    }

    private var pickerDevices: [BluetoothDevice] {
        IconDesignerBluetoothTargetModel.pickerDevices(
            bluetoothDevices.devices,
            selectedAddress: selectedAddress,
            bluetoothAvailability: bluetoothDevices.availability
        )
    }

    var body: some View {
        Group {
            if bluetoothDevices.authorization != .allowed {
                BluetoothPermissionNoticeRow(bluetoothDevices: bluetoothDevices, statusStore: statusStore)
            } else {
                IconDesignerControlRow(
                    localization.string(.iconDesignerControlSelectConnectedBluetoothDevice),
                    subtitle: localization.string(.iconDesignerSourceBluetoothAudio),
                    identifier: "iconDesigner.bluetooth.target",
                    showsDivider: false
                ) {
                    Picker("", selection: targetBinding) {
                        Text(localization.string(.iconDesignerSourceBluetoothAudio)).tag(String?.none)
                        ForEach(pickerDevices, id: \.id) { device in
                            Text(device.name).tag(Optional(BluetoothBatteryReader.normalizedAddress(device.id)))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(localization.string(.iconDesignerControlSelectConnectedBluetoothDevice))
                    .accessibilityIdentifier("iconDesigner.bluetooth.targetPicker")
                }
                if selectedTargetIsOffline {
                    SettingsHintRow(text: localization.string(.iconResolutionUnavailableDisconnected))
                }
                if pickerDevices.isEmpty, selectedAddress == nil {
                    SettingsHintRow(text: localization.string(.iconDesignerControlNoBluetoothDevices))
                }
            }
        }
    }

    private var selectedTargetIsOffline: Bool {
        guard let selectedAddress else { return false }
        guard bluetoothDevices.availability == .available else { return true }
        return !IconDesignerBluetoothTargetModel.isConnectedTarget(
            .connectedDevice(address: selectedAddress),
            devices: bluetoothDevices.devices
        )
    }

    private var targetBinding: Binding<String?> {
        Binding(
            get: { selectedAddress },
            set: { value in
                let target: IconDesignerBluetoothTarget
                if let value {
                    target = .connectedDevice(address: BluetoothBatteryReader.normalizedAddress(value))
                } else {
                    target = .currentAudioOutput
                }
                editorModel.perform {
                    store.connectedBluetoothIconDeviceAddress = value.map { BluetoothBatteryReader.normalizedAddress($0) }
                    store.updateIconConfiguration { configuration in
                        configuration = IconDesignerBluetoothTargetModel.applying(target, to: configuration)
                    }
                }
            }
        )
    }
}
