import Foundation

/// Coordinates the app-owned windows that can display Dock-icon previews.
///
/// The preview cache is separate from the live icon decode cache and animation
/// frame ownership. It may be cleared only after no preview window is visible
/// and the status popover no longer owns its content.
@MainActor
final class PreviewResourceLifecycle {
    enum Owner: Hashable {
        case settings
        case onboarding
    }

    private let previewCache: DockIconPreviewCache
    private var visibleOwners: Set<Owner> = []
    private var popoverContentOwned = false
    private var isStarted = false

    init(previewCache: DockIconPreviewCache = .shared) {
        self.previewCache = previewCache
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        visibleOwners.removeAll()
        popoverContentOwned = false
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        visibleOwners.removeAll()
        popoverContentOwned = false
    }

    func setPreviewOwner(_ owner: Owner, visible: Bool) {
        guard isStarted else { return }
        if visible {
            guard visibleOwners.insert(owner).inserted else { return }
        } else {
            guard visibleOwners.remove(owner) != nil else { return }
        }
        releaseIfIdle()
    }

    func setPopoverContentOwned(_ owned: Bool) {
        guard isStarted, popoverContentOwned != owned else { return }
        popoverContentOwned = owned
        releaseIfIdle()
    }

    func releaseIfIdle() {
        guard isStarted, visibleOwners.isEmpty, !popoverContentOwned else { return }
        previewCache.reset()
    }
}
