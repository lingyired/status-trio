import CoreAudio
import Foundation

@MainActor
final class StatusPanelActions {
    private let outputDevices: () -> [AudioOutputDevice]
    private let selectOutputDevice: (AudioOutputDevice) -> Void
    private let inputDevices: () -> [AudioInputDevice]
    private let selectInputDevice: (AudioInputDevice) -> Void
    private let setVolumeCommand: (Double) -> Void
    private let finishVolumeCommand: () -> Void
    private let toggleMuteCommand: () -> Void
    private let setInputScalarCommand: (Double) -> Void
    private let toggleInputMuteCommand: () -> Void
    private let outputPreferences: () -> AudioOutputListPreferences
    private let bluetoothDevices: () -> [BluetoothDevice]
    private let bluetoothAvailability: () -> BluetoothAvailability
    private let refreshBluetoothCommand: () -> Void
    private let requestBluetoothAuthorizationCommand: () -> Void
    private let openBluetoothPermissionSettingsCommand: () -> Void
    private let performBluetoothActionCommand: (BluetoothDevice) -> Void
    private let requestDisconnectCommand: (BluetoothDevice) -> Void
    private let disconnectConfirmationAddress: () -> String?
    private let cancelDisconnectCommand: () -> Void
    private let requestBatteryLevelsCommand: (String) -> Void
    private let releaseBatteryLevelsCommand: (String) -> Void
    private let requestNearbyBatteryDevicesCommand: (String) -> Void
    private let releaseNearbyBatteryDevicesCommand: (String, Bool) -> Void
    private let setListeningModeCommand: (BluetoothListeningMode, String) -> Void
    private let listeningModePresentations: () -> [String: BluetoothListeningModePresentation]
    private let listeningModeDevices: () -> [BluetoothDevice]
    private let batteryStatus: () -> BatteryStatus
    private let activateBatteryDetails: (BatteryPowerState) -> Void
    private let closeBatteryDetails: () -> Void
    private let wifiNameAccess: () -> WiFiNameAccess
    private let activateWiFiDetails: (WiFiNameAccess) -> Void
    private let closeWiFiDetails: () -> Void
    private let setWiFiPowerCommand: (Bool) -> Void
    private let refreshWiFiCommand: (WiFiNameAccess) -> Void
    private let openWiredDetails: () -> Void
    private let closeWiredDetails: () -> Void
    private let holdBluetoothSummary: () -> Void
    private let releaseBluetoothSummary: () -> Void
    private let refreshVolumeListeningModes: () -> Void
    private let stopVolumeListeningModes: () -> Void

    private static let summaryBatteryLevelsToken = "bluetooth.summary"
    private static let nearbyBatteryDevicesToken = "bluetooth.summary.nearbyBatteryDevices"

    var outputDeviceListPreferences: AudioOutputListPreferences {
        outputPreferences()
    }

