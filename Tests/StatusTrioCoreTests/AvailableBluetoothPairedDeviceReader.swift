import Foundation
@testable import StatusTrioCore

/// Lets controller tests exercise an available Bluetooth state without
/// depending on the Store-safe unavailable default or a system subprocess.
final class AvailableBluetoothPairedDeviceReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([]))
    }
}
