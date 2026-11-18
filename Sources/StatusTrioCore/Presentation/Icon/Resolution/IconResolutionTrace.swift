import Foundation

enum SlotResolutionRole: String, Codable, Equatable, Sendable {
    case primary
    case fallback
    case none
}

enum IconResolutionOverride: String, Codable, Equatable, Sendable {
    case networkProblem
}

enum SlotResolutionReason: Equatable, Sendable {
    case primary
    case fallback(IconSourceUnavailableReason)
    case none
    case overridden(IconResolutionOverride)
}

struct SlotResolutionTrace: Equatable, Sendable {
    var selectedSourceID: String?
    var role: SlotResolutionRole
    var primaryFailure: IconSourceUnavailableReason?
    var reason: SlotResolutionReason

    static let empty = Self(selectedSourceID: nil, role: .none, primaryFailure: nil, reason: .none)
}

struct IconResolutionTrace: Equatable, Sendable {
    var outerRing: SlotResolutionTrace
    var center: SlotResolutionTrace
    var footer: SlotResolutionTrace

    static let empty = Self(outerRing: .empty, center: .empty, footer: .empty)
}

struct IconResolutionOutput: Equatable, Sendable {
    var scene: IconSceneState
    var trace: IconResolutionTrace
}
