import AppKit
import SwiftUI

/// Pinned menu-bar preview for the instances page.
///
/// Uses the same menu-bar simulation as the other Settings panes, with the
/// selected instance's rendered item placed immediately to the left of the
/// app's own status icon.
struct MenuBarInstancePreviewCard: View {
    let model: MenuBarInstanceEditorModel?
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var hardwareObservable: HardwareMonitorObservable
    @ObservedObject var powerSampling: PowerSamplingService
    @Binding var isDarkBackground: Bool
    let localization: Localization
    @State private var hardwareRevision = 0

    var body: some View {
        VStack(spacing: 8) {
            MenuBarPreviewBar(
                status: MenuBarStatus(snapshot: statusStore.snapshot),
                iconSize: store.iconSize,
                batteryOptions: store.batteryIconOptions,
                connectionOptions: store.connectionIconOptions,
                volumeOptions: store.volumeIconOptions,
                bluetoothAudioOptions: store.bluetoothAudioIconOptions,
                isDarkBackground: isDarkBackground,
                showsChargingEffect: store.showsMenuBarChargingEffect,
                bottomIndicatorSource: store.bottomIndicatorSource,
                bottomIndicatorMetric: store.bottomIndicatorMetric,
                bottomIndicatorMetricColor: store.bottomIndicatorMetric.hardwareMetric.map { store.hardwareColor(for: $0) },
                bottomIndicatorStyle: store.effectiveBottomIndicatorStyle,
                leadingAccessory: { AnyView(instancePreview) }
            ) {
                PreviewAppearanceToggle(
                    isDarkBackground: $isDarkBackground,
                    localization: localization
                )
            }

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .onReceive(hardwareObservable.snapshotPublisher) { _ in
            hardwareRevision &+= 1
        }
    }

    @ViewBuilder
    private var instancePreview: some View {
        if let model {
            MenuBarInstancePreviewImage(
                model: model,
                isDarkBackground: isDarkBackground,
                localization: localization
            )
            .fixedSize()
            .padding(.trailing, -8)
        } else {
            Text(localization.string(.menuBarEditorAddOrSelect))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct MenuBarInstancePreviewImage: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let isDarkBackground: Bool
    let localization: Localization

    var body: some View {
        if let image = model.previewImage(dark: isDarkBackground) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: min(image.size.width, 110),
                    height: min(image.size.height, 18)
                )
                .fixedSize()
                .accessibilityLabel(localization.string(.menuBarEditorPreview))
        } else {
            Text(model.instance.name.isEmpty ? localization.string(.menuBarEditorUntitled) : model.instance.name)
                .font(.system(size: 11))
                .lineLimit(1)
        }
    }
}
