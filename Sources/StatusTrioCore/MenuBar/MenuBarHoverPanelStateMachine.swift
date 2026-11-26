import Foundation

struct MenuBarHoverPanelState: Equatable {
    var isOpen = false
    var sourceInstanceID: UUID?
    var presentedByHover = false
    var generation = 0
}

enum MenuBarHoverEvent: Equatable {
    case hoverEnter(UUID)
    case hoverExit(UUID)
    case openConfirmed(UUID)
    case click(UUID)
    case closeAll
}

enum MenuBarHoverDecision: Equatable {
    case none
    case scheduleOpen(UUID, generation: Int)
    case scheduleClose(UUID, generation: Int)
    case present(UUID)
    case pin
    case close
}

/// Coordinates a single shared panel across every instance. A delayed close is
/// tagged with the generation it was scheduled under; when a newer open bumps the
/// generation, the old close becomes a no-op so it can never close the panel a
/// different instance just opened.
final class MenuBarHoverPanelStateMachine {
    private(set) var state = MenuBarHoverPanelState()

    func handle(_ event: MenuBarHoverEvent) -> MenuBarHoverDecision {
        switch event {
        case .hoverEnter(let id):
            state.generation += 1
            if state.isOpen && state.sourceInstanceID != id {
                state.isOpen = false
                state.sourceInstanceID = nil
                state.presentedByHover = false
            }
            return .scheduleOpen(id, generation: state.generation)

        case .openConfirmed(let id):
            state.isOpen = true
            state.sourceInstanceID = id
            state.presentedByHover = true
            return .present(id)

        case .hoverExit(let id):
            state.generation += 1
            return .scheduleClose(id, generation: state.generation)

        case .click(let id):
            guard state.isOpen, state.sourceInstanceID == id else { return .none }
            if state.presentedByHover {
                state.presentedByHover = false
                return .pin
            }
            return .close

        case .closeAll:
            state = MenuBarHoverPanelState()
            return .close
        }
    }

    /// Applies a delayed decision only if it was scheduled for the current
    /// generation; otherwise it has been superseded.
    func fire(generation: Int, _ decision: MenuBarHoverDecision) -> MenuBarHoverDecision {
        guard generation == state.generation else { return .none }
        switch decision {
        case .scheduleOpen(let id, _):
            state.isOpen = true
            state.sourceInstanceID = id
            state.presentedByHover = true
            return .present(id)
        case .scheduleClose:
            state.isOpen = false
            state.sourceInstanceID = nil
            state.presentedByHover = false
            return .close
        default:
            return decision
        }
    }
}
