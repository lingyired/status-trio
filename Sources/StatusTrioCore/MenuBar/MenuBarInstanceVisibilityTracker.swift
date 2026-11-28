import Foundation

enum MenuBarVisibilityDecision: Equatable {
    case none
    case userRemoved
}

/// Decides whether an `isVisible` change means the user dragged the item out.
///
/// `NSStatusItem.isVisible` is what the app wants, not what is on screen: macOS
/// can stop showing an item for lack of room without flipping it to false. So a
/// true→false transition only counts as a user removal when it is not one of our
/// own programmatic changes and the instance is currently enabled.
struct MenuBarInstanceVisibilityTracker {
    private var selfInitiated = false

    mutating func setSelfInitiated(_ active: Bool) {
        selfInitiated = active
    }

    func evaluate(previousVisible: Bool, newVisible: Bool, isEnabled: Bool) -> MenuBarVisibilityDecision {
        guard !selfInitiated, isEnabled, previousVisible, !newVisible else { return .none }
        return .userRemoved
    }
}
