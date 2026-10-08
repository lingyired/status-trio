import Foundation

@MainActor
enum AccessibilityPresentation {
    static let statusItemLabel = "Status Trio"

    static func statusItemValue(
        _ snapshot: StatusSnapshot,
        localization: Localization
    ) -> String {
        let battery = snapshot.battery
        let batterySummary: String
        if battery.isPresent {
            let percentage = localization.format(.batteryAccessibilityValue, battery.percentage)
            let subtitle = PanelPresentationMapper.batterySubtitle(battery, localization: localization)
            if isOrdinaryBatteryState(battery) {
                batterySummary = percentage
            } else {
                batterySummary = localization.format(.commonParenthetical, percentage, subtitle)
            }
        } else {
            batterySummary = localization.string(.batteryStateNotPresent)
        }

        let networkSummary = snapshot.connection == .ethernet
            ? localization.string(.ethernetAccessibilityConnected)
            : wifiAccessibilitySummary(snapshot.wifi, localization: localization)
        let volumeSummary = localization.format(
            .accessibilityVolume,
            volumeValue(snapshot.volume, localization: localization)
        )

        return localization.format(.accessibilityStatus, batterySummary, networkSummary, volumeSummary)
    }

    private static func wifiAccessibilitySummary(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        let value = PanelPresentationMapper.wifiValue(wifi, localization: localization)
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return localization.format(.wifiAccessibilityWithSSID, ssid, value)
        }
        return localization.format(
            .commonLabelValue,
            localization.string(.wifiTitle),
            value
        )
    }

    private static func isOrdinaryBatteryState(_ battery: BatteryStatus) -> Bool {
        battery.isPresent
            && !battery.isCharged
            && !battery.isCharging
            && !battery.isLowPowerMode
            && !battery.isConnectedToPower
    }

    static func volumeValue(_ volume: VolumeStatus, localization: Localization) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else { return "—" }
        let clampedScalar = min(1, max(0, scalar))
        let percentage = Int((clampedScalar * 100).rounded())
        guard !volume.isMuted else { return localization.string(.volumeMuted) }
        let steps = StatusMappings.volumeSteps(scalar: clampedScalar, isMuted: false) ?? 0
        return localization.format(.volumeValue, percentage, steps)
    }
}
