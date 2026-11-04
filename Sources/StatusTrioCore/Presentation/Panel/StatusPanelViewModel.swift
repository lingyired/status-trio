import Combine
import Foundation

@MainActor
protocol PanelPresentationUpdateScheduling: AnyObject {
    func schedule(_ update: @escaping @MainActor () -> Void)
}

@MainActor
private final class YieldingPanelPresentationUpdateScheduler: PanelPresentationUpdateScheduling {
    func schedule(_ update: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            update()
        }
    }
}

@MainActor
final class StatusPanelViewModel: ObservableObject {
    private struct RefreshRegions: OptionSet {
        let rawValue: UInt8
        static let batteryDetails = Self(rawValue: 1 << 0)
        static let wifiDetails = Self(rawValue: 1 << 1)
        static let wiredDetailsAndNetwork = Self(rawValue: 1 << 2)
        static let bluetooth = Self(rawValue: 1 << 3)
        static let all = Self(rawValue: 1 << 4)
        static let volume = Self(rawValue: 1 << 5)
        static let localIP = Self(rawValue: 1 << 6)
        static let audioInput = Self(rawValue: 1 << 7)
        static let inputSource = Self(rawValue: 1 << 8)
        static let vpn = Self(rawValue: 1 << 9)
    }

    private struct SourceDemand: OptionSet {
        let rawValue: UInt8
        static let bluetooth = Self(rawValue: 1 << 0)
        static let volume = Self(rawValue: 1 << 1)
        static let audioInput = Self(rawValue: 1 << 2)
        static let inputSource = Self(rawValue: 1 << 3)
        static let vpn = Self(rawValue: 1 << 4)
        static let localIP = Self(rawValue: 1 << 5)
    }
    @Published private(set) var battery: PanelSummaryState
    @Published private(set) var network: PanelSummaryState
    @Published private(set) var vpn: PanelSummaryState
    @Published private(set) var bluetooth: BluetoothPanelState
    /// Restarts discovery when connected audio membership changes. This is
    /// independent of the volume presentation because Bluetooth-only visibility
    /// also owns HUAWEI and AirPods listening-mode discovery.
    @Published private(set) var listeningModeTaskID = ""
    /// The volume row observes this model directly, so a volume tick
    /// invalidates only that row instead of the whole panel (#263). The view
    /// model stays the only writer and keeps the reference non-published.
    let volumeControl: VolumeControlModel

    /// Read-only passthrough for `StatusBarController`'s scroll handling and
    /// for tests. It is deliberately not `@Published`: publishing it here would
    /// re-create the full-panel invalidation this model exists to avoid.
    var volume: VolumePanelState { volumeControl.volume }
    @Published private(set) var brightness: BrightnessPanelState
    @Published private(set) var audioInput: AudioInputPanelState
    @Published private(set) var inputSource: InputSourcePanelState
    @Published private(set) var batteryDetails: PanelDetailState
    @Published private(set) var wifiDetails: WiFiPanelState
    @Published private(set) var wiredDetails: PanelDetailState
    @Published private(set) var chargeToFullNowPresentation: ChargeToFullNowPresentation = .hidden
    /// The battery summary card keeps honoring the Settings toggle: the row only
    /// appears there when the user has enabled it. The battery details page uses
    /// the ungated `chargeToFullNowPresentation` above.
    @Published private(set) var summaryChargeToFullNowPresentation: ChargeToFullNowPresentation = .hidden
    @Published private(set) var visiblePopupSections: [PopupSection]
    @Published private(set) var route: StatusPanelRoute = .summary
    @Published private(set) var wifiDisclosure = WiFiPanelDisclosureState()

    /// The summary sections actually rendered. The brightness section is
    /// dropped when every display is hidden, so a fully hidden list leaves no
    /// empty section or dangling separator behind (#241).
    var displayedSummarySections: [PopupSection] {
        Self.displayedSummarySections(
            visible: visiblePopupSections,
            brightnessIsEmpty: brightness.isEmpty
        )
    }

    /// Pure section filter behind `displayedSummarySections`. Kept static so
    /// the "all displays hidden drops the section" rule is unit-testable
    /// without standing up a live panel.
    nonisolated static func displayedSummarySections(
        visible: [PopupSection],
        brightnessIsEmpty: Bool
    ) -> [PopupSection] {
        guard brightnessIsEmpty else { return visible }
        return visible.filter { $0 != .brightness }
    }

    let store: SystemStatusStore
    let settings: SettingsStore
    /// Persisted per-list layout, shared with the views so a reopened panel can
    /// reserve last time's height while the lists re-read their rows.
    let layoutSnapshots: PanelListLayoutSnapshotStore
    private let localization: Localization
    private let inputSourceController: InputSourceController
    private let chargeToFullNow: ChargeToFullNowController?
    private let updateScheduler: any PanelPresentationUpdateScheduling
    let actions: StatusPanelActions
    private var cancellables: Set<AnyCancellable> = []
    private var sourceDemandCancellables: Set<AnyCancellable> = []
    private var subscribedSourceDemand: SourceDemand?
    @Published private var bluetoothPresentationRevision = 0
    private var isStarted = false
    private var bluetoothIsExpanded = false
    /// Whether the volume section has published a real, non-empty device list
    /// since the panel last started. Until it has, the section may draw the
    /// cached skeleton instead of an empty list.
    private var volumeDeviceRowsLoaded = false
    /// The last live volume reading delivered by the store. Used to tell a pure
    /// level change from a structural one (mute, devices, availability).
    private var lastLiveVolumeStatus: VolumeStatus?
    /// The newest level-only reading waiting for the next coalesced publish.
    private var pendingLevelVolumeStatus: VolumeStatus?
    private var levelVolumePublishTask: Task<Void, Never>?
    /// A drag emits levels far faster than the row can usefully draw them.
    /// Coalescing to 10 Hz stops the panel hosting view from laying out the
    /// whole tree on every tick (#263); the slider's local draft keeps the
    /// gesture responsive in between.
    static let levelVolumePublishInterval: Duration = .milliseconds(100)
    private var pendingRefreshRegions: RefreshRegions = []
    private var lifecycleGeneration = 0

    /// Tests observe deliveries from the single popup-snapshot subscription
    /// before scheduler coalescing. Production never assigns this closure.
    var popupSourceEventForTesting: (() -> Void)?

