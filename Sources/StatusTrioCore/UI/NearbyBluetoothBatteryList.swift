import SwiftUI

/// Read-only readings from nearby peripherals that expose the standard BLE
/// Battery Service. These UUID-based devices remain separate from the paired
/// device list, which has a different identity source.
struct NearbyBluetoothBatteryList: View {
    @EnvironmentObject private var localization: Localization
    let rows: [PanelBluetoothDeviceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string(.bluetoothNearbyBatteryTitle))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            NearbyBluetoothBatteryRows(rows: rows)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
