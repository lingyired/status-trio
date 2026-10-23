import SwiftUI

struct IconDesignerAlertSection: View {
    @ObservedObject var store: SettingsStore
    @State private var isExpanded = false
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    var body: some View {
        SettingsGroup {
            DisclosureGroup(localization.string(.iconDesignerAlertsTitle), isExpanded: $isExpanded) {
                globalNetworkOverrideControl
            }
            .disclosureGroupStyle(IconDesignerDisclosureStyle())
        }
        .accessibilityIdentifier("iconDesigner.alerts")
    }

    private var globalNetworkOverrideControl: some View {
        IconDesignerControlRow(
            localization.string(.iconDesignerControlNetworkProblemsOverride),
            subtitle: localization.string(.iconDesignerControlNetworkProblemsOverrideHelp),
            identifier: "iconDesigner.centerNetworkOverride"
        ) {
            Toggle("", isOn: Binding(
                get: { store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary },
                set: { value in
                    editorModel.updateIconConfiguration {
                        $0.composition.centerOverride.networkProblemOverridesPrimary = value
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(localization.string(.iconDesignerControlNetworkProblemsOverride))
            .accessibilityIdentifier("iconDesigner.centerNetworkOverride.toggle")
        }
    }
}
