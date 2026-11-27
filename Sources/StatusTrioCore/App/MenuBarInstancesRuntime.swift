import AppKit
import Combine

/// Bridges persisted menu-bar instances to real `NSStatusItem`s: creates/updates
/// items, renders their two lines from live snapshots, registers sampling demand
/// and routes clicks. The dashboard settings UI edits the same store this reads.
@MainActor
final class MenuBarInstancesRuntime: NSObject {
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let statusBarController: StatusBarController
    private let localization: Localization
    private let openSettings: () -> Void

    private var items: MenuBarInstancesController!
    private let provider: MenuBarMetricValueProvider
    private var cancellables = Set<AnyCancellable>()
    private var configuration = MenuBarInstancesConfiguration.empty
    private var latestHardware = HardwareMetricsSnapshot()
    private var latestStatus: StatusSnapshot = .placeholder
    private var trackedButtons = Set<ObjectIdentifier>()
    private var buttonByInstance: [UUID: NSStatusBarButton] = [:]
    private var hoverWorkItems: [UUID: DispatchWorkItem] = [:]
    private var hoverOpenID: UUID?

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        statusBarController: StatusBarController,
        localization: Localization,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.statusBarController = statusBarController
        self.localization = localization
        self.openSettings = openSettings
        self.provider = MenuBarMetricValueProvider(localize: { localization.string($0) })
        super.init()
    }

    func start() {
        items = MenuBarInstancesController(statusBar: SystemStatusBar(), onUserRemoved: { [weak self] id in
            self?.userRemoved(id)
        })
        latestHardware = store.hardwareMetrics.observable.snapshot
        latestStatus = store.snapshot

        settings.$menuBarInstances
            .removeDuplicates()
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)

        store.hardwareMetrics.observable.snapshotPublisher
            .sink { [weak self] hardware in
                self?.latestHardware = hardware
                self?.renderAll()
            }
            .store(in: &cancellables)

        store.$snapshot
            .sink { [weak self] status in
                self?.latestStatus = status
                self?.renderAll()
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    private func apply(_ config: MenuBarInstancesConfiguration) {
        configuration = config
        items.sync(config)
        for id in items.itemIDs {
            guard let button = items.item(for: id)?.button else { continue }
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
            buttonByInstance[id] = button
            installHoverTracking(button: button, id: id)
        }
        updateDemand(config)
        renderAll()
    }

    private func updateDemand(_ config: MenuBarInstancesConfiguration) {
        let merged = config.instances
            .filter { $0.isEnabled && $0.hasVisibleContent }
            .flatMap { $0.demandedMetrics }
            .compactMap { MenuBarMetricRegistry.hardwareMetricID(for: $0) }
        let ids = Set(merged)
        if ids.isEmpty {
            store.hardwareMetrics.end(.menuBarCenter)
        } else {
            store.hardwareMetrics.begin(.menuBarCenter, metrics: ids)
        }
    }

    // MARK: - Rendering

    private func renderAll() {
        guard items != nil else { return }
        let appearance = NSApp.effectiveAppearance
        for instance in configuration.instances where instance.hasVisibleContent && instance.isEnabled {
            guard items.item(for: instance.id) != nil else { continue }
            let readings = provider.readings(
                for: instance.allMetrics,
                hardware: latestHardware,
                status: latestStatus
            )
            let input = MenuBarRenderInput(instance: instance, readings: readings, colorOverrides: settings.hardwareMonitorMetricColors)
            let measurement = MenuBarInstanceRenderer.measure(input, appearance: appearance)
            let image = MenuBarInstanceRenderer.render(input, appearance: appearance, scale: 2)
            items.update(
                id: instance.id,
                renderState: MenuBarRenderState(image: image, width: CGFloat(measurement.totalWidth))
            )
        }
    }

    // MARK: - Clicks

    private func installHoverTracking(button: NSStatusBarButton, id: UUID) {
        let oid = ObjectIdentifier(button)
        guard !trackedButtons.contains(oid) else { return }
        trackedButtons.insert(oid)
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["id": id.uuidString]
        )
        button.addTrackingArea(area)
    }

    /// Hover-opens the configured panel (never external actions). The panel stays
    /// open until the user clicks elsewhere; exiting the item does not auto-close,
    /// so the pointer can travel into the panel.
    @objc func mouseEntered(with event: NSEvent) {
        guard let id = instanceID(from: event) else { return }
        hoverWorkItems[id]?.cancel()
        guard let instance = configuration.instances.first(where: { $0.id == id }),
              case .showPanel(let raw) = MenuBarInstanceActivationResolver.resolve(instance.hoverAction, forHover: true),
              let button = buttonByInstance[id] else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.statusBarController.isStatusPanelShown else { return }
            self.statusBarController.presentInstancePanel(routeRaw: raw, anchorButton: button, presentedByHover: true)
            self.hoverOpenID = id
        }
        hoverWorkItems[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc func mouseExited(with event: NSEvent) {
        guard let id = instanceID(from: event) else { return }
        hoverWorkItems[id]?.cancel()
        hoverWorkItems[id] = nil
        guard hoverOpenID == id else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoverOpenID == id else { return }
            self.statusBarController.dismissInstancePanel()
            self.hoverOpenID = nil
        }
        hoverWorkItems[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func instanceID(from event: NSEvent) -> UUID? {
        guard let raw = event.trackingArea?.userInfo?["id"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    func stop() {
        cancelableRemoveAll()
    }

    private func cancelableRemoveAll() {
        hoverWorkItems.values.forEach { $0.cancel() }
        hoverWorkItems.removeAll()
        trackedButtons.removeAll()
        buttonByInstance.removeAll()
        cancellables.removeAll()
        items?.removeAll()
        store.hardwareMetrics.end(.menuBarCenter)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString),
              let instance = configuration.instances.first(where: { $0.id == id }) else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showRightClickMenu(instance: instance, button: sender)
            return
        }
        switch MenuBarInstanceActivationResolver.resolve(instance.clickAction, forHover: false) {
        case .noop:
            break
        case .followMainIcon:
            statusBarController.togglePopover()
        case .showPanel(let raw):
            statusBarController.presentInstancePanel(routeRaw: raw, anchorButton: sender, presentedByHover: false)
        case .openAppSettings:
            openSettings()
        case .openActivityMonitor:
            openActivityMonitor()
        case .openSystemSettings(let pane):
            openSystemSettings(pane)
        }
    }

    private func showRightClickMenu(instance: MenuBarInstance, button: NSStatusBarButton) {
        let menu = NSMenu()

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            let versionItem = NSMenuItem(title: "Status Trio v\(version)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(
            title: localization.string(.menuBarEditorAppSettings),
            action: #selector(openAppSettingsFromMenu(_:)),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let disable = NSMenuItem(
            title: localization.string(.menuBarInstanceDisable),
            action: #selector(disableInstance(_:)),
            keyEquivalent: ""
        )
        disable.target = self
        disable.representedObject = instance.id.uuidString
        menu.addItem(disable)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openAppSettingsFromMenu(_ sender: NSMenuItem) {
        openSettings()
    }

    @objc private func disableInstance(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String, let id = UUID(uuidString: idString),
              var instance = settings.menuBarInstances.instances.first(where: { $0.id == id }) else { return }
        instance.isEnabled = false
        settings.updateMenuBarInstance(instance)
    }

    private func userRemoved(_ id: UUID) {
        guard var instance = settings.menuBarInstances.instances.first(where: { $0.id == id }) else { return }
        instance.isEnabled = false
        settings.updateMenuBarInstance(instance)
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openSystemSettings(_ pane: SystemSettingsPane) {
        let identifier: String
        switch pane {
        case .wifi: identifier = "x-apple.systempreferences:com.apple.wifi-settings-extension"
        case .bluetooth: identifier = "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension"
        case .battery: identifier = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        case .sound: identifier = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        case .network: identifier = "x-apple.systempreferences:com.apple.Network-Settings.extension"
        }
        if let url = URL(string: identifier) {
            NSWorkspace.shared.open(url)
        }
    }
}
