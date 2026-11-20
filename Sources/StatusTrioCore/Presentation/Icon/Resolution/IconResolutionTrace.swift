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
    /// The exact plugin binding the slot resolved to. The runtime uses it for
    /// live-source demand; it is intentionally not reconstructed from the legacy
    /// source ID because two bindings can draw identical pixels.
    var binding: IconContentBinding? = nil

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
    /// The dependencies of the slots that actually resolved. The runtime uses
    /// this rather than re-deriving demand from the configured composition, so a
    /// source selected through an external binding is not lost.
    var dependencies: IconContentDependencies = .init()
    /// Bindings selected for the scene and bindings that must stay subscribed.
    var demand: IconPresentationDemand = .none
}
