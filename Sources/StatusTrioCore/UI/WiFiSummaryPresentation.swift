import Foundation

@MainActor
enum WiFiSummaryPresentation {
    static func summarySSID(_ wifi: WiFiStatus, connection: NetworkConnection) -> String? {
        guard connection == .wifi,
              wifi.state == .connected || wifi.state == .hotspot,
              let ssid = wifi.ssid, !ssid.isEmpty else { return nil }
        return ssid
    }

    static func measurements(
        _ wifi: WiFiStatus,
        connection: NetworkConnection,
        localization: Localization
    ) -> String? {
        // Link measurements do not require a network name. Keep the primary
        // Wi-Fi path gate so stale radio readings cannot describe another path.
        guard connection == .wifi,
              wifi.state == .connected || wifi.state == .hotspot else { return nil }
        let band = wifi.band.map {
            localization.format(.wifiSummaryBand, $0.gigahertz.formatted(
                .number.locale(Locale(identifier: localization.resolvedLanguage.rawValue))
            ))
        }
        let signal = wifi.rssi.flatMap { rssi in
            rssi < 0 ? localization.format(.wifiSummarySignal, rssi) : nil
        }
        if let band, let signal {
            return localization.format(.wifiSummaryBandAndSignal, band, signal)
        }
        return band ?? signal
    }
}