    var isShowingDetailPage: Bool { route != .summary }

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        actions: StatusPanelActions,
        updateScheduler: any PanelPresentationUpdateScheduling = YieldingPanelPresentationUpdateScheduler(),
        inputSourceController: InputSourceController? = nil,
        chargeToFullNow: ChargeToFullNowController? = nil
    ) {
        let resolvedInputSourceController = inputSourceController ?? InputSourceController()
        self.store = store
        self.settings = settings
        self.layoutSnapshots = PanelListLayoutSnapshotStore(defaults: settings.userDefaults)
        self.localization = localization
        self.inputSourceController = resolvedInputSourceController
        self.chargeToFullNow = chargeToFullNow
        self.updateScheduler = updateScheduler
        self.actions = actions
        visiblePopupSections = settings.visiblePopupSections
        battery = PanelPresentationMapper.battery(
            store.popupSnapshot.battery,
            powerSample: store.powerSampling.systemPower,
            inputPower: store.powerSampling.inputPower,
            batteryPower: store.powerSampling.batteryPower,
            showsPowerInfoBar: settings.showsBatteryPowerInfoBar,
            localization: localization
        )
        network = PanelPresentationMapper.network(
            wifi: store.popupSnapshot.wifi,
            connection: store.popupSnapshot.connection,
            wired: store.primaryLink.details,
            isConstrained: store.isNetworkConstrained,
            isResolvingName: store.isResolvingWiFiName,
            // Read inline: `self`'s computed accessor is not available until
            // every stored property below is initialized.
            localIPAddress: settings.showsLocalIPAddress ? store.localIP.details.address : nil,
            localization: localization
        )
        vpn = PanelPresentationMapper.vpn(store.vpnStatus, localization: localization)
        bluetooth = .empty(localization: localization)
        volumeControl = VolumeControlModel(
            volume: AudioPanelMapper.volume(
                store.liveVolume,
                controllerAvailable: store.isVolumeControllerAvailable,
                externalVolumeConfiguration: Self.externalVolumeConfiguration(
                    for: store.liveVolume,
                    settings: settings
                ),
                deviceList: settings.outputDeviceListPreferences,
                localization: localization
            )
        )
        audioInput = AudioPanelMapper.input(
            store.liveInput,
            deviceList: settings.inputDeviceListPreferences,
            localization: localization
        )
        inputSource = InputSourcePanelMapper.map(
            state: resolvedInputSourceController.state,
            failure: resolvedInputSourceController.selectionFailure,
            localization: localization
        )
        brightness = BrightnessPanelMapper.map(
            store.popupSnapshot.brightness,
            localization: localization,
            hiddenDisplayIDs: settings.hiddenBrightnessDisplayIDs
        )
        batteryDetails = PanelDetailMapper.battery(
            status: store.popupSnapshot.battery,
            details: store.batteryDetails.details,
            localization: localization,
            powerOptions: settings.batteryPowerDisplayOptions,
            showsPowerFlow: settings.showsBatteryPowerFlow,
            energyApps: settings.showsHighEnergyApps ? store.batteryDetails.energyApps.ranking : nil
        )
        wifiDetails = PanelDetailMapper.wifi(
            status: store.popupSnapshot.wifi,
            networks: store.wifiNetworks.networks,
            details: store.wifiNetworks.details,
            listState: store.wifiNetworks.state,
            localization: localization
        )
        wiredDetails = PanelDetailMapper.wired(details: store.primaryLink.details, localization: localization)
        refreshAll()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        lifecycleGeneration &+= 1
        let sections = settings.visiblePopupSections
        if visiblePopupSections != sections { visiblePopupSections = sections }
        subscribeToPopupPresentationSources()
        subscribeToChargeToFullNow()
        reconcileSourceSubscriptions()
        refreshAll()
        updatePowerSamplingDemand()

        // A no-battery Mac gets its panel title from the shared whole-machine
        // reading, and the provisional info bar shows the other rails; refresh
        // the row as soon as any shared sample changes.
        Publishers.CombineLatest3(
            store.powerSampling.$systemPower,
            store.powerSampling.$inputPower,
            store.powerSampling.$batteryPower
        )
            .sink { [weak self] systemPower, inputPower, batteryPower in
                guard let self else { return }
                if self.isVisible(.battery) {
                    let next = PanelPresentationMapper.battery(
                        self.store.popupSnapshot.battery,
                        powerSample: systemPower,
                        inputPower: inputPower,
                        batteryPower: batteryPower,
                        showsPowerInfoBar: self.settings.showsBatteryPowerInfoBar,
                        powerInfoBarIsLoading: !self.store.powerSampling.hasCompletedFirstRead,
                        localization: self.localization,
                        chargeToFullNow: self.summaryChargeToFullNowPresentation
                    )
                    if self.battery != next { self.battery = next }
                }
                if !self.isRouteAvailable(self.route) { self.closeCurrentPage() }
            }
            .store(in: &cancellables)

        settings.$showsBatteryPowerInfoBar
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                self?.updatePowerSamplingDemand(showsPowerInfoBar: enabled)
            }
            .store(in: &cancellables)

        store.$isPopoverVisible
            .dropFirst()
            .sink { [weak self] _ in
                self?.coalesceControllerUpdate([.bluetooth, .volume])
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$popupSectionOrder,
            settings.$enabledPopupSections
        )
            .dropFirst()
            .sink { [weak self] order, enabled in
                self?.settingsSectionsChanged(order: order, enabled: enabled)
            }
            .store(in: &cancellables)
        // Non-section settings are delivered from `willSet`; only queue the
        // remap here. The scheduler drains after this mutation commits, so its
        // refresh reads the new stored values.
        settings.objectWillChange
            .sink { [weak self] in self?.coalesceControllerUpdate(.all) }
            .store(in: &cancellables)
        localization.$resolvedLanguage
            .dropFirst()
            .sink { [weak self] _ in self?.coalesceControllerUpdate(.all) }
            .store(in: &cancellables)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        lifecycleGeneration &+= 1
        pendingRefreshRegions = []
        volumeDeviceRowsLoaded = false
        cancelLevelVolumePublish()
        lastLiveVolumeStatus = nil
        sourceDemandCancellables.removeAll()
        subscribedSourceDemand = nil
        chargeToFullNow?.clearDemand()
        chargeToFullNowPresentation = .hidden
        summaryChargeToFullNowPresentation = .hidden
        store.powerSampling.end(.panel)
        store.powerSampling.end(.powerInfoBar)
        cancellables.removeAll()
    }

    func showBatteryPage() {
        guard settings.visiblePopupSections.contains(.battery),
              canOpenBatteryPage else {
            showSummaryPage()
            return
        }
        transition(to: .battery)
        actions.batteryDetailsAppeared()
        refreshBatteryDetails()
    }

    func showWiFiPage(showsDetailsInitially: Bool) {
        guard settings.visiblePopupSections.contains(.network) else {
            showSummaryPage()
            return
        }
        wifiDisclosure = WiFiPanelDisclosureState(
            showsDetails: showsDetailsInitially,
            showsMore: false
        )
        transition(to: .wifi)
        actions.wifiDetailsOpened()
        refreshWiFiDetails()
    }

    func showWiredPage() {
        guard settings.visiblePopupSections.contains(.network) else {
            showSummaryPage()
            return
        }
        transition(to: .ethernet)
        actions.wiredDetailsOpened()
        refreshWiredDetailsAndNetwork()
    }

    func showInputSourcePage() {
        guard settings.visiblePopupSections.contains(.inputSource) else {
            showSummaryPage()
            return
        }
        transition(to: .inputSource)
    }

    func showSummaryPage() {
        closeCurrentPage()
    }

    func setWiFiShowsDetails(_ showsDetails: Bool) {
        guard wifiDisclosure.showsDetails != showsDetails else { return }
        var next = wifiDisclosure
        next.showsDetails = showsDetails
        wifiDisclosure = next
    }

    func setWiFiShowsMore(_ showsMore: Bool) {
        guard wifiDisclosure.showsMore != showsMore else { return }
        var next = wifiDisclosure
        next.showsMore = showsMore
        wifiDisclosure = next
    }

    /// Re-enters the lightweight route after a close released the detail view
    /// and its collectors. This runs before the popover's first layout pass.
    func prepareForPresentation() {
        if settings.returnsToSummaryOnOpen {
            closeCurrentPage()
            return
        }
        guard store.isPopoverVisible, route != .summary else { return }
        guard isRouteAvailable(route) else {
            closeCurrentPage()
            return
        }
        switch route {
        case .summary:
            break
        case .battery:
            actions.batteryDetailsAppeared()
            refreshBatteryDetails()
        case .wifi:
            actions.wifiDetailsOpened()
            refreshWiFiDetails()
        case .ethernet:
            actions.wiredDetailsOpened()
            refreshWiredDetailsAndNetwork()
        case .inputSource:
            break
        }
    }

    /// Called by the popover owner after presentation has stopped and while it
    /// is no longer visible. Enabled summaries stay available for an inexpensive
    /// restart; rows and detail payloads can be rebuilt from the store.
    func releaseInactivePresentationState() {
        guard !isStarted, !store.isPopoverVisible, !store.hasOpenPopoverPanel else { return }
        pendingRefreshRegions = []
        bluetoothIsExpanded = false
        volumeDeviceRowsLoaded = false
        bluetooth = bluetooth.releasingDeviceRows()
        batteryDetails = batteryDetails.releasingRows()
        wifiDetails = wifiDetails.releasingLists()
        wiredDetails = wiredDetails.releasingRows()
        if !isVisible(.battery) { battery = battery.releasingPresentation() }
        if !isVisible(.network) { network = network.releasingPresentation() }
        if !isVisible(.vpn) { vpn = vpn.releasingPresentation() }
        if isVisible(.volume) {
            volumeControl.update(volumeControl.volume.releasingDeviceRows())
        } else {
            volumeControl.update(volumeControl.volume.releasingPresentation())
        }
        if isVisible(.audioInput) {
            audioInput = audioInput.releasingDeviceRows()
        } else {
            audioInput = audioInput.releasingPresentation()
        }
        if isVisible(.bluetooth) {
            bluetooth = bluetooth.releasingDeviceRows()
        } else {
            bluetooth = .empty(localization: localization)
        }
        if isVisible(.inputSource) {
            inputSource = inputSource.releasingRows()
        } else {
            inputSource = inputSource.releasingPresentation()
        }
        if !isVisible(.bluetooth), !isVisible(.volume) {
            listeningModeTaskID = ""
        }
    }

    func setBluetoothExpanded(_ expanded: Bool) {
        guard bluetoothIsExpanded != expanded else { return }
        bluetoothIsExpanded = expanded
        if settings.visiblePopupSections.contains(.bluetooth) {
            refreshBluetooth()
        }
    }

    func refreshBluetooth() {
        let controller = store.bluetoothDevices
        let state = BluetoothPanelMapper.map(
            availability: controller.availability,
            devices: controller.devices,
            batteryLevels: controller.batteryLevels,
            actionStates: controller.deviceActionStates,
            nearbyDevices: controller.nearbyBatteryDevices,
            batteryLevelsReadFailed: controller.batteryLevelsReadFailed,
            isExpanded: bluetoothIsExpanded,
            options: settings.bluetoothDeviceListOptions,
            showsBatteryLevels: settings.showsBluetoothBatteryLevels,
            showsNearbyBatteryDevices: settings.showsNearbyBluetoothBatteryDevices,
            confirmingAddress: controller.pendingDisconnectConfirmation,
            localization: localization
        )
        if bluetooth != state { bluetooth = state }
        // The view reads the controller's row presentations directly. Publish a
        // lightweight revision so presentation-only changes still redraw without
        // retaining a second dictionary beside the controller.
        bluetoothPresentationRevision &+= 1
    }

    /// The address the network row shows, or `nil` while the setting is off or
    /// nothing has been read yet. Read through one place so the row cannot show
    /// an address a user has since switched off.
    private var resolvedLocalIPAddress: String? {
        guard settings.showsLocalIPAddress else { return nil }
        return store.localIP.details.address
    }

    private var outputPreferences: AudioOutputListPreferences {
        settings.outputDeviceListPreferences
    }

    private func mapVPN(_ status: VPNStatus) -> PanelSummaryState? {
        PanelPresentationMapper.vpn(status, localization: localization)
    }

    private func mapVolume(_ status: VolumeStatus) -> VolumePanelState {
        let previewConfiguration = currentPreviewConfiguration
        // Draw the cached skeleton only inside the window between reopening and
        // the first real device list of this presentation. A genuinely empty or
        // unavailable controller must not keep a stale skeleton on screen.
        let deviceListPlaceholder: PanelListLayoutSnapshot? =
            !volumeDeviceRowsLoaded
            && status.outputDevices.isEmpty
            && store.isVolumeControllerAvailable
            ? layoutSnapshots.snapshot(for: .volume).flatMap { $0.showsDeviceList ? $0 : nil }
            : nil
        return AudioPanelMapper.volume(
            status,
            controllerAvailable: store.isVolumeControllerAvailable,
            externalVolumeConfiguration: Self.externalVolumeConfiguration(
                for: status,
                settings: settings
            ),
            deviceList: outputPreferences,
            listeningModes: settings.showsBluetoothListeningMode ? store.bluetoothListeningModes : nil,
            listeningModeTaskID: makeListeningModeTaskID(outputDevices: status.outputDevices),
            previewDevices: ListeningModePreview.outputRows(for: previewConfiguration, volume: status.scalar),
            previewLanguageCode: previewConfiguration.languageCode,
            previewLocalization: PreviewLocalization.forCode(previewConfiguration.languageCode),
            deviceListPlaceholder: deviceListPlaceholder,
            localization: localization
        )
    }

    private static func externalVolumeConfiguration(
        for status: VolumeStatus,
        settings: SettingsStore
    ) -> ExternalVolumeConfiguration {
        let currentDevice = status.currentDevice
            ?? status.outputDevices.first(where: \.isCurrent)
        guard let uid = currentDevice?.uid?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !uid.isEmpty
        else {
            return .default
        }
        return settings.externalVolumeConfiguration(for: uid)
    }

    private var currentPreviewConfiguration: ListeningModePreview.Configuration {
        ListeningModePreview.Configuration(
            isEnabled: settings.showsBluetoothListeningMode && settings.previewsBluetoothListeningMode,
            deviceName: settings.bluetoothListeningModePreviewDeviceName,
            deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
            languageCode: settings.bluetoothListeningModePreviewLanguage
        )
    }

    private func makeListeningModeTaskID(outputDevices: [AudioOutputDevice]) -> String {
        let configuration = ListeningModePreview.Configuration(
            isEnabled: settings.showsBluetoothListeningMode && settings.previewsBluetoothListeningMode,
            deviceName: settings.bluetoothListeningModePreviewDeviceName,
            deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
            languageCode: settings.bluetoothListeningModePreviewLanguage
        )
        guard settings.showsBluetoothListeningMode else {
            // Master switch off: no real or preview listening-mode surface. A
            // stable non-empty tag lets the summary task mark this generation
            // "closed" and tear down discovery (see `listeningModeTaskID`).
            return "off::\(store.popoverOpenGeneration)"
        }
        let connected = BluetoothDevicePresentation.grouped(store.bluetoothDevices.devices).connected
            .filter { $0.isAirPods || $0.isHuaweiAudio }
            .map { BluetoothBatteryReader.normalizedAddress($0.id) }
            .joined(separator: ",")
        let preview = configuration.isEnabled ? "|preview" : ""
        let synthetic = ListeningModePreview.devices(for: configuration)
            .map { BluetoothBatteryReader.normalizedAddress($0.id) }
            .joined(separator: ",")
        let outputs = outputDevices.map { String($0.id) }.joined(separator: ",")
        let current = outputDevices.filter { $0.isCurrent }.map { String($0.id) }.joined(separator: ",")
        return connected + preview + (synthetic.isEmpty ? "" : "|\(synthetic)")
            + "|outputs:\(outputs)|current:\(current)|visible:\(store.isPopoverVisible)"
            + "|open:\(store.popoverOpenGeneration)"
    }

    private func updateListeningModeTaskID(outputDevices: [AudioOutputDevice]) {
        guard isVisible(.bluetooth) || isVisible(.volume) else { return }
        let next = makeListeningModeTaskID(outputDevices: outputDevices)
        if listeningModeTaskID != next { listeningModeTaskID = next }
    }

    private func mapInput(_ status: AudioInputStatus) -> AudioInputPanelState {
        AudioPanelMapper.input(
            status,
            deviceList: settings.inputDeviceListPreferences,
            localization: localization
        )
    }

    private func subscribeToPopupPresentationSources() {
        store.$popupSnapshot
            .combineLatest(store.$isNetworkConstrained, store.$isResolvingWiFiName)
            .dropFirst()
            .sink { [weak self] snapshot, isConstrained, isResolvingName in
                self?.popupSourceEventForTesting?()
                self?.refreshPopupPanels(
                    snapshot: snapshot,
                    isConstrained: isConstrained,
                    isResolvingName: isResolvingName
                )
            }
            .store(in: &cancellables)
        store.batteryDetails.$details
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, store.batteryDetails.isActive else { return }
                coalesceControllerUpdate(.batteryDetails)
            }
            .store(in: &cancellables)
        store.batteryDetails.energyApps.$ranking
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, store.batteryDetails.isActive else { return }
                coalesceControllerUpdate(.batteryDetails)
            }
            .store(in: &cancellables)
        Publishers.CombineLatest3(
            store.wifiNetworks.$details,
            store.wifiNetworks.$networks,
            store.wifiNetworks.$state
        )
            .dropFirst()
            .sink { [weak self] _, _, _ in
                guard let self, store.wifiNetworks.isActive else { return }
                coalesceControllerUpdate(.wifiDetails)
            }
            .store(in: &cancellables)
        store.primaryLink.$details
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.store.primaryLink.isActive
                    || self.isVisible(.network) {
                    self.coalesceControllerUpdate(.wiredDetailsAndNetwork)
                }
            }
            .store(in: &cancellables)
        store.localIP.$details
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, isVisible(.network) else { return }
                coalesceControllerUpdate(.localIP)
            }
            .store(in: &cancellables)
    }

    private func subscribeToChargeToFullNow() {
        guard let chargeToFullNow else {
            chargeToFullNowPresentation = .hidden
            summaryChargeToFullNowPresentation = .hidden
            return
        }

        chargeToFullNow.$presentation
            .removeDuplicates()
            .sink { [weak self] presentation in
                guard let self else { return }
                chargeToFullNowPresentation = presentation
                refreshSummaryChargeToFullNowPresentation()
                refreshBatterySummary()
            }
            .store(in: &cancellables)

        // The Settings toggle only gates the summary card; the battery details
        // page uses the ungated presentation. Refresh the summary immediately on
        // toggle so turning it off/on updates the card without waiting for the
        // next battery tick.
        settings.$showsChargeToFullNowButton
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                // `@Published` emits before the stored property updates, so use
                // the emitted value rather than re-reading the store here.
                refreshSummaryChargeToFullNowPresentation(settingEnabled: enabled)
                refreshBatterySummary()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            Publishers.CombineLatest(
                settings.$enabledPopupSections,
                settings.$popupSectionOrder
            )
                .map { enabled, order in
                    enabled.contains(.battery) && order.contains(.battery)
                }
                .removeDuplicates(),
            store.$isPopoverVisible.removeDuplicates(),
            store.$popupSnapshot
                .map(\.battery)
                .removeDuplicates()
        )
        .sink { [weak self] batterySectionVisible, popoverVisible, battery in
            self?.updateChargeToFullNowDemand(
                batterySectionVisible: batterySectionVisible,
                popoverVisible: popoverVisible,
                battery: battery
            )
        }
        .store(in: &cancellables)
    }

    private func refreshSummaryChargeToFullNowPresentation(
        settingEnabled: Bool? = nil
    ) {
        let enabled = settingEnabled ?? settings.showsChargeToFullNowButton
        let next = enabled ? chargeToFullNowPresentation : .hidden
        if summaryChargeToFullNowPresentation != next {
            summaryChargeToFullNowPresentation = next
        }
    }

    /// True when the battery page has something to show: a real battery, or a
    /// whole-machine power reading on a Mac that has none.
    private var canOpenBatteryPage: Bool {
        store.popupSnapshot.battery.isPresent
            || (store.powerSampling.systemPower?.isFresh(at: Date()) ?? false)
    }

    /// The panel summary and a no-battery page need the shared sampler only
    /// while the customer can see them. The details page registers its own
    /// demand, so closing the panel never cuts a sample it is still using.
    private func updatePowerSamplingDemand(showsPowerInfoBar: Bool? = nil) {
        let panelVisible = isStarted && visiblePopupSections.contains(.battery)
        if panelVisible {
            store.powerSampling.begin(.panel)
        } else {
            store.powerSampling.end(.panel)
        }
        // The provisional info bar needs the input and battery rails; without
        // it the sampler reads only the whole-machine total. Published settings
        // arrive before their stored value commits, so prefer the delivered value.
        let showsInfoBar = showsPowerInfoBar ?? settings.showsBatteryPowerInfoBar
        if panelVisible, showsInfoBar {
            store.powerSampling.begin(.powerInfoBar)
        } else {
            store.powerSampling.end(.powerInfoBar)
        }
    }

    /// Re-maps the visible battery row when the charge action changes, so the
    /// subtitle reflects the click before the system's charging flag catches up.
    private func refreshBatterySummary() {
        guard isVisible(.battery) else { return }
        let next = PanelPresentationMapper.battery(
            store.popupSnapshot.battery,
            powerSample: store.powerSampling.systemPower,
            inputPower: store.powerSampling.inputPower,
            batteryPower: store.powerSampling.batteryPower,
            showsPowerInfoBar: settings.showsBatteryPowerInfoBar,
            powerInfoBarIsLoading: !store.powerSampling.hasCompletedFirstRead,
            localization: localization,
            chargeToFullNow: summaryChargeToFullNowPresentation
        )
        if battery != next { battery = next }
    }

    private func updateChargeToFullNowDemand(
        batterySectionVisible: Bool,
        popoverVisible: Bool,
        battery: BatteryStatus
    ) {
        guard isStarted, let chargeToFullNow else {
            chargeToFullNowPresentation = .hidden
            return
        }
        chargeToFullNow.update(
            ChargeToFullNowDemand(
                popoverVisible: popoverVisible,
                batterySectionVisible: batterySectionVisible,
                battery: battery
            )
        )
    }

    private func reconcileSourceSubscriptions(
        deliveredSections: [PopupSection]? = nil
    ) {
        guard isStarted else { return }
        if let deliveredSections {
            if visiblePopupSections != deliveredSections {
                visiblePopupSections = deliveredSections
            }
        } else {
            applyCurrentSettingsSections()
        }
        var demand: SourceDemand = []
        if isVisible(.bluetooth) { demand.insert(.bluetooth) }
        if isVisible(.volume) {
            // AirPods listening mode and device identity are part of the audio
            // output presentation even when the Bluetooth section is hidden.
            demand.insert(.bluetooth)
            demand.insert(.volume)
        }
        if isVisible(.audioInput) { demand.insert(.audioInput) }
        if isVisible(.inputSource) { demand.insert(.inputSource) }
        if isVisible(.vpn) { demand.insert(.vpn) }
        if isVisible(.network) { demand.insert(.localIP) }
        guard demand != subscribedSourceDemand else { return }

        sourceDemandCancellables.removeAll()
        subscribedSourceDemand = demand

        if demand.contains(.vpn) {
            store.$vpnStatus
                .dropFirst()
                .compactMap { [weak self] status -> PanelSummaryState? in
                    guard let self, isVisible(.vpn) else { return nil }
                    return mapVPN(status)
                }
                .removeDuplicates()
                .sink { [weak self] state in
                    guard let self, isVisible(.vpn) else { return }
                    publishVPN(state)
                }
                .store(in: &sourceDemandCancellables)
        }
        if demand.contains(.volume) {
            store.$liveVolume
                .dropFirst()
                .sink { [weak self] status in
                    guard let self, isVisible(.volume) else { return }
                    receiveLiveVolume(status)
                }
                .store(in: &sourceDemandCancellables)
        }
        if demand.contains(.audioInput) {
            store.$liveInput
                .dropFirst()
                .map { [weak self] status -> AudioInputPanelState? in
                    guard let self, isVisible(.audioInput) else { return nil }
                    return mapInput(status)
                }
                .compactMap { $0 }
                .removeDuplicates()
                .sink { [weak self] state in
                    guard let self, isVisible(.audioInput) else { return }
                    publishAudioInput(state)
                }
                .store(in: &sourceDemandCancellables)
        }
        if demand.contains(.inputSource) {
            Publishers.CombineLatest(
                inputSourceController.$state,
                inputSourceController.$selectionFailure
            )
            .dropFirst()
            .sink { [weak self] state, failure in
                guard let self, isVisible(.inputSource) else { return }
                publishInputSource(state: state, failure: failure)
            }
            .store(in: &sourceDemandCancellables)
        }
        if demand.contains(.bluetooth) {
            let regions: RefreshRegions = isVisible(.volume) ? [.bluetooth, .volume] : .bluetooth
            if !demand.contains(.volume) {
                store.$liveVolume
                    .map(\.outputDevices)
                    .removeDuplicates()
                    .dropFirst()
                    .sink { [weak self] outputDevices in
                        guard let self, isVisible(.bluetooth), !isVisible(.volume) else { return }
                        updateListeningModeTaskID(outputDevices: outputDevices)
                    }
                    .store(in: &sourceDemandCancellables)
            }
            store.bluetoothDevices.objectWillChange
                .sink { [weak self] in
                    guard let self, isStarted,
                          isVisible(.bluetooth) || isVisible(.volume) else { return }
                    coalesceControllerUpdate(regions)
                }
                .store(in: &sourceDemandCancellables)
            store.bluetoothListeningModes.$presentations
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self, isStarted,
                          isVisible(.bluetooth) || isVisible(.volume) else { return }
                    coalesceControllerUpdate(regions)
                }
                .store(in: &sourceDemandCancellables)
        }
    }

    private func isVisible(_ section: PopupSection) -> Bool {
        visiblePopupSections.contains(section)
    }

    private func refreshAll() {
        applyCurrentSettingsSections()
        reconcileSourceSubscriptions()
        refreshPopupPanels()
        if isVisible(.vpn) {
            publishVPN(PanelPresentationMapper.vpn(store.vpnStatus, localization: localization))
        }
        if isVisible(.bluetooth) { refreshBluetooth() }
        if isVisible(.volume) {
            publishVolume(mapVolume(store.liveVolume))
        } else if isVisible(.bluetooth) {
            updateListeningModeTaskID(outputDevices: store.liveVolume.outputDevices)
        }
        if isVisible(.audioInput) {
            publishAudioInput(mapInput(store.liveInput))
        }
        if isVisible(.brightness) {
            brightness = BrightnessPanelMapper.map(
                store.popupSnapshot.brightness,
                localization: localization,
                hiddenDisplayIDs: settings.hiddenBrightnessDisplayIDs
            )
        }
        if isVisible(.inputSource) {
            publishInputSource(
                state: inputSourceController.state,
                failure: inputSourceController.selectionFailure
            )
        }
        if store.batteryDetails.isActive { refreshBatteryDetails() }
        if store.wifiNetworks.isActive { refreshWiFiDetails() }
        refreshWiredDetailsAndNetwork()
    }

    private func applyCurrentSettingsSections() {
        let sections = settings.visiblePopupSections
        if visiblePopupSections != sections { visiblePopupSections = sections }
    }

    private func settingsSectionsChanged(
        order: [PopupSection],
        enabled: Set<PopupSection>
    ) {
        let sections = order.filter { enabled.contains($0) }
        if visiblePopupSections != sections { visiblePopupSections = sections }
        reconcileSourceSubscriptions(deliveredSections: sections)
        updatePowerSamplingDemand()
        if !isRouteAvailable(route) { closeCurrentPage() }
        coalesceControllerUpdate(.all)
    }

    private func refreshPopupPanels(
        snapshot deliveredSnapshot: StatusSnapshot? = nil,
        isConstrained deliveredConstraint: Bool? = nil,
        isResolvingName deliveredResolutionState: Bool? = nil
    ) {
        let snapshot = deliveredSnapshot ?? store.popupSnapshot
        let isConstrained = deliveredConstraint ?? store.isNetworkConstrained
        let isResolvingName = deliveredResolutionState ?? store.isResolvingWiFiName
        if isVisible(.battery) {
            let batteryState = PanelPresentationMapper.battery(
                snapshot.battery,
                powerSample: store.powerSampling.systemPower,
                inputPower: store.powerSampling.inputPower,
                batteryPower: store.powerSampling.batteryPower,
                showsPowerInfoBar: settings.showsBatteryPowerInfoBar,
                localization: localization,
                chargeToFullNow: summaryChargeToFullNowPresentation
            )
            if battery != batteryState { battery = batteryState }
        }
        if isVisible(.network) {
            let networkState = PanelPresentationMapper.network(
                wifi: snapshot.wifi,
                connection: snapshot.connection,
                wired: store.primaryLink.details,
                isConstrained: isConstrained,
                isResolvingName: isResolvingName,
                localIPAddress: resolvedLocalIPAddress,
                localization: localization
            )
            if network != networkState { network = networkState }
        }
        if isVisible(.brightness) {
            let brightnessState = BrightnessPanelMapper.map(
                snapshot.brightness,
                localization: localization,
                hiddenDisplayIDs: settings.hiddenBrightnessDisplayIDs
            )
            if brightness != brightnessState { brightness = brightnessState }
        }
        if store.batteryDetails.isActive { refreshBatteryDetails(status: snapshot.battery) }
        if store.wifiNetworks.isActive { refreshWiFiDetails(status: snapshot.wifi) }
        if !isRouteAvailable(route) { closeCurrentPage() }
    }

    private func refreshBatteryDetails(status deliveredStatus: BatteryStatus? = nil) {
        guard store.batteryDetails.isActive else { return }
        store.batteryDetails.configure(options: settings.batteryPowerDisplayOptions,
            showsHighEnergyApps: settings.showsHighEnergyApps)
        let status = deliveredStatus ?? store.popupSnapshot.battery
        // The page can outlive a plugin or a charge-limit pulse. Keep the
        // collector's context aligned with the latest snapshot so the next
        // sample is collected for the state the user is actually looking at.
        store.batteryDetails.update(state: BatteryPowerState(status))
        let state = PanelDetailMapper.battery(
            status: status,
            details: store.batteryDetails.details,
            localization: localization,
            powerOptions: settings.batteryPowerDisplayOptions,
            showsPowerFlow: settings.showsBatteryPowerFlow,
            energyApps: settings.showsHighEnergyApps ? store.batteryDetails.energyApps.ranking : nil
        )
        if batteryDetails != state { batteryDetails = state }
    }

    private func refreshWiFiDetails(status deliveredStatus: WiFiStatus? = nil) {
        guard store.wifiNetworks.isActive else { return }
        let state = PanelDetailMapper.wifi(
            status: deliveredStatus ?? store.popupSnapshot.wifi,
            networks: store.wifiNetworks.networks,
            details: store.wifiNetworks.details,
            listState: store.wifiNetworks.state,
            localization: localization
        )
        if wifiDetails != state { wifiDetails = state }
    }

    private func refreshWiredDetailsAndNetwork() {
        if store.primaryLink.isActive {
            let wiredState = PanelDetailMapper.wired(
                details: store.primaryLink.details,
                localization: localization
            )
            if wiredDetails != wiredState { wiredDetails = wiredState }
        }
        if isVisible(.network) {
            let snapshot = store.popupSnapshot
            let networkState = PanelPresentationMapper.network(
                wifi: snapshot.wifi,
                connection: snapshot.connection,
                wired: store.primaryLink.details,
                isConstrained: store.isNetworkConstrained,
                isResolvingName: store.isResolvingWiFiName,
                localIPAddress: resolvedLocalIPAddress,
                localization: localization
            )
            if network != networkState { network = networkState }
        }
    }

    private func transition(to next: StatusPanelRoute) {
        guard route != next else { return }
        if route != .summary { closeCurrentPage() }
        route = next
    }

    private func closeCurrentPage() {
        guard route != .summary else { return }
        switch route {
        case .battery:
            actions.batteryDetailsClosed()
        case .wifi:
            actions.wifiDetailsClosed()
        case .ethernet:
            actions.wiredDetailsClosed()
        case .inputSource:
            break
        case .summary:
            return
        }
        route = .summary
    }

    private func isRouteAvailable(_ route: StatusPanelRoute) -> Bool {
        let sections = settings.visiblePopupSections
        switch route {
        case .summary:
            return true
        case .battery:
            return sections.contains(.battery) && canOpenBatteryPage
        case .wifi:
            return sections.contains(.network)
        case .ethernet:
            return sections.contains(.network)
                && store.popupSnapshot.connection == .ethernet
        case .inputSource:
            return sections.contains(.inputSource)
        }
    }


    private func coalesceControllerUpdate(_ regions: RefreshRegions) {
        guard isStarted else { return }
        let shouldSchedule = pendingRefreshRegions.isEmpty
        pendingRefreshRegions.formUnion(regions)
        guard shouldSchedule else { return }
        let generation = lifecycleGeneration
        updateScheduler.schedule { [weak self] in
            guard let self, isStarted, lifecycleGeneration == generation,
                  !pendingRefreshRegions.isEmpty else { return }
            let regions = pendingRefreshRegions
            pendingRefreshRegions = []
            if regions.contains(.all) {
                refreshAll()
                return
            }
            if regions.contains(.batteryDetails), store.batteryDetails.isActive {
                refreshBatteryDetails()
            }
            if regions.contains(.wifiDetails), store.wifiNetworks.isActive {
                refreshWiFiDetails()
            }
            if regions.contains(.wiredDetailsAndNetwork) { refreshWiredDetailsAndNetwork() }
            if regions.contains(.bluetooth), isVisible(.bluetooth) { refreshBluetooth() }
            if regions.contains(.volume), isVisible(.volume) {
                publishVolume(mapVolume(store.liveVolume))
            } else if regions.contains(.bluetooth), isVisible(.bluetooth) {
                updateListeningModeTaskID(outputDevices: store.liveVolume.outputDevices)
            }
            if regions.contains(.localIP) { refreshWiredDetailsAndNetwork() }
            if regions.contains(.audioInput), isVisible(.audioInput) {
                publishAudioInput(mapInput(store.liveInput))
            }
            if regions.contains(.inputSource), isVisible(.inputSource) {
                publishInputSource(
                    state: inputSourceController.state,
                    failure: inputSourceController.selectionFailure
                )
            }
            if regions.contains(.vpn), isVisible(.vpn) {
                publishVPN(PanelPresentationMapper.vpn(store.vpnStatus, localization: localization))
            }
        }
    }

    private func publishVPN(_ state: PanelSummaryState?) {
        guard let state, vpn != state else { return }
        vpn = state
    }

    /// Receives a raw live reading. A structural change (mute, device list,
    /// availability, control source, external transition) publishes at once; a
    /// pure level change is coalesced so a drag cannot invalidate the panel on
    /// every tick (#263).
    private func receiveLiveVolume(_ status: VolumeStatus) {
        let previous = lastLiveVolumeStatus
        lastLiveVolumeStatus = status
        if let previous, status.changesOnlyLevel(comparedTo: previous) {
            pendingLevelVolumeStatus = status
            scheduleLevelVolumePublish()
        } else {
            publishVolume(mapVolume(status))
        }
    }

    private func scheduleLevelVolumePublish() {
        guard levelVolumePublishTask == nil else { return }
        levelVolumePublishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.levelVolumePublishInterval)
            } catch {
                return
            }
            guard let self else { return }
            self.levelVolumePublishTask = nil
            let status = self.pendingLevelVolumeStatus
            self.pendingLevelVolumeStatus = nil
            guard self.isStarted, self.isVisible(.volume), let status else { return }
            self.publishVolume(self.mapVolume(status))
        }
    }

    private func cancelLevelVolumePublish() {
        levelVolumePublishTask?.cancel()
        levelVolumePublishTask = nil
        pendingLevelVolumeStatus = nil
    }

    private func publishVolume(_ state: VolumePanelState) {
        // Any immediate publish supersedes a pending coalesced level.
        cancelLevelVolumePublish()
        if listeningModeTaskID != state.listeningModeTaskID {
            listeningModeTaskID = state.listeningModeTaskID
        }
        guard volumeControl.update(state) else { return }
        // Once real rows are back, remember the collapsed layout so the next
        // open can reserve its height, and mark the section as loaded so it stops
        // asking for the skeleton.
        guard !state.rows.isEmpty else { return }
        volumeDeviceRowsLoaded = true
        let snapshot = PanelListLayoutSnapshot(
            rowHeights: VolumeDeviceRowMetrics.rowHeights(for: state.visibleRows(expanded: false)),
            hasExpansionButton: state.hasHiddenRows,
            showsDeviceList: state.showsDeviceList
        )
        layoutSnapshots.save(snapshot.isEmpty ? nil : snapshot, for: .volume)
    }

    private func publishAudioInput(_ state: AudioInputPanelState) {
        guard audioInput != state else { return }
        audioInput = state
    }

    private func publishInputSource(
        state: InputSourceState,
        failure: InputSourceController.SelectionFailure?
    ) {
        let next = InputSourcePanelMapper.map(state: state, failure: failure, localization: localization)
        guard inputSource != next else { return }
        inputSource = next
    }
}