    /// Narrow injection keeps command routing testable without introducing a
    /// second monitor abstraction around the existing store.
    init(
        outputDevices: @escaping () -> [AudioOutputDevice] = { [] },
        selectOutput: @escaping (AudioOutputDevice) -> Void = { _ in },
        inputDevices: @escaping () -> [AudioInputDevice] = { [] },
        selectInput: @escaping (AudioInputDevice) -> Void = { _ in },
        setVolume: @escaping (Double) -> Void = { _ in },
        finishVolumeAdjustment: @escaping () -> Void = {},
        toggleMute: @escaping () -> Void = {},
        setInputScalar: @escaping (Double) -> Void = { _ in },
        toggleInputMute: @escaping () -> Void = {},
        outputPreferences: @escaping () -> AudioOutputListPreferences = { .default },
        bluetoothDevices: @escaping () -> [BluetoothDevice] = { [] },
        bluetoothAvailability: @escaping () -> BluetoothAvailability = { .idle },
        refreshBluetooth: @escaping () -> Void = {},
        requestBluetoothAuthorization: @escaping () -> Void = {},
        openBluetoothPermissionSettings: @escaping () -> Void = {},
        performBluetoothAction: @escaping (BluetoothDevice) -> Void = { _ in },
        requestDisconnect: @escaping (BluetoothDevice) -> Void = { _ in },
        disconnectConfirmationAddress: @escaping () -> String? = { nil },
        cancelDisconnect: @escaping () -> Void = {},
        requestBatteryLevels: @escaping (String) -> Void = { _ in },
        releaseBatteryLevels: @escaping (String) -> Void = { _ in },
        requestNearbyBatteryDevices: @escaping (String) -> Void = { _ in },
        releaseNearbyBatteryDevices: @escaping (String, Bool) -> Void = { _, _ in },
        setListeningMode: @escaping (BluetoothListeningMode, String) -> Void = { _, _ in },
        listeningModePresentations: @escaping () -> [String: BluetoothListeningModePresentation] = { [:] },
        listeningModeDevices: (() -> [BluetoothDevice])? = nil,
        batteryStatus: @escaping () -> BatteryStatus = { .placeholder },
        activateBatteryDetails: @escaping (BatteryPowerState) -> Void = { _ in },
        closeBatteryDetails: @escaping () -> Void = {},
        wifiNameAccess: @escaping () -> WiFiNameAccess = { .notDetermined },
        activateWiFiDetails: @escaping (WiFiNameAccess) -> Void = { _ in },
        closeWiFiDetails: @escaping () -> Void = {},
        setWiFiPower: @escaping (Bool) -> Void = { _ in },
        refreshWiFi: @escaping (WiFiNameAccess) -> Void = { _ in },
        openWiredDetails: @escaping () -> Void = {},
        closeWiredDetails: @escaping () -> Void = {},
        holdBluetoothSummary: @escaping () -> Void = {},
        releaseBluetoothSummary: @escaping () -> Void = {},
        refreshVolumeListeningModes: @escaping () -> Void = {},
        stopVolumeListeningModes: @escaping () -> Void = {}
    ) {
        self.outputDevices = outputDevices
        self.selectOutputDevice = selectOutput
        self.inputDevices = inputDevices
        self.selectInputDevice = selectInput
        self.setVolumeCommand = setVolume
        self.finishVolumeCommand = finishVolumeAdjustment
        self.toggleMuteCommand = toggleMute
        self.setInputScalarCommand = setInputScalar
        self.toggleInputMuteCommand = toggleInputMute
        self.outputPreferences = outputPreferences
        self.bluetoothDevices = bluetoothDevices
        self.bluetoothAvailability = bluetoothAvailability
        self.refreshBluetoothCommand = refreshBluetooth
        self.requestBluetoothAuthorizationCommand = requestBluetoothAuthorization
        self.openBluetoothPermissionSettingsCommand = openBluetoothPermissionSettings
        self.performBluetoothActionCommand = performBluetoothAction
        self.requestDisconnectCommand = requestDisconnect
        self.disconnectConfirmationAddress = disconnectConfirmationAddress
        self.cancelDisconnectCommand = cancelDisconnect
        self.requestBatteryLevelsCommand = requestBatteryLevels
        self.releaseBatteryLevelsCommand = releaseBatteryLevels
        self.requestNearbyBatteryDevicesCommand = requestNearbyBatteryDevices
        self.releaseNearbyBatteryDevicesCommand = releaseNearbyBatteryDevices
        self.setListeningModeCommand = setListeningMode
        self.listeningModePresentations = listeningModePresentations
        self.listeningModeDevices = listeningModeDevices ?? bluetoothDevices
        self.batteryStatus = batteryStatus
        self.activateBatteryDetails = activateBatteryDetails
        self.closeBatteryDetails = closeBatteryDetails
        self.wifiNameAccess = wifiNameAccess
        self.activateWiFiDetails = activateWiFiDetails
        self.closeWiFiDetails = closeWiFiDetails
        self.setWiFiPowerCommand = setWiFiPower
        self.refreshWiFiCommand = refreshWiFi
        self.openWiredDetails = openWiredDetails
        self.closeWiredDetails = closeWiredDetails
        self.holdBluetoothSummary = holdBluetoothSummary
        self.releaseBluetoothSummary = releaseBluetoothSummary
        self.refreshVolumeListeningModes = refreshVolumeListeningModes
        self.stopVolumeListeningModes = stopVolumeListeningModes
    }

