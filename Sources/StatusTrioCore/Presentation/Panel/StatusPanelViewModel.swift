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
    }
    @Published private(set) var battery: PanelSummaryState
    @Published private(set) var network: PanelSummaryState
    @Published private(set) var vpn: PanelSummaryState
    @Published private(set) var bluetooth: BluetoothPanelState
    @Published private(set) var bluetoothListeningModeRows: [String: BluetoothListeningModePresentation] = [:]
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
    let actions: StatusPanelActions
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false
    private var bluetoothIsExpanded = false
    private var pendingRefreshRegions: RefreshRegions = []
    private var lifecycleGeneration = 0

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        actions: StatusPanelActions,
        updateScheduler: any PanelPresentationUpdateScheduling = YieldingPanelPresentationUpdateScheduler(),
        inputSourceController: InputSourceController? = nil
    ) {
        let resolvedInputSourceController = inputSourceController ?? InputSourceController()
        self.store = store
        self.settings = settings
        self.localization = localization
        self.inputSourceController = resolvedInputSourceController
        self.updateScheduler = updateScheduler
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
        refreshAll()

        store.$popupSnapshot
            .combineLatest(store.$isNetworkConstrained, store.$isResolvingWiFiName)
            .sink { [weak self] snapshot, isConstrained, isResolvingName in
                self?.refreshPopupPanels(
                    snapshot: snapshot,
                    isConstrained: isConstrained,
                    isResolvingName: isResolvingName
                )
            }
            .store(in: &cancellables)
        store.$vpnStatus
            .map { [weak self] status -> PanelSummaryState? in
                guard let self else { return nil }
                return mapVPN(status)
            }
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] in self?.publishVPN($0) }
            .store(in: &cancellables)
        store.$liveVolume
            .compactMap { [weak self] status -> VolumePanelState? in
                guard let self else { return nil }
                return mapVolume(status)
            }
            .removeDuplicates()
            .sink { [weak self] in self?.publishVolume($0) }
            .store(in: &cancellables)
        store.$liveInput
            .map { [weak self] status -> AudioInputPanelState? in
                guard let self else { return nil }
                return mapInput(status)
            }
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] in self?.publishAudioInput($0) }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            inputSourceController.$state,
            inputSourceController.$selectionFailure
        )
        .sink { [weak self] state, failure in
            self?.publishInputSource(state: state, failure: failure)
        }
        .store(in: &cancellables)

        store.batteryDetails.$details
            .dropFirst()
            .sink { [weak self] _ in self?.coalesceControllerUpdate(.batteryDetails) }
            .store(in: &cancellables)
        store.wifiNetworks.objectWillChange
            .sink { [weak self] in self?.coalesceControllerUpdate(.wifiDetails) }
            .store(in: &cancellables)
        store.primaryLink.$details
            .dropFirst()
            .sink { [weak self] _ in self?.coalesceControllerUpdate(.wiredDetailsAndNetwork) }
            .store(in: &cancellables)
        store.localIP.$details
            .dropFirst()
            .sink { [weak self] _ in self?.coalesceControllerUpdate(.localIP) }
            .store(in: &cancellables)
        store.bluetoothDevices.objectWillChange
            .sink { [weak self] in self?.coalesceControllerUpdate([.bluetooth, .volume]) }
            .store(in: &cancellables)
        store.bluetoothListeningModes.$presentations
            .dropFirst()
            .sink { [weak self] _ in self?.coalesceControllerUpdate([.bluetooth, .volume]) }
            .store(in: &cancellables)

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
        cancellables.removeAll()
    }

    func setBluetoothExpanded(_ expanded: Bool) {
        guard bluetoothIsExpanded != expanded else { return }
        bluetoothIsExpanded = expanded
        refreshBluetooth()
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
        let modeRows = store.bluetoothListeningModes.huaweiBluetoothRowPresentations
        if bluetoothListeningModeRows != modeRows { bluetoothListeningModeRows = modeRows }
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
            listeningModeTaskID: listeningModeTaskID(outputDevices: status.outputDevices),
            previewDevices: ListeningModePreview.outputRows(for: previewConfiguration, volume: status.scalar),
            previewLanguageCode: previewConfiguration.languageCode,
            previewLocalization: PreviewLocalization.forCode(previewConfiguration.languageCode),
            localization: localization
        )
    }

    private var currentPreviewConfiguration: ListeningModePreview.Configuration {
        ListeningModePreview.Configuration(
            isEnabled: settings.previewsBluetoothListeningMode,
            deviceName: settings.bluetoothListeningModePreviewDeviceName,
            deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
            languageCode: settings.bluetoothListeningModePreviewLanguage
        )
    }

    private func listeningModeTaskID(outputDevices: [AudioOutputDevice]) -> String {
        let configuration = ListeningModePreview.Configuration(
            isEnabled: settings.previewsBluetoothListeningMode,
            deviceName: settings.bluetoothListeningModePreviewDeviceName,
            deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
            languageCode: settings.bluetoothListeningModePreviewLanguage
        )
        let connected = BluetoothDevicePresentation.grouped(store.bluetoothDevices.devices).connected
            .filter { $0.isAirPods || $0.isHuaweiAudio }
            .map { BluetoothBatteryReader.normalizedAddress($0.id) }
            .joined(separator: ",")
        let preview = configuration.isEnabled ? "|preview" : ""
        let synthetic = ListeningModePreview.devices(for: configuration)
            .map { BluetoothBatteryReader.normalizedAddress($0.id) }
            .joined(separator: ",")
        let outputs = outputDevices.map { String($0.id) }.joined(separator: ",")
        return connected + preview + (synthetic.isEmpty ? "" : "|\(synthetic)") + "|outputs:\(outputs)"
    }

    private func mapInput(_ status: AudioInputStatus) -> AudioInputPanelState? {
        AudioPanelMapper.input(status, localization: localization)
    }

    private func refreshAll() {
        let sections = settings.visiblePopupSections
        if visiblePopupSections != sections { visiblePopupSections = sections }
        refreshPopupPanels()
        publishVPN(PanelPresentationMapper.vpn(store.vpnStatus, localization: localization))
        refreshBluetooth()
        publishVolume(mapVolume(store.liveVolume))
        publishAudioInput(AudioPanelMapper.input(store.liveInput, localization: localization))
        publishInputSource(
            state: inputSourceController.state,
            failure: inputSourceController.selectionFailure
        )
        refreshBatteryDetails()
        refreshWiFiDetails()
        refreshWiredDetailsAndNetwork()
    }

    private func refreshPopupPanels(
        snapshot deliveredSnapshot: StatusSnapshot? = nil,
        isConstrained deliveredConstraint: Bool? = nil,
        isResolvingName deliveredResolutionState: Bool? = nil
    ) {
        let snapshot = deliveredSnapshot ?? store.popupSnapshot
        let isConstrained = deliveredConstraint ?? store.isNetworkConstrained
        let isResolvingName = deliveredResolutionState ?? store.isResolvingWiFiName
        let batteryState = PanelPresentationMapper.battery(snapshot.battery, localization: localization)
        if battery != batteryState { battery = batteryState }
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
        let detailsState = PanelDetailMapper.battery(
            status: snapshot.battery,
            details: store.batteryDetails.details,
            localization: localization
        )
        if batteryDetails != detailsState { batteryDetails = detailsState }
        refreshWiFiDetails(status: snapshot.wifi)
    }

    private func refreshBatteryDetails() {
        let state = PanelDetailMapper.battery(
            status: store.popupSnapshot.battery,
            details: store.batteryDetails.details,
            localization: localization
        )
        if batteryDetails != state { batteryDetails = state }
    }

    private func refreshWiFiDetails(status deliveredStatus: WiFiStatus? = nil) {
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
        let wiredState = PanelDetailMapper.wired(details: store.primaryLink.details, localization: localization)
        if wiredDetails != wiredState { wiredDetails = wiredState }
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
            if regions.contains(.batteryDetails) { refreshBatteryDetails() }
            if regions.contains(.wifiDetails) { refreshWiFiDetails() }
            if regions.contains(.wiredDetailsAndNetwork) { refreshWiredDetailsAndNetwork() }
            if regions.contains(.bluetooth) { refreshBluetooth() }
            if regions.contains(.volume) { publishVolume(mapVolume(store.liveVolume)) }
            if regions.contains(.localIP) { refreshWiredDetailsAndNetwork() }
        }
    }

    private func publishVPN(_ state: PanelSummaryState?) {
        guard let state, vpn != state else { return }
        vpn = state
    }

    private func publishVolume(_ state: VolumePanelState) {
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