private extension BluetoothPanelState {
    func releasingDeviceRows() -> Self {
        BluetoothPanelState(
            summary: summary,
            summaryBatterySegments: summaryBatterySegments,
            hasConnectedDevices: hasConnectedDevices,
            batteryReadTaskID: batteryReadTaskID,
            pairedRows: [],
            nearbyRows: [],
            errorText: errorText,
            showsPairedHeading: false,
            canExpand: false,
            confirmationAddress: confirmationAddress,
            showsBatteryLevels: showsBatteryLevels,
            showsNearbyBatteryDevices: showsNearbyBatteryDevices
        )
    }
}

private extension PanelSummaryState {
    func releasingPresentation() -> Self {
        PanelSummaryState(
            title: "",
            subtitle: "",
            measurements: nil,
            symbol: .symbol(name: "square", variableValue: nil, fallback: nil),
            tint: .secondary,
            accessibilityLabel: "",
            accessibilityValue: "",
            showsSettings: false,
            intent: .none
        )
    }
}

private extension VolumePanelState {
    func releasingDeviceRows() -> Self {
        VolumePanelState(
            summary: summary,
            scalar: scalar,
            percentageText: percentageText,
            outputIdentity: outputIdentity,
            interactionIdentity: interactionIdentity,
            muted: muted,
            muteState: muteState,
            canAdjust: canAdjust,
            canMute: canMute,
            muteSymbol: muteSymbol,
            muteHelp: muteHelp,
            sliderLabel: sliderLabel,
            showsDeviceList: false,
            deviceListPlaceholder: nil,
            rows: [],
            previewRows: [],
            visibleLimit: visibleLimit,
            expandLabel: expandLabel,
            collapseLabel: collapseLabel,
            listeningModeTaskID: listeningModeTaskID,
            previewLanguageCode: previewLanguageCode
        )
    }

