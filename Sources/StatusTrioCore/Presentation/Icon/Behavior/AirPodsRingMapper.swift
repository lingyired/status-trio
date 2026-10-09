import Foundation

enum AirPodsRingBehavior: String, Codable, CaseIterable, Sendable {
    case single
    case dual
}

enum AirPodsRingMapper {
    static func resolve(
        snapshot: AirPodsBatteryIconSnapshot,
        behavior: AirPodsRingBehavior,
        now: Date = .now,
        isHeld: Bool = false
    ) -> OuterRingState? {
        guard isHeld || isFresh(snapshot, at: now), hasRenderableBattery(snapshot) else { return nil }

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

        let validLeft = valid(snapshot.left)
        let validRight = valid(snapshot.right)
        let value: Double?
        if behavior == .dual, let onlyKnownEar = validLeft ?? validRight,
           (validLeft == nil) != (validRight == nil) {
            value = Double(onlyKnownEar)
        } else if let main = valid(snapshot.main) {
            value = Double(main)
        } else if let left = validLeft, let right = validRight {
            value = Double(left + right) / 2
        } else if let left = validLeft {
            value = Double(left)
        } else if let right = validRight {
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

    static func isFresh(_ snapshot: AirPodsBatteryIconSnapshot, at now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.observedAt)
        return age >= 0 && age <= AirPodsBatteryIconSnapshot.freshnessInterval
    }

    static func hasRenderableBattery(_ snapshot: AirPodsBatteryIconSnapshot) -> Bool {
        valid(snapshot.main) != nil || valid(snapshot.left) != nil || valid(snapshot.right) != nil
    }

    private static func valid(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }
}
