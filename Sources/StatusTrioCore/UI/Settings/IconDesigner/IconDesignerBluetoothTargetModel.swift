import Foundation

struct IconDesignerBluetoothTargetModel {
    static func selectedAddress(for role: IconDesignerBehaviorTarget, in configuration: IconConfigurationV1,
                                deviceAddress: String?) -> String? {
        guard IconDesignerEditingModel.source(for: role, slot: .center, in: configuration) == .center(.connectedBluetoothDevice) else { return nil }
        return deviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// V1 stores one device address. Never clear an address another role still
    /// uses, or normalize a colliding choice by silently deleting its fallback.
    @discardableResult
    static func setTarget(_ target: IconDesignerBluetoothTarget, for role: IconDesignerBehaviorTarget,
                          in configuration: inout IconConfigurationV1, deviceAddress: inout String?) -> Bool {
        guard case let .center(current) = IconDesignerEditingModel.source(for: role, slot: .center, in: configuration),
              isBluetoothSource(current) || current == .pinnedBluetoothGlyph else { return false }
        let candidate = source(for: target)
        let other = role == .primary ? configuration.composition.center.fallback : configuration.composition.center.primary
        guard candidate != other else { return false }
        var address = deviceAddress
        if case let .connectedDevice(rawAddress) = target {
            let normalized = BluetoothBatteryReader.normalizedAddress(rawAddress)
            guard !normalized.isEmpty else { return false }
            address = normalized
        }
        var copy = configuration
        switch role {
        case .primary: copy.composition.center.primary = candidate
        case .fallback: copy.composition.center.fallback = candidate
        }
        if copy.composition.center.primary != .connectedBluetoothDevice,
           copy.composition.center.fallback != .connectedBluetoothDevice { address = nil }
        configuration = copy.normalized()
        deviceAddress = address
        return true
    }

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
