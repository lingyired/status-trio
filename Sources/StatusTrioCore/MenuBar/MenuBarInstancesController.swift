import AppKit

/// Abstraction over a single status item so the controller can be unit-tested
/// without a live menu bar.
@MainActor
protocol MenuBarStatusItemHandle: AnyObject {
    var length: CGFloat { get set }
    var isVisible: Bool { get set }
    var autosaveName: String? { get set }
    var hasRemovalBehavior: Bool { get set }
    var image: NSImage? { get set }
    var button: NSStatusBarButton? { get }
    var onVisibilityChange: ((Bool) -> Void)? { get set }
}

@MainActor
protocol MenuBarStatusBarProviding {
    func makeItem() -> MenuBarStatusItemHandle
}

struct MenuBarRenderState {
    var image: NSImage?
    var width: CGFloat
}

/// Owns one `NSStatusItem` per enabled instance. Creation and visibility are
/// separate concerns: disabling only hides (keeps the slot / position), while
/// deleting removes the item. A user drag-out is detected via the visibility
/// tracker and reported once.
@MainActor
final class MenuBarInstancesController {
    private let statusBar: MenuBarStatusBarProviding
    private let onUserRemoved: (UUID) -> Void
    private var items: [UUID: MenuBarStatusItemHandle] = [:]
    private var lastVisible: [UUID: Bool] = [:]
    private var enabled: [UUID: Bool] = [:]
    private var tracker = MenuBarInstanceVisibilityTracker()

    init(statusBar: MenuBarStatusBarProviding, onUserRemoved: @escaping (UUID) -> Void) {
        self.statusBar = statusBar
        self.onUserRemoved = onUserRemoved
    }

    var itemIDs: [UUID] { Array(items.keys) }

    func item(for id: UUID) -> MenuBarStatusItemHandle? { items[id] }

    func sync(_ configuration: MenuBarInstancesConfiguration) {
        let displayable = configuration.instances.filter { $0.hasVisibleContent }
        let keep = Set(displayable.map(\.id))
        for id in items.keys where !keep.contains(id) {
            items[id] = nil
            lastVisible[id] = nil
            enabled[id] = nil
        }
        for instance in displayable {
            let handle: MenuBarStatusItemHandle
            if let existing = items[instance.id] {
                handle = existing
            } else {
                let created = statusBar.makeItem()
                created.autosaveName = "statusTrio.menuBarInstance.\(instance.id.uuidString)"
                created.hasRemovalBehavior = true
                items[instance.id] = created
                handle = created
            }
            enabled[instance.id] = instance.isEnabled
            handle.onVisibilityChange = { [weak self] newVisible in
                self?.notifyExternalVisibilityChange(id: instance.id, newVisible: newVisible)
            }
            setVisible(handle, instance.isEnabled, id: instance.id)
        }
    }

    func update(id: UUID, renderState: MenuBarRenderState) {
        guard let handle = items[id] else { return }
        handle.length = renderState.width
        if let image = renderState.image {
            handle.image = image
        }
    }

    /// Test/integration hook: feed a KVO-reported visibility change.
    func notifyExternalVisibilityChange(id: UUID, newVisible: Bool) {
        guard items[id] != nil else { return }
        let previous = lastVisible[id] ?? true
        let decision = tracker.evaluate(
            previousVisible: previous,
            newVisible: newVisible,
            isEnabled: enabled[id] ?? true
        )
        lastVisible[id] = newVisible
        if decision == .userRemoved {
            onUserRemoved(id)
        }
    }

    func removeAll() {
        for (id, handle) in items {
            tracker.setSelfInitiated(true)
            handle.isVisible = false
            tracker.setSelfInitiated(false)
            _ = id
        }
        items.removeAll()
        lastVisible.removeAll()
        enabled.removeAll()
    }

    private func setVisible(_ handle: MenuBarStatusItemHandle, _ visible: Bool, id: UUID) {
        tracker.setSelfInitiated(true)
        handle.isVisible = visible
        tracker.setSelfInitiated(false)
        lastVisible[id] = visible
    }
}

/// Live implementation backed by `NSStatusBar`.
@MainActor
final class SystemStatusItemHandle: MenuBarStatusItemHandle {
    private let statusItem: NSStatusItem

    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    var length: CGFloat {
        get { statusItem.length }
        set { statusItem.length = newValue }
    }

    var isVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }

    var autosaveName: String? {
        get { statusItem.autosaveName }
        set { statusItem.autosaveName = newValue }
    }

    var hasRemovalBehavior: Bool {
        get { statusItem.behavior.contains(.removalAllowed) }
        set { statusItem.behavior = newValue ? [.removalAllowed] : [] }
    }

    var image: NSImage? {
        get { statusItem.button?.image }
        set { statusItem.button?.image = newValue }
    }

    var button: NSStatusBarButton? { statusItem.button }

    private var visibilityObservation: NSKeyValueObservation?
    var onVisibilityChange: ((Bool) -> Void)? {
        didSet {
            guard onVisibilityChange != nil else { visibilityObservation = nil; return }
            visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                guard let newValue = change.newValue else { return }
                Task { @MainActor in self?.onVisibilityChange?(newValue) }
            }
        }
    }
}

@MainActor
struct SystemStatusBar: MenuBarStatusBarProviding {
    func makeItem() -> MenuBarStatusItemHandle { SystemStatusItemHandle() }
}
