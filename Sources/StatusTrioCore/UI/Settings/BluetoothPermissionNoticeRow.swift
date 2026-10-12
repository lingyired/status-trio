import SwiftUI

enum BluetoothPermissionNoticeAction: Equatable {
    case requestAuthorization
    case openPermissionSettings

    init?(authorization: BluetoothAuthorizationStatus) {
        switch authorization {
        case .notDetermined:
            self = .requestAuthorization
        case .denied, .restricted:
            self = .openPermissionSettings
        case .allowed:
            return nil
        }
    }
}

/// A permission notice shared by Bluetooth settings and Bluetooth-backed icon sources.
struct BluetoothPermissionNoticeRow: View {
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        switch BluetoothPermissionNoticeAction(authorization: bluetoothDevices.authorization) {
        case .requestAuthorization:
            notice(
                description: .settingsBluetoothPermissionNotDeterminedDescription,
                button: .bluetoothActionRequestAuthorization,
                action: { statusStore.requestBluetoothAuthorization() }
            )
        case .openPermissionSettings:
            notice(
                description: .settingsBluetoothPermissionDeniedDescription,
                button: .bluetoothActionOpenPermissionSettings,
                action: { statusStore.openBluetoothPermissionSettings() }
            )
        case nil:
            EmptyView()
        }
    }

    private func notice(
        description: LocalizationKey,
        button: LocalizationKey,
        action: @escaping () -> Void
    ) -> some View {
        SettingsRow(
            "exclamationmark.triangle.fill",
            tint: .orange,
            title: localization.string(.settingsBluetoothPermissionRequired),
            subtitle: localization.string(description)
        ) {
            Button(localization.string(button), action: action)
                .controlSize(.small)
        }
    }
}
