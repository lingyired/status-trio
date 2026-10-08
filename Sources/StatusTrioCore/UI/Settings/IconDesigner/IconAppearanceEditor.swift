import SwiftUI

struct IconAppearanceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    @State private var role: IconSemanticColorRole = .primary

    var body: some View {
        SettingsGroup("Appearance") {
            Picker("Color style", selection: styleBinding) {
                Text("Automatic").tag(StyleChoice.automatic)
                Text("Fixed color").tag(StyleChoice.fixed)
                Text("By state").tag(StyleChoice.semantic)
            }
            if slot != .center {
                Slider(value: scaleBinding, in: 0.5...2.5, step: 0.05) {
                    Text("Stroke scale")
                }
            } else {
                Slider(value: scaleBinding, in: 1...3, step: 0.05) {
                    Text("Symbol scale")
                }
            }
            if styleBinding.wrappedValue != .automatic {
                if styleBinding.wrappedValue == .semantic {
                    Picker("State", selection: $role) {
                        ForEach(IconSemanticColorRole.allCases, id: \.self) { value in
                            Text(value.rawValue.capitalized).tag(value)
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
            componentSlider("Red", value: color.red, keyPath: \.red)
            componentSlider("Green", value: color.green, keyPath: \.green)
            componentSlider("Blue", value: color.blue, keyPath: \.blue)
            componentSlider("Opacity", value: color.alpha, keyPath: \.alpha)
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
