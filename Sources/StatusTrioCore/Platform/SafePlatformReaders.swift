import Foundation

/// Store-safe Bluetooth readers. They fail closed instead of silently spawning
/// a process the App Store target does not ship as a dependency.
final class UnavailableBluetoothPairedDeviceReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.unavailable)
    }
}

final class UnavailableBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion(nil)
    }
}

/// Preserves CoreWLAN-based list scanning while omitting the optional
/// `networksetup` preferred-network enrichment.
struct UnavailableWiFiKnownNetworkProvider: WiFiKnownNetworkProviding {
    func preferredNetworkSSIDs(interface: String) -> Set<String> {
        []
    }
}
