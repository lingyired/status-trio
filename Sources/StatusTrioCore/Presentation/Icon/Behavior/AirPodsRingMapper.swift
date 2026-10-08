import Foundation

enum AirPodsRingBehavior: String, Codable, CaseIterable, Sendable {
    case single
    case dual
}

enum AirPodsRingMapper {
    static func resolve(
        snapshot: AirPodsBatteryIconSnapshot,
        behavior: AirPodsRingBehavior,
        now: Date = .now
    ) -> OuterRingState? {
        let age = now.timeIntervalSince(snapshot.observedAt)
        guard age >= 0, age <= AirPodsBatteryIconSnapshot.freshnessInterval else { return nil }

        if behavior == .dual, let left = valid(snapshot.left), let right = valid(snapshot.right) {
            return OuterRingState(
                segments: [
                    RingSegmentState(progress: Double(left) / 100, color: .bluetooth, position: .left),
                    RingSegmentState(progress: Double(right) / 100, color: .primary, position: .right)
                ],
                gap: .closed,
                layout: .leftRight
            )
        }

        let value: Double?
        if let main = valid(snapshot.main) {
            value = Double(main)
        } else if let left = valid(snapshot.left), let right = valid(snapshot.right) {
            value = Double(left + right) / 2
        } else if let left = valid(snapshot.left) {
            value = Double(left)
        } else if let right = valid(snapshot.right) {
            value = Double(right)
        } else {
            value = nil
        }
        guard let value else { return nil }
        return OuterRingState(
            segments: [RingSegmentState(progress: value / 100, color: .primary)],
            gap: .closed,
            isPartial: behavior == .dual && ((valid(snapshot.left) == nil) != (valid(snapshot.right) == nil))
        )
    }

    private static func valid(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }
}
