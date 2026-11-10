import Foundation

enum IconDesignerCenterColorRoleScope: Equatable {
    case primary
    case fallback
    case networkOverride
}

struct IconDesignerCenterColorRoleMeaning: Equatable {
    let scope: IconDesignerCenterColorRoleScope
    let localizationKey: LocalizationKey
    let helpLocalizationKey: LocalizationKey
}

struct IconDesignerCenterColorRoleOption: Equatable, Identifiable {
    let role: IconSemanticColorRole
    let meanings: [IconDesignerCenterColorRoleMeaning]

    var id: IconSemanticColorRole { role }
}

enum IconDesignerCenterColorRoleModel {
    static func options(
        in rawConfiguration: IconConfigurationV1,
        connectedBluetoothDeviceIsAudio: Bool
    ) -> [IconDesignerCenterColorRoleOption] {
        let configuration = rawConfiguration.normalized()
        var meaningsByRole: [IconSemanticColorRole: [IconDesignerCenterColorRoleMeaning]] = [:]

        func add(
            _ role: IconSemanticColorRole,
            _ localizationKey: LocalizationKey,
            _ helpLocalizationKey: LocalizationKey,
            _ scope: IconDesignerCenterColorRoleScope
        ) {
            let meaning = IconDesignerCenterColorRoleMeaning(
                scope: scope,
                localizationKey: localizationKey,
                helpLocalizationKey: helpLocalizationKey
            )
            if meaningsByRole[role, default: []].contains(meaning) { return }
            meaningsByRole[role, default: []].append(meaning)
        }

        func addSource(_ source: CenterSource, scope: IconDesignerCenterColorRoleScope) {
            switch source {
            case .inputSource:
                add(.primary, .iconDesignerCenterColorMeaningInputSource, .iconDesignerCenterColorHelpInputSource, scope)
            case .network:
                add(.primary, .iconDesignerCenterColorMeaningNetworkPrimary, .iconDesignerCenterColorHelpNetworkPrimary, scope)
                add(.inactive, .iconDesignerCenterColorMeaningWiFiZeroBars, .iconDesignerCenterColorHelpWiFiZeroBars, scope)
            case .bluetoothAudioOutput, .connectedBluetoothDevice:
                let isAudioTarget = source == .bluetoothAudioOutput || connectedBluetoothDeviceIsAudio
                guard isAudioTarget, configuration.behaviors.bluetoothAudioCenter.usesVolumeColor else {
                    add(.bluetooth, .iconDesignerCenterColorMeaningBluetoothGlyph, .iconDesignerCenterColorHelpBluetoothGlyph, scope)
                    return
                }
                add(.primary, .iconDesignerCenterColorMeaningBluetoothMutedZeroOrUnavailable, .iconDesignerCenterColorHelpBluetoothMutedZeroOrUnavailable, scope)
                add(.bluetooth, .iconDesignerCenterColorMeaningBluetoothVolumeAboveZero, .iconDesignerCenterColorHelpBluetoothVolumeAboveZero, scope)
            case .pinnedBluetoothGlyph:
                add(.bluetooth, .iconDesignerCenterColorMeaningBluetoothGlyph, .iconDesignerCenterColorHelpBluetoothGlyph, scope)
            case .systemBatteryPercentage, .chargingStatus, .power:
                add(.primary, .iconDesignerCenterColorMeaningBatteryPercentage, .iconDesignerCenterColorHelpBatteryPercentage, scope)
            case .automaticLegacy:
                add(.primary, .iconDesignerCenterColorMeaningLegacyPrimary, .iconDesignerCenterColorHelpLegacyPrimary, scope)
                add(.inactive, .iconDesignerCenterColorMeaningLegacyWiFiZeroBars, .iconDesignerCenterColorHelpLegacyWiFiZeroBars, scope)
                add(.bluetooth, .iconDesignerCenterColorMeaningLegacyBluetoothGlyph, .iconDesignerCenterColorHelpLegacyBluetoothGlyph, scope)
            case .none:
                break
            }
        }

        let center = configuration.composition.center
        addSource(center.primary, scope: .primary)
        if let fallback = center.fallback {
            addSource(fallback, scope: .fallback)
        }

        // The global network override can replace any centre source (including
        // none), so expose the reachable network primary role whenever it is on.
        if configuration.composition.centerOverride.networkProblemOverridesPrimary {
            add(.primary, .iconDesignerCenterColorMeaningNetworkPrimary, .iconDesignerCenterColorHelpNetworkPrimary, .networkOverride)
        }

        return IconSemanticColorRole.allCases.compactMap { role in
            guard let meanings = meaningsByRole[role], !meanings.isEmpty else { return nil }
            return IconDesignerCenterColorRoleOption(role: role, meanings: meanings)
        }
    }

    static func effectiveRole(
        _ selected: IconSemanticColorRole,
        options: [IconDesignerCenterColorRoleOption]
    ) -> IconSemanticColorRole? {
        options.contains { $0.role == selected } ? selected : options.first?.role
    }
}
