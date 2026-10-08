import SwiftUI

struct IconAppearanceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    @State private var role: IconSemanticColorRole = .primary
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(.iconDesignerAppearanceTitle)) {
            Picker(localization.string(.iconDesignerControlColorStyle), selection: styleBinding) {
                Text(localization.string(.iconDesignerControlAutomatic)).tag(StyleChoice.automatic)
                Text(localization.string(.iconDesignerControlFixedColor)).tag(StyleChoice.fixed)
                Text(localization.string(.iconDesignerControlByState)).tag(StyleChoice.semantic)
            }
            if slot != .center {
                Slider(value: scaleBinding, in: 0.5...2.5, step: 0.05) {
                    Text(localization.string(.iconDesignerControlStrokeScale))
                }
            } else {
                Slider(value: scaleBinding, in: 1...3, step: 0.05) {
                    Text(localization.string(.iconDesignerControlSymbolScale))
                }
            }
            if styleBinding.wrappedValue != .automatic {
                if styleBinding.wrappedValue == .semantic {
                    Picker(localization.string(.iconDesignerControlState), selection: $role) {
                        ForEach(IconSemanticColorRole.allCases, id: \.self) { value in
                            Text(localization.string(value.iconDesignerLocalizationKey)).tag(value)
                        }
                    }
                }
                colorControls
            }
        }
    }

    private var colorControls: some View {
        let color = currentColor
        return Group {
            componentSlider(localization.string(.iconDesignerControlRed), value: color.red, keyPath: \.red)
            componentSlider(localization.string(.iconDesignerControlGreen), value: color.green, keyPath: \.green)
            componentSlider(localization.string(.iconDesignerControlBlue), value: color.blue, keyPath: \.blue)
            componentSlider(localization.string(.iconDesignerControlOpacity), value: color.alpha, keyPath: \.alpha)
        }
    }

    private func componentSlider(_ title: String, value: Double, keyPath: WritableKeyPath<IconRGBA, Double>) -> some View {
        Slider(value: Binding(
            get: { value },
            set: { component in
                var updated = currentColor
                updated[keyPath: keyPath] = component
                setCurrentColor(updated)
            }
        ), in: 0...1) { Text(title) }
    }

    private var styleBinding: Binding<StyleChoice> {
        Binding(get: {
            switch colorStyle {
            case .automatic: .automatic
            case .fixed: .fixed
            case .semanticOverrides: .semantic
            }
        }, set: { choice in
            store.updateIconConfiguration { configuration in
                let oldColor = currentColor
                let style: SlotColorStyle = switch choice {
                case .automatic: .automatic
                case .fixed: .fixed(oldColor)
                case .semantic: .semanticOverrides([role: oldColor])
                }
                Self.set(style, slot: slot, in: &configuration)
            }
        })
    }

    private var colorStyle: SlotColorStyle {
        switch slot {
        case .outerRing: store.iconConfiguration.appearance.outerRing.color
        case .center: store.iconConfiguration.appearance.center.color
        case .footer: store.iconConfiguration.appearance.footer.color
        }
    }

    private var currentColor: IconRGBA {
        switch colorStyle {
        case .automatic: .white
        case let .fixed(color): color
        case let .semanticOverrides(colors): colors[role] ?? colors[.primary] ?? .white
        }
    }

    private var scaleBinding: Binding<Double> {
        Binding(get: {
            switch slot {
            case .outerRing: store.iconConfiguration.appearance.outerRing.strokeScale
            case .center: store.iconConfiguration.appearance.center.symbolScale
            case .footer: store.iconConfiguration.appearance.footer.strokeScale
            }
        }, set: { value in
            store.updateIconConfiguration { configuration in
                switch slot {
                case .outerRing: configuration.appearance.outerRing.strokeScale = value
                case .center: configuration.appearance.center.symbolScale = value
                case .footer: configuration.appearance.footer.strokeScale = value
                }
            }
        })
    }

    private func setCurrentColor(_ color: IconRGBA) {
        store.updateIconConfiguration { configuration in
            let style: SlotColorStyle
            switch colorStyle {
            case .automatic: style = .fixed(color)
            case .fixed: style = .fixed(color)
            case var .semanticOverrides(colors): colors[role] = color; style = .semanticOverrides(colors)
            }
            Self.set(style, slot: slot, in: &configuration)
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