    func releasingPresentation() -> Self {
        VolumePanelState(
            summary: summary.releasingPresentation(),
            scalar: scalar,
            percentageText: percentageText,
            outputIdentity: outputIdentity,
            interactionIdentity: interactionIdentity,
            muted: muted,
            muteState: muteState,
            canAdjust: false,
            canMute: false,
            muteSymbol: muteSymbol,
            muteHelp: muteHelp,
            sliderLabel: sliderLabel,
            showsDeviceList: false,
            deviceListPlaceholder: nil,
            rows: [],
            previewRows: [],
            visibleLimit: visibleLimit,
            expandLabel: expandLabel,
            collapseLabel: collapseLabel,
            listeningModeTaskID: listeningModeTaskID,
            previewLanguageCode: previewLanguageCode
        )
    }
}

private extension AudioInputPanelState {
    func releasingDeviceRows() -> Self {
        AudioInputPanelState(
            summary: summary,
            selectedDeviceIdentity: selectedDeviceIdentity,
            scalar: scalar,
            percentageText: percentageText,
            muteSymbol: muteSymbol,
            muteTint: muteTint,
            muteHelp: muteHelp,
            muteState: muteState,
            canAdjust: false,
            canMute: false,
            isBusy: isBusy,
            errorText: errorText,
            showsDeviceList: false,
            rows: [],
            visibleLimit: visibleLimit,
            expandLabel: expandLabel,
            collapseLabel: collapseLabel,
            sliderLabel: sliderLabel,
            usageText: usageText,
            completedScalarRequestID: nil
        )
    }

