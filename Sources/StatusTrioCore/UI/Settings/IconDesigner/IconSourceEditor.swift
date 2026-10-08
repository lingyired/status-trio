import SwiftUI

struct IconSourceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var phaseFiveEnabled = false

    private var sources: [IconDesignerSource] {
        IconDesignerEditingModel.selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled)
    }
    private var current: IconDesignerCurrentSource {
        IconDesignerEditingModel.currentSource(for: slot, in: store.iconConfiguration, phaseFiveEnabled: phaseFiveEnabled)
    }

    var body: some View {
        SettingsGroup("Sources") {
            Picker("Primary source", selection: primaryBinding) {
                ForEach(sources, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .accessibilityLabel("Primary source for \(slot.title)")

            if !current.isSelectable {
                Label("Current source (not available in this version): \(current.id)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if current.isLegacy {
                Text("Compatible with current configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Fallback source", selection: fallbackBinding) {
                Text("None").tag(IconDesignerSource?.none)
                ForEach(sources.filter { $0 != primary }, id: \.self) { source in
                    Text(source.title).tag(Optional(source))
                }
            }
            .accessibilityLabel("Fallback source for \(slot.title)")
            if fallbackBinding.wrappedValue != nil {
                Button("Swap primary and fallback") {
                    store.updateIconConfiguration { configuration in
                        _ = IconDesignerEditingModel.swapPrimaryAndFallback(for: slot, in: &configuration)
                    }
                }
                .accessibilityLabel("Swap primary and fallback for \(slot.title)")
            }
        }
    }

    private var primary: IconDesignerSource {
        switch slot {
        case .outerRing: .ring(store.iconConfiguration.composition.outerRing.primary)
        case .center: .center(store.iconConfiguration.composition.center.primary)
        case .footer: .footer(store.iconConfiguration.composition.footer.primary)
        }
    }

    private var primaryBinding: Binding<IconDesignerSource> {
        Binding(get: { primary }, set: { value in
            store.updateIconConfiguration { configuration in
                _ = IconDesignerEditingModel.setPrimary(value, for: slot, in: &configuration, phaseFiveEnabled: phaseFiveEnabled)
            }
        })
    }

    private var fallbackBinding: Binding<IconDesignerSource?> {
        Binding(get: {
            switch slot {
            case .outerRing:
                if let value = store.iconConfiguration.composition.outerRing.fallback { .ring(value) } else { nil }
            case .center:
                if let value = store.iconConfiguration.composition.center.fallback { .center(value) } else { nil }
            case .footer:
                if let value = store.iconConfiguration.composition.footer.fallback { .footer(value) } else { nil }
            }
        }, set: { value in
            store.updateIconConfiguration { configuration in
                _ = IconDesignerEditingModel.setFallback(value, for: slot, in: &configuration, phaseFiveEnabled: phaseFiveEnabled)
            }
        })
    }
}

private extension IconDesignerSource {
    var title: String {
        let words = rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return words == "automaticLegacy" ? "Compatible with current configuration" : words.capitalized
    }
}

private extension IconSlot {
    var title: String {
        switch self { case .outerRing: "outer ring"; case .center: "center"; case .footer: "footer" }
    }
}
