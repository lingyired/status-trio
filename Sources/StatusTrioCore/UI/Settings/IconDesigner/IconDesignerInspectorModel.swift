enum IconDesignerInspectorModel {
    static func showsAppearance(slot: IconSlot, configuration: IconConfigurationV1, targetIsAudio: Bool) -> Bool {
        if slot == .center {
            return !IconDesignerCenterColorRoleModel.options(in: configuration,
                connectedBluetoothDeviceIsAudio: targetIsAudio).isEmpty
        }
        return IconDesignerEditingModel.source(for: .primary, slot: slot, in: configuration)?.pluginBinding != nil
    }

    static func fallbackSetupReason(slot: IconSlot, configuration: IconConfigurationV1, bluetoothAuthorized: Bool,
                                    devices: [BluetoothDevice], airPodsAddress: String?, connectedDeviceAddress: String?) -> LocalizationKey? {
        guard let source = IconDesignerEditingModel.source(for: .fallback, slot: slot, in: configuration),
              let binding = source.pluginBinding else { return nil }
        let dependencies = BuiltinIconPlugins.makeRegistry().dependencies(for: binding,
            context: .init(configuration: configuration, targetIsAudio: false))
        if dependencies.requiresBluetoothMonitor, !bluetoothAuthorized { return .settingsBluetoothPermissionRequired }
        if source == .ring(.airPodsBattery) {
            let candidates = devices.filter { $0.isConnected && $0.airPodsModel != nil }
            let address = airPodsAddress.map { BluetoothBatteryReader.normalizedAddress($0) }
            if (address == nil || address?.isEmpty == true), candidates.count > 1 { return .iconDesignerControlChooseBluetoothDevice }
            if !AirPodsBatteryIconSnapshot.hasConnectedSelection(devices: candidates, selectedAddress: airPodsAddress) {
                return .iconResolutionUnavailableDisconnected
            }
        } else if source == .center(.connectedBluetoothDevice) {
            guard let address = connectedDeviceAddress, !BluetoothBatteryReader.normalizedAddress(address).isEmpty else {
                return .iconDesignerControlChooseBluetoothDevice
            }
            if !IconDesignerBluetoothTargetModel.isConnectedTarget(.connectedDevice(address: address), devices: devices) {
                return .iconResolutionUnavailableDisconnected
            }
        }
        return nil
    }

    static func effectiveTarget(_ target: IconDesignerBehaviorTarget, slot: IconSlot,
                                configuration: IconConfigurationV1) -> IconDesignerBehaviorTarget {
        IconDesignerEditingModel.effectiveBehaviorTarget(target, slot: slot, in: configuration)
    }

    static func hasEditableBehavior(slot: IconSlot, target: IconDesignerBehaviorTarget,
                                   configuration: IconConfigurationV1, targetIsAudio: Bool,
                                   registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> Bool {
        // A removed fallback must not expose controls that edit the primary.
        guard target == .primary || effectiveTarget(target, slot: slot, configuration: configuration) == target,
              let source = IconDesignerEditingModel.source(for: target, slot: slot, in: configuration),
              let binding = source.pluginBinding else { return false }
        return !registry.capabilities(for: binding,
            context: .init(configuration: configuration, targetIsAudio: targetIsAudio)).isEmpty
    }

    static func displayedSourceName(for trace: SlotResolutionTrace) -> LocalizationKey {
        trace.selectedSourceID.flatMap { IconDesignerSourceSelection.localizationKey(forRawSourceID: $0) }
            ?? .iconDesignerSourceNone
    }

    static func trace(for slot: IconSlot, in trace: IconResolutionTrace) -> SlotResolutionTrace {
        switch slot {
        case .outerRing: trace.outerRing
        case .center: trace.center
        case .footer: trace.footer
        }
    }

    static func displayedValue(for slot: IconSlot, in scene: IconSceneState) -> String? {
        // Use only text actually supplied to drawing; an arc's geometry is not
        // necessarily the raw metric (for example a battery full threshold).
        switch slot {
        case .outerRing:
            if case let .text(text) = scene.outerRing?.accessory { return text.text }
        case .center:
            if case let .text(text) = scene.center { return text.text }
        case .footer: break
        }
        return nil
    }

    static func slotName(_ slot: IconSlot) -> LocalizationKey {
        switch slot {
        case .outerRing: .iconDesignerSlotOuterRing
        case .center: .iconDesignerSlotCenter
        case .footer: .iconDesignerSlotFooter
        }
    }
}