    func releasingPresentation() -> Self {
        releasingDeviceRows()
    }
}

private extension InputSourcePanelState {
    func releasingRows() -> Self {
        InputSourcePanelState(
            title: title,
            currentName: currentName,
            rows: [],
            emptyMessage: emptyMessage,
            failureText: failureText,
            openSettingsLabel: openSettingsLabel
        )
    }

    func releasingPresentation() -> Self {
        InputSourcePanelState(
            title: "",
            currentName: nil,
            rows: [],
            emptyMessage: nil,
            failureText: nil,
            openSettingsLabel: ""
        )
    }
}

private extension PanelDetailState {
    func releasingRows() -> Self {
        PanelDetailState(
            title: title,
            rows: [],
            isLoading: false,
            errorText: errorText,
            explanation: nil,
            lifecycleIdentity: lifecycleIdentity
        )
    }
}

private extension WiFiPanelState {
    func releasingLists() -> Self {
        WiFiPanelState(
            detail: detail.releasingRows(),
            collapsedDetailRowCount: collapsedDetailRowCount,
            showMoreTitle: showMoreTitle,
            showLessTitle: showLessTitle,
            personalHotspotRows: [],
            knownRows: [],
            otherRows: [],
            powerIsOn: powerIsOn,
            canSetPower: canSetPower,
            canRefresh: false,
            isScanning: false,
            message: message,
            messageIntent: messageIntent,
            showsConnectionDetails: showsConnectionDetails
        )
    }
}

@MainActor
private extension BluetoothPanelState {
    static func empty(localization: Localization) -> BluetoothPanelState {
        BluetoothPanelState(
            summary: PanelSummaryState(
                title: localization.string(.bluetoothTitle),
                subtitle: "",
                measurements: nil,
                symbol: .symbol(name: "bluetooth", variableValue: nil, fallback: "antenna.radiowaves.left.and.right"),
                tint: .secondary,
                accessibilityLabel: localization.string(.bluetoothTitle),
                accessibilityValue: "",
                showsSettings: true,
                intent: .none
            ),
            summaryBatterySegments: nil,
            hasConnectedDevices: false,
            batteryReadTaskID: "false-",
            pairedRows: [],
            nearbyRows: [],
            errorText: nil,
            showsPairedHeading: false,
            canExpand: false,
            confirmationAddress: nil,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false
        )
    }
}
