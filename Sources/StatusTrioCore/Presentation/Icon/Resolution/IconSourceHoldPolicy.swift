import Foundation

struct IconSourceHoldPolicy<Value: Equatable & Sendable> {
    let holdDuration: TimeInterval
    private(set) var sourceID: String?
    private var lastAvailableValue: Value?
    private var lastAvailableAt: Date?
    private(set) var isHolding = false

    init(holdDuration: TimeInterval = 2) {
        self.holdDuration = holdDuration.isFinite ? max(0, holdDuration) : 2
        sourceID = nil
        lastAvailableValue = nil
        lastAvailableAt = nil
        isHolding = false
    }

    var expirationDate: Date? {
        guard isHolding, lastAvailableValue != nil, let lastAvailableAt else { return nil }
        return lastAvailableAt.addingTimeInterval(holdDuration)
    }

    mutating func update(
        _ result: SourceResult<Value>,
        sourceID newSourceID: String,
        at now: Date
    ) -> SourceResult<Value> {
        if sourceID != newSourceID {
            clearLastGood()
            sourceID = newSourceID
        }

        switch result {
        case let .available(value):
            lastAvailableValue = value
            lastAvailableAt = now
            isHolding = false
            return .available(value)
        case let .unavailable(reason):
            switch reason {
            case .unknown, .temporarilyStale:
                guard let lastAvailableValue, let lastAvailableAt else {
                    return .unavailable(reason)
                }
                let expiry = lastAvailableAt.addingTimeInterval(holdDuration)
                guard now < expiry else {
                    clearLastGood()
                    return .unavailable(.temporarilyStale)
                }
                isHolding = true
                return .available(lastAvailableValue)
            case .disconnected, .permissionDenied, .unavailable:
                clearLastGood()
                return .unavailable(reason)
            }
        }
    }

    mutating func reset() {
        clearLastGood()
        sourceID = nil
    }

    private mutating func clearLastGood() {
        lastAvailableValue = nil
        lastAvailableAt = nil
        isHolding = false
    }
}
