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
    @Published private(set) var volume: VolumePanelState
    @Published private(set) var audioInput: AudioInputPanelState
    @Published private(set) var inputSource: InputSourcePanelState
    @Published private(set) var batteryDetails: PanelDetailState
    @Published private(set) var wifiDetails: WiFiPanelState
    @Published private(set) var wiredDetails: PanelDetailState
    @Published private(set) var visiblePopupSections: [PopupSection]

    let store: SystemStatusStore
    let settings: SettingsStore
    private let localization: Localization
    private let inputSourceController: InputSourceController
    private let updateScheduler: any PanelPresentationUpdateScheduling
    private let capabilityPolicy: DistributionCapabilityPolicy
    let actions: StatusPanelActions
    private var cancellables: Set<AnyCancellable> = []
    private var sourceDemandCancellables: Set<AnyCancellable> = []
    private var subscribedSourceDemand: SourceDemand?
    @Published private var bluetoothPresentationRevision = 0
    private var isStarted = false
    private var bluetoothIsExpanded = false
    private var pendingRefreshRegions: RefreshRegions = []
    private var lifecycleGeneration = 0

    /// Tests observe deliveries from the single popup-snapshot subscription
    /// before scheduler coalescing. Production never assigns this closure.
    var popupSourceEventForTesting: (() -> Void)?

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        actions: StatusPanelActions,
        updateScheduler: any PanelPresentationUpdateScheduling = YieldingPanelPresentationUpdateScheduler(),
        inputSourceController: InputSourceController? = nil,
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault
    ) {
        let resolvedInputSourceController = inputSourceController ?? InputSourceController()
        self.store = store
        self.settings = settings
        self.localization = localization
        self.inputSourceController = resolvedInputSourceController
        self.updateScheduler = updateScheduler
        self.capabilityPolicy = capabilityPolicy
        self.actions = actions
        visiblePopupSections = settings.visiblePopupSections
        battery = PanelPresentationMapper.battery(store.popupSnapshot.battery, localization: localization)
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
        volume = AudioPanelMapper.volume(
            store.liveVolume,
            controllerAvailable: store.isVolumeControllerAvailable,
            deviceList: AudioOutputListPreferences(
                order: settings.outputDeviceOrder,
                visibleLimit: settings.visibleOutputDeviceLimit
            ),
            localization: localization
        )
        audioInput = AudioPanelMapper.input(store.liveInput, localization: localization)
        inputSource = InputSourcePanelMapper.map(
            state: resolvedInputSourceController.state,
            failure: resolvedInputSourceController.selectionFailure,
            localization: localization
        )
        batteryDetails = PanelDetailMapper.battery(
            status: store.popupSnapshot.battery,
            details: store.batteryDetails.details,
            localization: localization
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
        reconcileSourceSubscriptions()
        refreshAll()

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
        sourceDemandCancellables.removeAll()
        subscribedSourceDemand = nil
        cancellables.removeAll()
    }

    /// Called by the popover owner after presentation has stopped and while it
    /// is no longer visible. Enabled summaries stay available for an inexpensive
    /// restart; rows and detail payloads can be rebuilt from the store.
    func releaseInactivePresentationState() {
        guard !isStarted, !store.isPopoverVisible, !store.hasOpenPopoverPanel else { return }
        pendingRefreshRegions = []
        bluetoothIsExpanded = false
        bluetooth = bluetooth.releasingDeviceRows()
        batteryDetails = batteryDetails.releasingRows()
        wifiDetails = wifiDetails.releasingLists()
        wiredDetails = wiredDetails.releasingRows()
        if !isVisible(.battery) { battery = battery.releasingPresentation() }
        if !isVisible(.network) { network = network.releasingPresentation() }
        if !isVisible(.vpn) { vpn = vpn.releasingPresentation() }
        if isVisible(.volume) {
            volume = volume.releasingDeviceRows()
        } else {
            volume = volume.releasingPresentation()
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
        AudioOutputListPreferences(
            order: settings.outputDeviceOrder,
            visibleLimit: settings.visibleOutputDeviceLimit
        )
    }

    private func mapVPN(_ status: VPNStatus) -> PanelSummaryState? {
        PanelPresentationMapper.vpn(status, localization: localization)
    }

    private func mapVolume(_ status: VolumeStatus) -> VolumePanelState {
        let previewConfiguration = currentPreviewConfiguration
        return AudioPanelMapper.volume(
            status,
            controllerAvailable: store.isVolumeControllerAvailable,
            deviceList: outputPreferences,
            listeningModes: store.bluetoothListeningModes,
            listeningModeTaskID: makeListeningModeTaskID(outputDevices: status.outputDevices),
            previewDevices: ListeningModePreview.outputRows(for: previewConfiguration, volume: status.scalar),
            previewLanguageCode: previewConfiguration.languageCode,
            previewLocalization: PreviewLocalization.forCode(previewConfiguration.languageCode),
            localization: localization
        )
    }

    private var currentPreviewConfiguration: ListeningModePreview.Configuration {
        ListeningModePreview.Configuration(
            isEnabled: !capabilityPolicy.blocksControl(.appleListeningMode)
                && settings.previewsBluetoothListeningMode,
            deviceName: settings.bluetoothListeningModePreviewDeviceName,
            deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
            languageCode: settings.bluetoothListeningModePreviewLanguage
        )
    }

    private func makeListeningModeTaskID(outputDevices: [AudioOutputDevice]) -> String {
        let configuration = currentPreviewConfiguration
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

    private func mapInput(_ status: AudioInputStatus) -> AudioInputPanelState? {
        AudioPanelMapper.input(status, localization: localization)
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
                .compactMap { [weak self] status -> VolumePanelState? in
                    guard let self, isVisible(.volume) else { return nil }
                    return mapVolume(status)
                }
                .removeDuplicates()
                .sink { [weak self] state in
                    guard let self, isVisible(.volume) else { return }
                    publishVolume(state)
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
            publishAudioInput(AudioPanelMapper.input(store.liveInput, localization: localization))
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
            let batteryState = PanelPresentationMapper.battery(snapshot.battery, localization: localization)
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
        if store.batteryDetails.isActive { refreshBatteryDetails(status: snapshot.battery) }
        if store.wifiNetworks.isActive { refreshWiFiDetails(status: snapshot.wifi) }
    }

    private func refreshBatteryDetails(status deliveredStatus: BatteryStatus? = nil) {
        guard store.batteryDetails.isActive else { return }
        let state = PanelDetailMapper.battery(
            status: deliveredStatus ?? store.popupSnapshot.battery,
            details: store.batteryDetails.details,
            localization: localization
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
                publishAudioInput(AudioPanelMapper.input(store.liveInput, localization: localization))
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

    private func publishVolume(_ state: VolumePanelState) {
        if listeningModeTaskID != state.listeningModeTaskID {
            listeningModeTaskID = state.listeningModeTaskID
        }
        guard volume != state else { return }
        volume = state
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
            muted: muted,
            canAdjust: canAdjust,
            canMute: canMute,
            muteSymbol: muteSymbol,
            muteHelp: muteHelp,
            sliderLabel: sliderLabel,
            showsDeviceList: false,
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
            muted: muted,
            canAdjust: false,
            canMute: false,
            muteSymbol: muteSymbol,
            muteHelp: muteHelp,
            sliderLabel: sliderLabel,
            showsDeviceList: false,
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
