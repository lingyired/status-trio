import Foundation

enum BluetoothDeviceIdentity {
    private static let blePrefix = "ble:"

    static func bleRowID(_ id: UUID) -> String {
        "\(blePrefix)\(id.uuidString.lowercased())"
    }

    static func bleUUID(from rowID: String) -> UUID? {
        guard rowID.hasPrefix(blePrefix) else { return nil }
        return UUID(uuidString: String(rowID.dropFirst(blePrefix.count)))
    }

    static func preferenceKey(_ rowID: String) -> String {
        if let id = bleUUID(from: rowID) { return bleRowID(id) }
        if rowID.hasPrefix("mobile-") { return BluetoothBatteryReader.normalizedAddress(rowID) }
        return BluetoothBatteryReader.normalizedAddress(rowID)
    }

    /// A six-byte Bluetooth address, or `nil`.
    ///
    /// Only address-shaped text qualifies: hex digits optionally separated by
    /// the usual address separators. `normalizedAddress` is deliberately laxer
    /// (it keeps every hex digit so an arbitrary id can still be keyed), but that
    /// means it would turn `xyz02:00:…` into a valid-looking address. Identity
    /// and battery attribution must not do that.
    static func normalizedAddress(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separators: Set<Character> = [":", "-", " ", "."]
        guard trimmed.allSatisfy({ $0.isHexDigit || separators.contains($0) }) else { return nil }
        let compact = trimmed.filter(\.isHexDigit).uppercased()
        return compact.count == 12 ? compact : nil
    }
}