    convenience init(store: SystemStatusStore, settings: SettingsStore) {
        self.init(
            outputDevices: { store.liveVolume.outputDevices },
            selectOutput: { device in store.selectOutputDevice(device) },
            inputDevices: { store.liveInput.devices },
            selectInput: { device in store.selectInputDevice(device.id) },
            setVolume: { scalar in store.setVolume(scalar) },
            finishVolumeAdjustment: { store.finishVolumeAdjustment() },
            toggleMute: { store.toggleMute() },
            setInputScalar: { scalar in store.setInputScalar(scalar) },
            toggleInputMute: { store.toggleInputMute() },
            outputPreferences: {
                AudioOutputListPreferences(
                    order: settings.outputDeviceOrder,
                    visibleLimit: settings.visibleOutputDeviceLimit
                )
            },
            bluetoothDevices: { store.bluetoothDevices.devices },
            bluetoothAvailability: { store.bluetoothDevices.availability },
            refreshBluetooth: { store.bluetoothDevices.refreshFromUser() },
            requestBluetoothAuthorization: { store.requestBluetoothAuthorization() },
            openBluetoothPermissionSettings: { store.openBluetoothPermissionSettings() },
            performBluetoothAction: { store.bluetoothDevices.performDeviceAction(for: $0) },
            requestDisconnect: { store.bluetoothDevices.requestDisconnectConfirmation(for: $0) },
            disconnectConfirmationAddress: { store.bluetoothDevices.pendingDisconnectConfirmation },
            cancelDisconnect: { store.bluetoothDevices.cancelDisconnectConfirmation() },
            requestBatteryLevels: { store.bluetoothDevices.requestBatteryLevels($0) },
            releaseBatteryLevels: { store.bluetoothDevices.releaseBatteryLevels($0) },
            requestNearbyBatteryDevices: { store.bluetoothDevices.requestNearbyBatteryDevices($0) },
            releaseNearbyBatteryDevices: { store.bluetoothDevices.releaseNearbyBatteryDevices($0, keepingResults: $1) },
            setListeningMode: { store.bluetoothListeningModes.setMode($0, forAddress: $1) },
            listeningModePresentations: { store.bluetoothListeningModes.presentations },
            listeningModeDevices: {
                let config = ListeningModePreview.Configuration(
                    isEnabled: settings.previewsBluetoothListeningMode,
                    deviceName: settings.bluetoothListeningModePreviewDeviceName,
                    deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
                    languageCode: settings.bluetoothListeningModePreviewLanguage
                )
                return store.bluetoothDevices.devices + ListeningModePreview.devices(for: config)
            },
            batteryStatus: { store.popupSnapshot.battery },
            activateBatteryDetails: { store.batteryDetails.activate(state: $0) },
            closeBatteryDetails: { store.batteryDetails.deactivate() },
            wifiNameAccess: { store.popupSnapshot.wifi.nameAccess },
            activateWiFiDetails: { store.wifiNetworks.activate(nameAccess: $0) },
            closeWiFiDetails: { store.wifiNetworks.deactivate() },
            setWiFiPower: { store.wifiNetworks.setPower($0) },
            refreshWiFi: { store.wifiNetworks.refreshNow(nameAccess: $0) },
            openWiredDetails: { store.activatePrimaryLinkPanel() },
            closeWiredDetails: { store.closePrimaryLinkPanel() },
            holdBluetoothSummary: { store.bluetoothDevices.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken) },
            releaseBluetoothSummary: { store.bluetoothDevices.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken) },
            refreshVolumeListeningModes: {
                let config = ListeningModePreview.Configuration(
                    isEnabled: settings.previewsBluetoothListeningMode,
                    deviceName: settings.bluetoothListeningModePreviewDeviceName,
                    deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
                    languageCode: settings.bluetoothListeningModePreviewLanguage
                )
                store.bluetoothListeningModes.previewMode = config.isEnabled
                store.bluetoothListeningModes.refresh(
                    devices: store.bluetoothDevices.devices + ListeningModePreview.devices(for: config)
                )
            },
            stopVolumeListeningModes: { store.bluetoothListeningModes.stop() }
        )
    }

    func setVolume(_ scalar: Double) {
        guard scalar.isFinite else { return }
        setVolumeCommand(min(1, max(0, scalar)))
    }

    func finishVolumeAdjustment() {
        finishVolumeCommand()
    }

    func toggleMute() {
        toggleMuteCommand()
    }

    func selectOutput(_ key: PanelAudioDeviceID) {
        guard let device = outputDevices().first(where: {
            $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
        }) else { return }
        selectOutputDevice(device)
    }

    func setInputScalar(_ scalar: Double) {
        guard scalar.isFinite else { return }
        setInputScalarCommand(min(1, max(0, scalar)))
    }

    func toggleInputMute() {
        toggleInputMuteCommand()
    }

    func selectInput(_ key: PanelAudioDeviceID) {
        guard let device = inputDevices().first(where: {
            $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
        }) else { return }
        selectInputDevice(device)
    }

    func refreshBluetooth() { refreshBluetoothCommand() }
    func requestBluetoothAuthorization() { requestBluetoothAuthorizationCommand() }
    func openBluetoothPermissionSettings() { openBluetoothPermissionSettingsCommand() }

    func performBluetoothAction(address: String) {
        guard let device = bluetoothDevice(address: address),
              BluetoothDeviceActionPolicy.isActionable(device),
              !BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        performBluetoothActionCommand(device)
    }

    func rowTapped(address: String) {
        guard let device = bluetoothDevice(address: address),
              BluetoothDeviceActionPolicy.isActionable(device) else { return }
        if BluetoothDeviceActionPolicy.requiresConfirmation(for: device) {
            requestDisconnectCommand(device)
        } else {
            performBluetoothActionCommand(device)
        }
    }

    func confirmBluetoothDisconnect(address: String) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty,
              BluetoothBatteryReader.normalizedAddress(disconnectConfirmationAddress() ?? "") == key,
              let device = bluetoothDevice(address: key),
              BluetoothDeviceActionPolicy.isActionable(device),
              BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        performBluetoothActionCommand(device)
    }

    func requestDisconnect(address: String) {
        guard let device = bluetoothDevice(address: address),
              BluetoothDeviceActionPolicy.isActionable(device),
              BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        requestDisconnectCommand(device)
    }

    func cancelDisconnect() { cancelDisconnectCommand() }

    func updateBluetoothBatteryLevelsClaim(enabled: Bool) {
        guard enabled,
              BluetoothSummary.presentation(
                availability: bluetoothAvailability(),
                devices: bluetoothDevices(),
                batteryLevels: [:]
              ).hasConnectedDevices else {
            releaseBatteryLevelsCommand(Self.summaryBatteryLevelsToken)
            return
        }
        requestBatteryLevelsCommand(Self.summaryBatteryLevelsToken)
    }

    func updateBluetoothNearbyBatteryClaim(enabled: Bool) {
        if enabled {
            requestNearbyBatteryDevicesCommand(Self.nearbyBatteryDevicesToken)
        } else {
            releaseNearbyBatteryDevicesCommand(Self.nearbyBatteryDevicesToken, false)
        }
    }

    func setListeningMode(address: String, mode: BluetoothListeningMode) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty,
              listeningModeDevices().contains(where: {
                  BluetoothBatteryReader.normalizedAddress($0.id) == key
                      && BluetoothDeviceActionPolicy.isActionable($0)
              }),
              let presentation = listeningModePresentations()[key],
              presentation.availableModes.contains(mode) else { return }
        setListeningModeCommand(mode, key)
    }

    func batteryDetailsAppeared() { activateBatteryDetails(BatteryPowerState(batteryStatus())) }
    func batteryDetailsClosed() { closeBatteryDetails() }
    func wifiDetailsOpened() { activateWiFiDetails(wifiNameAccess()) }
    func wifiDetailsClosed() { closeWiFiDetails() }
    func wiredDetailsOpened() { openWiredDetails() }
    func wiredDetailsClosed() { closeWiredDetails() }
    func bluetoothSummaryAppeared() { holdBluetoothSummary() }

    func bluetoothSummaryDisappeared() {
        releaseBluetoothSummary()
        releaseBatteryLevelsCommand(Self.summaryBatteryLevelsToken)
        releaseNearbyBatteryDevicesCommand(Self.nearbyBatteryDevicesToken, true)
    }

    func volumeListAppeared() { refreshVolumeListeningModes() }

    /// Called by the list task when connected-device membership or preview
    /// configuration changes; listening-mode discovery has no timer.
    func volumeListChanged() { refreshVolumeListeningModes() }
    func volumeListDisappeared() { stopVolumeListeningModes() }
    func setWiFiPower(_ enabled: Bool) { setWiFiPowerCommand(enabled) }
    func refreshWiFi() { refreshWiFiCommand(wifiNameAccess()) }
    private func bluetoothDevice(address: String) -> BluetoothDevice? {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { return nil }
        return bluetoothDevices().first { BluetoothBatteryReader.normalizedAddress($0.id) == key }
    }
}
