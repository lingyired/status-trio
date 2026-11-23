import Foundation

/// The saved order and hidden set shared by the output and input device lists.
enum AudioDeviceOrder {
    /// Devices named in `order` come first, in that order. Every other device
    /// keeps its incoming position after them, so new devices appear at the end.
    static func ordered<Device>(
        _ devices: [Device],
        using order: [String],
        uid: (Device) -> String?
    ) -> [Device] {
        guard !order.isEmpty else { return devices }

        var ranks: [String: Int] = [:]
        for (index, key) in order.enumerated() where ranks[key] == nil {
            ranks[key] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = uid(lhs.element).flatMap { ranks[$0] } ?? Int.max
                let rightRank = uid(rhs.element).flatMap { ranks[$0] } ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// A device without a UID has no stable key to remember, so it can't be hidden.
    static func isHidden(uid: String?, in hiddenUIDs: Set<String>) -> Bool {
        guard let uid else { return false }
        return hiddenUIDs.contains(uid)
    }
}
