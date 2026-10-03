import SwiftUI

enum MobileBatteryDeviceRowPresentation {
    static func displayName(_ snapshot: MobileBatterySnapshot, fallbackWatchName: String) -> String {
        let name = snapshot.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return BluetoothMobileDeviceModel.kind(forModel: snapshot.model) == .mobile(.watch)
                ? fallbackWatchName
                : "iPhone"
        }
        return name
    }

    static func sourceText(_ snapshot: MobileBatterySnapshot, viaIPhone: String) -> String? {
        BluetoothMobileDeviceModel.kind(forModel: snapshot.model) == .mobile(.watch)
            ? viaIPhone
            : nil
    }

    static func chargingText(_ snapshot: MobileBatterySnapshot, charging: String) -> String? {
        snapshot.isCharging == true ? charging : nil
    }
}

/// The observation detail drawn under a row backed by the trusted-phone helper.
/// Watch names and charging state are absent from the helper response today, so
/// the row uses the localized fallback and only reports charging when observed.
struct MobileBatteryDeviceRows: View {
    @EnvironmentObject private var localization: Localization
    let snapshot: MobileBatterySnapshot

    var body: some View {
        Text(detailText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var detailText: String {
        let time = snapshot.observedAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(localization.resolvedLanguage.locale)
        )
        let parts = [
            MobileBatteryDeviceRowPresentation.sourceText(
                snapshot,
                viaIPhone: localization.string(.mobileBatteryWatchSource)
            ),
            localization.format(.mobileBatteryUpdatedAt, time),
            MobileBatteryDeviceRowPresentation.chargingText(
                snapshot,
                charging: localization.string(.mobileBatteryCharging)
            )
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }
}
