import SwiftUI

struct IconDesignerView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void
    @State private var selectedSlot: IconSlot = .outerRing
    @State private var previewScenario: IconPreviewScenario = .live

    @EnvironmentObject private var localization: Localization

    private func scenarioTitle(_ scenario: IconPreviewScenario) -> String {
        let key: LocalizationKey = switch scenario {
        case .live: .iconPreviewScenarioLive
        case .networkHealthy: .iconPreviewScenarioNetworkHealthy
        case .networkNoInternet: .iconPreviewScenarioNetworkNoInternet
        case .wifiOffEthernetConnected: .iconPreviewScenarioWifiOffEthernet
        case .batteryCharging: .iconPreviewScenarioBatteryCharging
        case .batteryCriticallyLow: .iconPreviewScenarioBatteryLow
        case .volumeMuted: .iconPreviewScenarioVolumeMuted
        case .airPodsConnected: .iconPreviewScenarioAirPodsConnected
        case .airPodsDisconnected: .iconPreviewScenarioAirPodsDisconnected
        }
        return localization.string(key)
    }

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark,
                scenario: previewScenario,
                showsResolutionExplanation: true
            )
        }) {
            IconSurfaceSettings(store: store, statusStore: statusStore, previewIsDark: $previewIsDark)
            SettingsGroup(localization.string(.iconDesignerTitle)) {
                Picker(localization.string(.iconDesignerPreviewScenario), selection: $previewScenario) {
                    ForEach(IconDesignerPreviewState.availableScenarios, id: \.self) { scenario in
                        Text(scenarioTitle(scenario)).tag(scenario)
                    }
                }
                IconSlotPicker(selection: $selectedSlot, configuration: store.iconConfiguration)
                IconSourceEditor(
                    store: store,
                    slot: selectedSlot,
                    phaseFiveEnabled: IconDesignerEditingModel.supportsImplementedSources(for: selectedSlot),
                    bluetoothDevices: statusStore.bluetoothDevices.devices
                )
                IconBehaviorEditor(
                    store: store,
                    slot: selectedSlot,
                    bluetoothDevices: statusStore.bluetoothDevices.devices,
                    bluetoothDeviceOrder: store.bluetoothDeviceOrder
                )
                IconAppearanceEditor(store: store, slot: selectedSlot)
                IconPresetPicker(store: store, slot: selectedSlot)
            }

            SettingsGroup(localization.string(.iconDesignerLearnMore)) {
                Button(action: onShowIconGuide) {
                    Label(localization.string(.iconDesignerGuide), systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
