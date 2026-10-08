import SwiftUI

struct IconDesignerView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void
    @State private var selectedSlot: IconSlot = .outerRing

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )
        }) {
            IconSurfaceSettings(store: store, statusStore: statusStore, previewIsDark: $previewIsDark)
            SettingsGroup("Icon Designer") {
                IconSlotPicker(selection: $selectedSlot)
                IconSourceEditor(store: store, slot: selectedSlot)
                IconBehaviorEditor(
                    store: store,
                    slot: selectedSlot,
                    bluetoothDevices: statusStore.bluetoothDevices.devices,
                    bluetoothDeviceOrder: store.bluetoothDeviceOrder
                )
                IconAppearanceEditor(store: store, slot: selectedSlot)
                IconPresetPicker(store: store, slot: selectedSlot)
            }

            SettingsGroup("Learn more") {
                Button(action: onShowIconGuide) {
                    Label("Icon guide", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
