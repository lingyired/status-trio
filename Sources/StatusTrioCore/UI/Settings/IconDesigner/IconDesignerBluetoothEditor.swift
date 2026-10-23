import SwiftUI

struct IconDesignerBluetoothEditor: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @ObservedObject var statusStore: SystemStatusStore
    var behaviorTarget: IconDesignerBehaviorTarget = .primary
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    private var selectedAddress: String? {
        IconDesignerBluetoothTargetModel.selectedAddress(for: behaviorTarget, in: store.iconConfiguration,
            deviceAddress: store.connectedBluetoothIconDeviceAddress)
    }

    private var source: IconDesignerSource? {
        IconDesignerEditingModel.source(for: behaviorTarget, slot: .center, in: store.iconConfiguration)
    }

    private var otherSource: CenterSource? {
        behaviorTarget == .primary ? store.iconConfiguration.composition.center.fallback : store.iconConfiguration.composition.center.primary
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
                            .disabled(otherSource == .bluetoothAudioOutput)
                        if source == .center(.connectedBluetoothDevice), selectedAddress == nil {
                            Text(localization.string(.iconDesignerControlChooseBluetoothDevice)).tag(Optional(""))
                        }
                        ForEach(pickerDevices, id: \.id) { device in
                            Text(device.name).tag(Optional(BluetoothBatteryReader.normalizedAddress(device.id)))
                                .disabled(otherSource == .connectedBluetoothDevice)
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
            get: { source == .center(.connectedBluetoothDevice) ? selectedAddress ?? "" : nil },
            set: { value in
                guard value != "" else { return }
                let target: IconDesignerBluetoothTarget
                if let value {
                    target = .connectedDevice(address: BluetoothBatteryReader.normalizedAddress(value))
                } else {
                    target = .currentAudioOutput
                }
                editorModel.perform {
                    var configuration = store.iconConfiguration
                    var address = store.connectedBluetoothIconDeviceAddress
                    guard IconDesignerBluetoothTargetModel.setTarget(target, for: behaviorTarget,
                        in: &configuration, deviceAddress: &address) else { return }
                    store.updateIconConfiguration { $0 = configuration }
                    store.connectedBluetoothIconDeviceAddress = address
                }
            }
        )
    }
}
