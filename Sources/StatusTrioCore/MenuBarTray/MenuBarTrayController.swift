import AppKit
import Combine

/// Collects the user's menu bar items into the status panel's tray box and
/// forwards clicks to them, without adding any spacer or extra item to the
/// system menu bar (leaving macOS's native menu bar behaviour untouched).
@MainActor
final class MenuBarTrayController: ObservableObject {
    static let shared = MenuBarTrayController()

    @Published private(set) var phase: MenuBarTrayPhase = .inactive
    @Published private(set) var items: [MenuBarTrayItem] = []
    @Published private(set) var permissions = MenuBarTrayPermissions(screenRecording: true, accessibility: false)

    /// Status Trio's own menu bar item window, supplied by `StatusBarController`.
    var ownStatusItemWindow: (() -> NSWindow?)?

    private static let knownBundleIDsDefaultsKey = "menuBarTray.knownBundleIDs"

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var windowOwners: [CGWindowID: MenuBarItemOwner] = [:]
    private var knownBundleIDs: Set<String>
    private var refreshTask: Task<Void, Never>?
    private var isActive = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.knownBundleIDsDefaultsKey) ?? []
        self.knownBundleIDs = MenuBarItemScanner.defaultKnownMenuBarBundleIDs.union(stored)
    }

    // MARK: - Lifecycle

    func start(
        settings: SettingsStore,
        popoverVisible: AnyPublisher<Bool, Never>,
        localization: Localization
    ) {
        guard cancellables.isEmpty else { return }
        _ = localization
        settings.$enabledPopupSections
            .map { $0.contains(.menuBarTray) }
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.activate()
                } else {
                    self?.deactivate()
                }
            }
            .store(in: &cancellables)
        popoverVisible
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        deactivate()
    }

    func trimForMemoryPressure() {
        if !isActive {
            windowOwners.removeAll()
        }
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        phase = .collapsed
        refreshPermissions()
        refresh()
    }

    private func deactivate() {
        isActive = false
        refreshTask?.cancel()
        items = []
        phase = .inactive
    }

    // MARK: - Discovery & Interaction

    func refresh() {
        guard isActive else { return }
        refreshPermissions()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let allWindows = MenuBarItemScanner.liveWindows()
            let fallbackOwners = MenuBarItemScanner.fallbackMenuBarOwners(
                in: allWindows,
                knownBundleIDs: self.knownBundleIDs
            )
            if self.items.isEmpty, !fallbackOwners.isEmpty {
                self.publish(owners: fallbackOwners)
            }

            var resolvedOwners = fallbackOwners
            if self.permissions.accessibility {
                let candidates = MenuBarAccessibility.candidates()
                let axOwners = await Task.detached(priority: .userInitiated) {
                    MenuBarAccessibility.resolveOwners(candidates)
                }.value
                guard !Task.isCancelled else { return }

                // Persist every bundle ID observed in AXExtrasMenuBar so it
                // stays in the tray even when macOS 27's `«` overflow collapses
                // and detaches overflowed items from AXExtrasMenuBar.
                self.recordObservedBundleIDs(from: axOwners)

                let orderedAX = MenuBarItemScanner.hiddenAXOwners(
                    axOwners,
                    separatorFrame: nil,
                    ownFrame: nil
                )
                if !orderedAX.isEmpty {
                    let updatedFallback = MenuBarItemScanner.fallbackMenuBarOwners(
                        in: allWindows,
                        knownBundleIDs: self.knownBundleIDs
                    )
                    let coveredPIDs = Set(orderedAX.map(\.pid))
                    let collapsedExtras = updatedFallback.filter { !coveredPIDs.contains($0.pid) }
                    resolvedOwners = orderedAX + collapsedExtras
                }
            }

            self.publish(owners: resolvedOwners)
        }
    }

    /// Opens an item's menu or app window when clicked in the tray.
    func open(_ item: MenuBarTrayItem, click: MenuBarTrayClick, dismissPanel: () -> Void) {
        refreshPermissions()
        guard permissions.accessibility else {
            requestAccessibility()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        dismissPanel()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard self != nil else { return }

            var targetFrame = item.owner.flatMap { MenuBarAccessibility.liveFrame(for: $0) } ?? item.frame

            // If the item is currently folded inside macOS 27's native `«`
            // overflow (detached from AXExtrasMenuBar or off-screen), expand
            // the native `«` indicator first so the item materializes on the bar.
            if !Self.isVisibleInMenuBar(targetFrame) {
                if MenuBarAccessibility.expandSystemOverflowIfNeeded() {
                    try? await Task.sleep(for: .milliseconds(180))
                    if let owner = item.owner {
                        // Also refresh all items now that `«` is expanded.
                        let candidates = MenuBarAccessibility.candidates()
                        let axOwners = await Task.detached(priority: .userInitiated) {
                            MenuBarAccessibility.resolveOwners(candidates)
                        }.value
                        self?.recordObservedBundleIDs(from: axOwners)
                        if let fresh = MenuBarAccessibility.liveFrame(for: owner) {
                            targetFrame = fresh
                        }
                    }
                }
            }

            var handled = false
            // 1. When the icon is visible on the menu bar, post a real left/right
            //    mouse click at its menu bar coordinates.
            if Self.isVisibleInMenuBar(targetFrame) {
                MenuBarClickPoster.post(click, at: CGPoint(x: targetFrame.midX, y: targetFrame.midY))
                handled = true
            }

            // 2. Otherwise trigger its `AXExtrasMenuBar` action (`AXShowMenu` / `AXPress`).
            if !handled, let owner = item.owner {
                handled = MenuBarAccessibility.performAction(owner: owner, click: click)
            }

            // 3. Fallback for apps whose status item is still unreachable.
            if !handled, let owner = item.owner {
                Self.activateOrReopenApplication(owner: owner)
            }
        }
    }

    func requestAccessibility() {
        MenuBarAccessibility.requestTrust()
    }

    // MARK: - Helpers

    private func recordObservedBundleIDs(from owners: [MenuBarItemOwner]) {
        var added = false
        for owner in owners {
            if let bundleID = owner.bundleIdentifier, !bundleID.isEmpty {
                if knownBundleIDs.insert(bundleID).inserted {
                    added = true
                }
            }
        }
        if added {
            defaults.set(Array(knownBundleIDs).sorted(), forKey: Self.knownBundleIDsDefaultsKey)
        }
    }

    private func publish(owners: [MenuBarItemOwner]) {
        let next = owners.map { owner in
            let id = owner.syntheticID
            windowOwners[id] = owner
            return MenuBarTrayItem(
                windowID: id,
                frame: owner.frame,
                owner: owner,
                snapshot: nil
            )
        }
        if next != items {
            items = next
        }
    }

    private func refreshPermissions() {
        let next = MenuBarTrayPermissions(
            screenRecording: true,
            accessibility: MenuBarAccessibility.isTrusted()
        )
        if next != permissions {
            permissions = next
        }
    }

    private static func isVisibleInMenuBar(_ frame: CGRect) -> Bool {
        guard frame.width > 2, frame.height > 2,
              frame.minY >= 0, frame.maxY <= 55 else { return false }
        for screen in NSScreen.screens {
            let bounds = MenuBarSeparatorController.globalFrame(ofAppKitFrame: screen.frame)
            guard frame.maxX <= bounds.maxX + 1 else { continue }
            if let topRight = screen.auxiliaryTopRightArea {
                if frame.minX >= topRight.minX + 36 {
                    return true
                }
            } else if frame.minX >= bounds.minX + 40 {
                return true
            }
        }
        return false
    }

    private static func activateOrReopenApplication(owner: MenuBarItemOwner) {
        if let app = NSRunningApplication(processIdentifier: owner.pid) {
            app.unhide()
            app.activate(options: [.activateAllWindows])
            if let url = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
            }
        }
    }
}
