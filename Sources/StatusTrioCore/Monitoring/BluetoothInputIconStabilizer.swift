import Foundation

/// Keeps a device's generic-input glyph from flickering.
///
/// A composite device is classified as `genericInput` only while both its mouse
/// and keyboard interfaces are enumerated. Those interfaces can drop out of the
/// Registry for a read — a Bluetooth HID device re-enumerates on reconnect — and
/// a later read that happens to see only one of them would flip the row back to
/// a definite mouse or keyboard glyph. This holds the generic classification
/// once it has been seen, so the row reads the same across reads.
///
/// Keyed by `BluetoothBatteryReader.normalizedAddress`, the one normalization
/// the app joins devices by. In memory only: an app restart starts fresh, which
/// is a deliberate first-phase bound, not a promise of cross-launch stability.
@MainActor
struct BluetoothInputIconStabilizer {
    /// Addresses whose generic classification is sticky. Pruned to the devices
    /// currently present on every call, so an unpaired or removed device drops
    /// its entry and cannot leak into a later device that reuses the address.
    private var stickyGenericAddresses: Set<String> = []

    /// Finalizes the display classification for one published device list: any
    /// `genericInput` becomes sticky, a sticky address is held at `genericInput`
    /// even when this read saw only one capability, and addresses no longer
    /// present are dropped.
    mutating func stabilize(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        let present = Set(
            devices.map { BluetoothBatteryReader.normalizedAddress($0.id) }.filter { !$0.isEmpty }
        )
        stickyGenericAddresses.formIntersection(present)

        return devices.map { device in
            let key = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !key.isEmpty else { return device }

            if device.inputIconClassification == .genericInput {
                stickyGenericAddresses.insert(key)
                return device
            }
            if stickyGenericAddresses.contains(key) {
                return device.replacingInputIconClassification(with: .genericInput)
            }
            return device
        }
    }
}