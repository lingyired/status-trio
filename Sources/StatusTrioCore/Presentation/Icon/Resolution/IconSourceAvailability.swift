import Foundation

enum IconSourceUnavailableReason: String, Codable, Equatable, Hashable, Sendable {
    case disconnected
    case permissionDenied
    case unavailable
    case stale
}

enum SourceResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case available(Value)
    case unavailable(IconSourceUnavailableReason)
}

enum IconSourceAvailability: Equatable, Sendable {
    case available
    case unavailable(IconSourceUnavailableReason)
}
