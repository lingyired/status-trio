import Foundation

struct IconSourceSnapshot: Equatable, Sendable {
    var availability: [String: IconSourceAvailability]

    static let empty = Self(availability: [:])

    func result<Value: Equatable & Sendable>(for sourceID: String, default value: SourceResult<Value>) -> SourceResult<Value> {
        switch availability[sourceID] {
        case .available, nil: value
        case let .unavailable(reason): .unavailable(reason)
        }
    }
}
