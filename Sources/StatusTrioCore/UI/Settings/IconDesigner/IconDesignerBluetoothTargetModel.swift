import Foundation

struct IconDesignerBluetoothTargetModel {
    static func displaySource(for source: CenterSource) -> CenterSource {
        switch source {
        case .connectedBluetoothDevice: .bluetoothAudioOutput
        case .bluetoothAudioOutput, .pinnedBluetoothGlyph: source
        default: source
        }
    }

    static func source(for target: IconDesignerBluetoothTarget) -> CenterSource {
        switch target {
        case .currentAudioOutput:
            return .bluetoothAudioOutput
        case .connectedDevice:
            return .connectedBluetoothDevice
        case .preservedUnboundGlyph:
            return .pinnedBluetoothGlyph
        }
    }


    static func applying(
        _ target: IconDesignerBluetoothTarget,
        to configuration: IconConfigurationV1
    ) -> IconConfigurationV1 {
        var copy = configuration
        let selectedSource = source(for: target)
        let selection = copy.composition.center
        let primary = isBluetoothSource(selection.primary) ? selectedSource : selection.primary
        let fallback = selection.fallback.map { isBluetoothSource($0) ? selectedSource : $0 }
        copy.composition.center = SlotSelection(primary: primary, fallback: fallback)
        return copy.normalized()
    }

    /// Returns connected, locally paired devices for new choices and retains a
    /// selected offline device as a visible, unavailable selection. Device actions
    /// and external battery-only rows are never included.
    static func pickerDevices(
        _ devices: [BluetoothDevice],
        selectedAddress: String?,
        bluetoothAvailability: BluetoothAvailability = .available
    ) -> [BluetoothDevice] {
        guard bluetoothAvailability == .available else { return [] }
        let selectedKey = selectedAddress.map { BluetoothBatteryReader.normalizedAddress($0) }
        var candidates = devices.filter { device in
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty, !device.isUnpairedGhost, !device.isReadOverTheAir else { return false }
            return device.isConnected || (selectedKey != nil && address == selectedKey)
        }
        candidates.sort {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return BluetoothBatteryReader.normalizedAddress($0.id)
                < BluetoothBatteryReader.normalizedAddress($1.id)
        }
        return candidates
    }

    static func isConnectedTarget(_ target: IconDesignerBluetoothTarget, devices: [BluetoothDevice]) -> Bool {
        guard case let .connectedDevice(address) = target else { return target == .currentAudioOutput }
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { return false }
        return devices.contains {
            $0.isConnected && !$0.isUnpairedGhost && !$0.isReadOverTheAir
                && BluetoothBatteryReader.normalizedAddress($0.id) == key
        }
    }

    static func isAudioTarget(_ target: IconDesignerBluetoothTarget, devices: [BluetoothDevice]) -> Bool {
        switch target {
        case .currentAudioOutput:
            return true
        case let .connectedDevice(address):
            let normalizedAddress = BluetoothBatteryReader.normalizedAddress(address)
            guard !normalizedAddress.isEmpty else { return false }
            return devices.contains {
                $0.isConnected && !$0.isUnpairedGhost && !$0.isReadOverTheAir && $0.kind.isAudio
                    && BluetoothBatteryReader.normalizedAddress($0.id) == normalizedAddress
            }
        case .preservedUnboundGlyph:
            return false
        }
    }

    private static func isBluetoothSource(_ source: CenterSource) -> Bool {
        source == .bluetoothAudioOutput || source == .connectedBluetoothDevice
    }
}
