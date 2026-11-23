import Foundation

/// Store-side stand-in for the Direct-only private `IOBluetoothRadioPowerBackend`.
/// The App Store build does not write Bluetooth radio power, so it reports
/// unavailable and refuses writes.
@MainActor
final class IOBluetoothRadioPowerBackend: BluetoothRadioPowerBacking {
    var isAvailable: Bool { false }
    func readPower() -> BluetoothRadioPower { .unavailable }
    func setPower(_ enabled: Bool) async -> Bool { false }
}
