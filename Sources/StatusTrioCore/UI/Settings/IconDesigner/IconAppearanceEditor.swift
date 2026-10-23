import SwiftUI

struct IconAppearanceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var bluetoothDevices: [BluetoothDevice] = []
    @State private var role: IconSemanticColorRole = .primary
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    var body: some View {
        SettingsGroup(localization.string(.iconDesignerAppearanceTitle)) {
            if showsColorStyle {
                IconDesignerControlRow(localization.string(.iconDesignerControlColorStyle)) {
                    Picker("", selection: styleBinding) {
                        Text(localization.string(.iconDesignerControlAutomatic)).tag(StyleChoice.automatic)
                        Text(localization.string(.iconDesignerControlFixedColor)).tag(StyleChoice.fixed)
                        Text(localization.string(.iconDesignerControlByState)).tag(StyleChoice.semantic)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(localization.string(.iconDesignerControlColorStyle))
                }
            }

            if showsScaleControl {
                scaleControl
            }

            if styleBinding.wrappedValue == .semantic, showsRolePicker {
                IconDesignerControlRow(
                    localization.string(slot == .center ? .iconDesignerCenterColorRolePicker : .iconDesignerControlState),
                    subtitle: slot == .center ? effectiveCenterRoleHelp : nil
                ) {
                    Picker("", selection: roleBinding) {
                        ForEach(roleOptions) { option in
                            Text(roleTitle(for: option)).tag(option.role)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: slot != .center, vertical: true)
                    .accessibilityLabel(localization.string(
                        slot == .center ? .iconDesignerCenterColorRolePicker : .iconDesignerControlState
                    ))
                }
            }

            if showsColorStyle, styleBinding.wrappedValue != .automatic {
                colorControls
            }
        }
        .accessibilityIdentifier("iconDesigner.appearanceCard")
        .onChange(of: centerColorRoleOptions) { _ in
            guard slot == .center else { return }
            if let effectiveRole = IconDesignerCenterColorRoleModel.effectiveRole(role, options: centerColorRoleOptions) {
                role = effectiveRole
            }
        }
    }

    private var showsColorStyle: Bool {
        slot != .center || !centerColorRoleOptions.isEmpty
    }

    private var showsRolePicker: Bool {
        slot != .center || centerColorRoleOptions.count > 1
    }

    private var roleOptions: [IconDesignerCenterColorRoleOption] {
        if slot == .center {
            return centerColorRoleOptions
        }
        return IconSemanticColorRole.allCases.map { role in
            IconDesignerCenterColorRoleOption(
                role: role,
                meanings: [.init(
                    scope: .primary,
                    localizationKey: role.iconDesignerLocalizationKey,
                    helpLocalizationKey: .iconDesignerCenterColorHelpNetworkPrimary
                )]
            )
        }
    }

    private var centerColorRoleOptions: [IconDesignerCenterColorRoleOption] {
        let isConnectedBluetoothDeviceAudio = store.connectedBluetoothIconDeviceAddress.map { address in
            IconDesignerBluetoothTargetModel.isAudioTarget(
                .connectedDevice(address: address),
                devices: bluetoothDevices
            )
        } ?? false
        return IconDesignerCenterColorRoleModel.options(
            in: store.iconConfiguration,
            connectedBluetoothDeviceIsAudio: isConnectedBluetoothDeviceAudio
        )
    }

    /// Resolve stale picker state synchronously so reads and writes always use
    /// a role that the current center configuration can actually render.
    private var effectiveRole: IconSemanticColorRole {
        guard slot == .center else { return role }
        return IconDesignerCenterColorRoleModel.effectiveRole(role, options: centerColorRoleOptions) ?? role
    }

    private var roleBinding: Binding<IconSemanticColorRole> {
        Binding(
            get: { effectiveRole },
            set: { role = slot == .center
                ? (IconDesignerCenterColorRoleModel.effectiveRole($0, options: centerColorRoleOptions) ?? role)
                : $0
            }
        )
    }

    private func roleTitle(for option: IconDesignerCenterColorRoleOption) -> String {
        guard slot == .center else {
            return localization.string(option.role.iconDesignerLocalizationKey)
        }
        return option.meanings.map { meaning in
            let text = localization.string(meaning.localizationKey)
            return switch meaning.scope {
            case .primary:
                text
            case .fallback:
                localization.format(.iconDesignerCenterColorContextFallbackFormat, text)
            case .networkOverride:
                localization.format(.iconDesignerCenterColorContextNetworkOverrideFormat, text)
            }
        }.joined(separator: " · ")
    }

    private func roleHelp(for option: IconDesignerCenterColorRoleOption) -> String {
        option.meanings.map { meaning in
            let text = localization.string(meaning.helpLocalizationKey)
            switch meaning.scope {
            case .primary:
                return text
            case .fallback:
                return localization.format(.iconDesignerCenterColorContextFallbackFormat, text)
            case .networkOverride:
                return localization.format(.iconDesignerCenterColorContextNetworkOverrideFormat, text)
            }
        }.joined(separator: " · ")
    }

    private var effectiveCenterRoleHelp: String? {
        guard slot == .center, styleBinding.wrappedValue == .semantic else { return nil }
        guard let option = centerColorRoleOptions.first(where: { $0.role == effectiveRole }) else { return nil }
        return roleHelp(for: option)
    }

    private var showsScaleControl: Bool {
        slot != .center || !centerColorRoleOptions.isEmpty
    }

    private var scaleControl: some View {
        let isCenter = slot == .center
        let scale = scaleBinding.wrappedValue
        let group = "appearance.scale.\(slot)"
        let range = isCenter
            ? IconDesignerEditingModel.commonPercentageScaleRange
            : IconStrokeSizingPolicy.interactiveScaleRange
        return IconDesignerScaleControl(
            title: localization.string(isCenter ? .iconDesignerControlSymbolScale : .iconDesignerControlStrokeScale),
            value: sliderBinding,
            formattedValue: isCenter
                ? IconDesignerEditingModel.commonPercentageScaleLabel(for: scale)
                : IconStrokeSizingPolicy.label(for: scale),
            range: range,
            step: isCenter ? IconCenterSizingPolicy.percentageStep : IconStrokeSizingPolicy.percentageStep,
            showsDivider: styleBinding.wrappedValue != .automatic,
            onEditingChanged: { editing in
                if editing { editorModel.beginCoalescingGroup(group) }
                else { editorModel.endCoalescingGroup(group) }
            }
        )
    }

    private var colorControls: some View {
        IconDesignerControlRow(colorPickerTitle, subtitle: effectiveCenterRoleHelp, showsDivider: true) {
            let group = "appearance.color.\(slot).\(effectiveRole)"
            IconDesignerColorWell(selection: colorBinding, onEditingChanged: { editing in
                if editing { editorModel.beginCoalescingGroup(group) }
                else { editorModel.endCoalescingGroup(group) }
            })
                .frame(width: 44, height: 24)
                .accessibilityLabel(colorPickerLabel)
                .accessibilityIdentifier("iconDesigner.appearance.colorPicker")
        }
    }

    private var colorPickerLabelKey: LocalizationKey {
        switch colorStyle {
        case .automatic, .fixed:
            .iconDesignerControlFixedColor
        case .semanticOverrides:
            effectiveRole.iconDesignerLocalizationKey
        }
    }

    private var colorPickerTitle: String {
        if slot == .center, styleBinding.wrappedValue == .semantic,
           let option = centerColorRoleOptions.first(where: { $0.role == effectiveRole }) {
            return roleTitle(for: option)
        }
        return localization.string(colorPickerLabelKey)
    }

    private var colorPickerLabel: String { colorPickerTitle }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { IconAppearanceColorConversion.color(from: currentColor) },
            set: { setCurrentColor(IconAppearanceColorConversion.iconRGBA(from: $0)) }
        )
    }

    private var styleBinding: Binding<StyleChoice> {
        Binding(get: {
            switch colorStyle {
            case .automatic: .automatic
            case .fixed: .fixed
            case .semanticOverrides: .semantic
            }
        }, set: { choice in
            editorModel.updateIconConfiguration { configuration in
                let previousStyle = Self.colorStyle(for: slot, in: configuration)
                let oldColor = IconAppearanceColorEditing.color(for: previousStyle, role: effectiveRole)
                let style: SlotColorStyle = switch choice {
                case .automatic:
                    .automatic
                case .fixed:
                    if case .fixed = previousStyle { previousStyle } else { .fixed(oldColor) }
                case .semantic:
                    if case .semanticOverrides = previousStyle {
                        previousStyle
                    } else {
                        .semanticOverrides([effectiveRole: oldColor])
                    }
                }
                Self.set(style, slot: slot, in: &configuration)
            }
        })
    }

    private var colorStyle: SlotColorStyle {
        Self.colorStyle(for: slot, in: store.iconConfiguration)
    }

    private static func colorStyle(for slot: IconSlot, in configuration: IconConfigurationV1) -> SlotColorStyle {
        switch slot {
        case .outerRing: configuration.appearance.outerRing.color
        case .center: configuration.appearance.center.color
        case .footer: configuration.appearance.footer.color
        }
    }

    private var currentColor: IconRGBA {
        IconAppearanceColorEditing.color(for: colorStyle, role: effectiveRole)
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                let rawValue = scaleBinding.wrappedValue
                if slot == .center {
                    return IconDesignerEditingModel.commonPercentageScaleSliderValue(for: rawValue)
                }
                return IconStrokeSizingPolicy.sliderValue(for: rawValue)
            },
            set: { scaleBinding.wrappedValue = $0 }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(get: {
            let configuration = store.iconConfiguration
            return switch slot {
            case .outerRing: configuration.appearance.outerRing.strokeScale
            case .center: IconDesignerEditingModel.commonPercentageScale(in: configuration)
            case .footer: configuration.appearance.footer.strokeScale
            }
        }, set: { value in
            editorModel.updateIconConfiguration(coalescingKey: "appearance.scale.\(slot)") { configuration in
                switch slot {
                case .outerRing:
                    configuration.appearance.outerRing.strokeScale = IconStrokeSizingPolicy.strokeScale(for: value)
                case .center:
                    IconDesignerEditingModel.settingCommonPercentageScale(value, in: &configuration)
                case .footer:
                    configuration.appearance.footer.strokeScale = IconStrokeSizingPolicy.strokeScale(for: value)
                }
            }
        })
    }

    private func setCurrentColor(_ color: IconRGBA) {
        editorModel.updateIconConfiguration(coalescingKey: "appearance.color.\(slot).\(effectiveRole)") { configuration in
            IconAppearanceColorEditing.setColor(color, role: effectiveRole, slot: slot, in: &configuration)
        }
    }

    private static func set(_ color: SlotColorStyle, slot: IconSlot, in configuration: inout IconConfigurationV1) {
        switch slot {
        case .outerRing: configuration.appearance.outerRing.color = color
        case .center: configuration.appearance.center.color = color
        case .footer: configuration.appearance.footer.color = color
        }
    }
}

private enum StyleChoice { case automatic, fixed, semantic }


enum IconDesignerRoleLabel {
    static func localizationKey(for role: IconSemanticColorRole) -> LocalizationKey {
        switch role {
        case .primary: .iconDesignerColorRolePrimary
        case .inactive: .iconDesignerColorRoleInactive
        case .critical: .iconDesignerColorRoleCritical
        case .lowPower: .iconDesignerColorRoleLowPower
        case .powered: .iconDesignerColorRolePowered
        case .bluetooth: .iconDesignerColorRoleBluetooth
        }
    }
}

extension IconSemanticColorRole {
    var iconDesignerLocalizationKey: LocalizationKey {
        IconDesignerRoleLabel.localizationKey(for: self)
    }
}
