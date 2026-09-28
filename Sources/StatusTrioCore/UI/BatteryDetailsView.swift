import SwiftUI

/// The battery page, reached from the popover's battery summary row. It owns
/// the on-demand collector: collection runs only while this page is on screen.
struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var controller: BatteryDetailsController
    let battery: BatteryStatus
    let actionLabel: String?
    let onBack: () -> Void
    let onOpenBatterySettings: () -> Void

    init(
        controller: BatteryDetailsController,
        battery: BatteryStatus,
        actionLabel: String? = nil,
        onBack: @escaping () -> Void,
        onOpenBatterySettings: @escaping () -> Void
    ) {
        self.controller = controller
        self.battery = battery
        self.actionLabel = actionLabel
        self.onBack = onBack
        self.onOpenBatterySettings = onOpenBatterySettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: StatusPresentation.batteryTitle(battery, localization: localization),
                action: onBack
            )

            fields
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            Button(action: onOpenBatterySettings) {
                Text(settingsActionLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                .buttonStyle(.plain)
                .accessibilityLabel(settingsActionLabel)
        }
        .task(id: BatteryPowerState(battery)) {
            controller.activate(state: BatteryPowerState(battery))
        }
        // A panel can also disappear because the popover closed; the store
        // deactivates collection there too, so this is the in-popover path.
        .onDisappear { controller.deactivate() }
    }

    var settingsActionLabel: String {
        actionLabel ?? localization.string(.batteryActionOpenSettings)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let details = controller.details {
                let reading = BatteryPowerPresentation(details: details, isConnectedToPower: battery.isConnectedToPower)
                row(reading.title, reading.watts.map {
                    $0.formatted(.number.precision(.fractionLength(1)).locale(localization.resolvedLanguage.locale)) + " W"
                } ?? localization.string(reading.unavailableTitle))
                if let timestamp = reading.timestamp {
                    row(reading.timestampTitle, timestamp.formatted(.dateTime.hour().minute().second().locale(localization.resolvedLanguage.locale)))
                }
                if let charging = reading.chargingWatts {
                    // The primary row describes the whole system on external power,
                    // so the battery's own charge power keeps its own green row.
                    row(.batteryDetailsCharging,
                        charging.formatted(.number.precision(.fractionLength(1)).locale(localization.resolvedLanguage.locale)) + " W",
                        tint: .green)
                }
                if let power = details.power {
                    row(.batteryDetailsVoltage, power.volts.formatted(.number.precision(.fractionLength(2)).locale(localization.resolvedLanguage.locale)) + " V")
                    row(.batteryDetailsCurrent, power.amps.formatted(.number.precision(.fractionLength(2)).locale(localization.resolvedLanguage.locale)) + " A")
                }
                if let watts = details.adapterWatts {
                    row(.batteryDetailsAdapter, watts.formatted(.number.locale(localization.resolvedLanguage.locale)) + " W")
                }
                if !battery.isConnectedToPower {
                    row(.batteryDetailsRemaining, details.remainingMinutes.map {
                        Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(localization.resolvedLanguage.locale))
                    } ?? localization.string(.batteryDetailsUnavailable))
                }
                if let count = details.cycleCount {
                    row(.batteryDetailsCycles, count.formatted(.number.locale(localization.resolvedLanguage.locale)))
                }
            } else {
                Text(localization.string(.batteryDetailsLoading)).foregroundStyle(.secondary)
            }
            row(.batteryDetailsLowPower, localization.string(battery.isLowPowerMode ? .batteryDetailsOn : .batteryDetailsOff))
            Text(localization.string(.batteryDetailsExplanation))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func row(_ key: LocalizationKey, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(localization.string(key)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(tint ?? .primary)
        }
        .accessibilityElement(children: .combine)
    }
}
