import AppKit
import AudioToolbox
import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    static let popupDebounceInterval: Duration = .milliseconds(500)

    /// The fallback poll refreshes the battery on every tick: its percentage and
    /// charging state are drawn into the menu bar icon and cannot go stale.
    /// Wi-Fi and volume have push channels (CoreWLAN events, the network path
    /// monitor, CoreAudio property listeners) and are drawn into the same icon,
    /// so while neither the popover nor the Settings window is open they are
    /// refreshed every fourth tick as a watchdog against a missed event. Four
    /// ticks are 60 seconds at the default interval, 20 at the 5-second minimum
    /// and 240 at the 60-second maximum, next to a push path that has already
    /// reported every change it saw.
    static let hiddenFallbackTickStride = 4

    /// How many consecutive fallback ticks the display-asleep flag may skip
    /// before one tick runs anyway. A display-only sleep (screen saver, the
    /// display-sleep timer, or a Mac whose system sleep is off) is cleared only
    /// by `screensDidWakeNotification`; if that single notification is lost, an
    /// unbounded skip would freeze the battery reading drawn into the menu bar
    /// icon for the rest of the session. Twenty ticks are five minutes at the
    /// default interval, so a lost notification costs at most one refresh per
    /// cap.
    static let maximumDisplayAsleepSkips = 20

    /// Tolerance for the fallback poll. Without one, macOS must wake the CPU on
    /// an exact schedule to satisfy the timer, which is exactly what an idle
    /// menu bar app should not ask for; a fifth of the interval still samples
    /// often enough for a value that the push channels did not report.
    static func refreshSleepTolerance(for interval: Duration) -> Duration {
        interval / 5
    }

    @Published private(set) var snapshot: StatusSnapshot
    @Published private(set) var popupSnapshot: StatusSnapshot
    /// The VPN row's value. Deliberately not part of `StatusSnapshot`: nothing
    /// in the menu bar or the Dock icon draws it, and folding it in would put a
    /// third signal on the snapshot's equality path for no rendering gain.
    @Published private(set) var vpnStatus: VPNStatus
    /// True while the popover is waiting for a Wi-Fi name it has not read yet.
    @Published private(set) var isResolvingWiFiName = false
    /// Whether the system marks the current path as bandwidth-restricted.
    /// Read from `NWPath.isConstrained` and shown on the network row. It stays
    /// out of `StatusSnapshot` on purpose: nothing draws it, so the icon render
    /// keys should not gain a signal for a popover-only label.
    @Published private(set) var isNetworkConstrained = false
    @Published private(set) var liveVolume: VolumeStatus
    @Published private(set) var liveInput = AudioInputStatus.empty
    let batteryDetails: BatteryDetailsController
    let wifiNetworks: WiFiNetworkController
    /// The wired link's address configuration. Read while the popover is open on
    /// an Ethernet connection and dropped when either stops being true, so the
    /// row never shows the address of a link the user has left.
    let primaryLink: PrimaryLinkController
    let bluetoothDevices: BluetoothDeviceController
    let mobileBattery: MobileBatteryController
    let appleDeviceDiscovery: AppleDeviceDiscoveryController
    /// The AirPods listening-mode surface. A separate owner from `bluetoothDevices`
    /// (the plan's Option B): its own discovery/write lifecycle, so the delicate
    /// paired-device controller is not widened by it. The Bluetooth view drives it
    /// from the same appear/disappear and refresh hooks the device list uses.
    let bluetoothListeningModes: BluetoothListeningModeController

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let connectionMonitor: (any NetworkConnectionMonitoring)?
    private let vpnMonitor: (any VPNMonitoring)?
    private let volumeMonitor: any VolumeMonitoring
    private let inputMonitor: (any AudioInputMonitoring)?
    private let volumeController: (any VolumeControlling)?
    private let volumeFeedback: (any VolumeFeedbackPlaying)?
    private var refreshInterval: Duration
    private let nameResolutionTimeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let popupDebounceSleep: @Sendable (Duration) async throws -> Void
    private let wakeNotificationCenter: NotificationCenter
    private var monitorTasks: [Task<Void, Never>] = []
    private var vpnUpdateTask: Task<Void, Never>?
    private var isVPNActiveForPopover = false
    private var inputUpdateTask: Task<Void, Never>?
    private var inputSettingsCancellable: AnyCancellable?
    private var mobileBatterySettingsCancellable: AnyCancellable?
    private var appleDeviceSettingsCancellable: AnyCancellable?
    private var appleBackgroundSettingsCancellable: AnyCancellable?
    private var appleEligibilitySettingsCancellable: AnyCancellable?
    private var nearbyBLESettingsCancellables: Set<AnyCancellable> = []
    private var inputSettingEnabled = false
    private var isInputEnabled = false
    private var refreshTask: Task<Void, Never>?
    private var fallbackTickCount = 0
    /// Consecutive fallback ticks skipped because the display was asleep. Reset
    /// by either wake notification and whenever a tick actually runs, so
    /// `maximumDisplayAsleepSkips` bounds how long a lost display-wake
    /// notification can stop the poll.
    private var displayAsleepSkipCount = 0
    private var popupPublishTask: Task<Void, Never>?
    private var wifiNameResolutionTask: Task<Void, Never>?
    /// Teardown-owned notification registrations.
    ///
    /// `deinit` is nonisolated, so these are `nonisolated(unsafe)`: they are only
    /// ever mutated on the main actor while the store is alive, and the one
    /// operation the teardown performs on them —
    /// `NotificationCenter.removeObserver(_:)` — is safe to call from any
    /// thread. This mirrors the existing `wakeObserver` pattern and avoids
    /// `MainActor.assumeIsolated`, which is a fatal assertion rather than a hop
    /// if the last reference is released off the main thread.
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var systemSleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var displaySleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var displayWakeObserver: NSObjectProtocol?
    private var lastPublishedSnapshot: StatusSnapshot?
    private var hasStarted = false
    private var hasStopped = false
    @Published private(set) var isPopoverVisible = false
    @Published private(set) var trustedAppleDeviceCandidates: [AppleDeviceCandidate] = []
    @Published private(set) var trustedAppleDeviceDiscoveryGeneration: UInt64 = 0
    /// True while the display is asleep. The fallback poll skips its work then,
    /// because no menu bar or Dock tile is on screen to keep fresh.
    @Published private(set) var isDisplayAsleep = false
    private var isSettingsVisible = false
    private var isBluetoothEnabled = false
    private var isBluetoothActivatedForPopover = false
    /// Whether the wired link panel is the open detail panel. The controller
    /// itself follows the connection; this only records that the panel is on
    /// screen, which is what decides whether the built popover content can be
    /// kept for a rapid reopen.
    private var isPrimaryLinkPanelOpen = false

    init(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        vpnMonitor: (any VPNMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        inputMonitor: (any AudioInputMonitoring)? = nil,
        volumeFeedback: (any VolumeFeedbackPlaying)? = VolumeFeedbackPlayer(),
        refreshInterval: Duration = .seconds(15),
        nameResolutionTimeout: Duration = .milliseconds(1500),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { interval in
            try await Task.sleep(
                for: interval,
                tolerance: SystemStatusStore.refreshSleepTolerance(for: interval)
            )
        },
        popupDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        batteryDetails: BatteryDetailsController = BatteryDetailsController(),
        wifiNetworks: WiFiNetworkController = WiFiNetworkController(),
        primaryLink: PrimaryLinkController = PrimaryLinkController(),
        bluetoothDevices: BluetoothDeviceController = BluetoothDeviceController(),
        mobileBattery: MobileBatteryController = MobileBatteryController(),
        appleDeviceDiscovery: AppleDeviceDiscoveryController = AppleDeviceDiscoveryController(),
        bluetoothListeningModes: BluetoothListeningModeController = BluetoothListeningModeController(),
        initialSnapshot: StatusSnapshot = .placeholder
    ) {
        self.batteryMonitor = batteryMonitor
        self.wifiMonitor = wifiMonitor
        self.connectionMonitor = connectionMonitor
        self.vpnMonitor = vpnMonitor
        self.volumeMonitor = volumeMonitor
        self.inputMonitor = inputMonitor
        self.volumeController = volumeMonitor as? any VolumeControlling
        self.volumeFeedback = volumeFeedback
        self.refreshInterval = refreshInterval
        self.nameResolutionTimeout = nameResolutionTimeout
        self.sleep = sleep
        self.popupDebounceSleep = popupDebounceSleep
        self.wakeNotificationCenter = wakeNotificationCenter
        self.batteryDetails = batteryDetails
        self.wifiNetworks = wifiNetworks
        self.primaryLink = primaryLink
        self.bluetoothDevices = bluetoothDevices
        self.mobileBattery = mobileBattery
        self.appleDeviceDiscovery = appleDeviceDiscovery
        self.bluetoothListeningModes = bluetoothListeningModes
        self.snapshot = initialSnapshot
        self.popupSnapshot = initialSnapshot
        self.vpnStatus = .placeholder
        self.liveVolume = initialSnapshot.volume
    }

    deinit {
        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
        }
        if let systemSleepObserver {
            wakeNotificationCenter.removeObserver(systemSleepObserver)
        }
        if let displaySleepObserver {
            wakeNotificationCenter.removeObserver(displaySleepObserver)
        }
        if let displayWakeObserver {
            wakeNotificationCenter.removeObserver(displayWakeObserver)
        }
        monitorTasks.forEach { $0.cancel() }
        inputUpdateTask?.cancel()
        refreshTask?.cancel()
        popupPublishTask?.cancel()
    }

    func start() {
        guard !hasStarted, !hasStopped else { return }
        hasStarted = true
        wifiMonitor.setDetailsVisible(false)
        volumeMonitor.setDetailsVisible(false)

        wakeObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Either wake notification self-heals the flag: a wake cycle
                // that delivers only this one must not leave the fallback poll
                // disabled for the rest of the session. A dark or network wake
                // can fire with the display still off, so the poll resumes
                // until the next display-sleep notification; bounded
                // over-polling is the safe direction, permanent staleness is
                // not.
                self.isDisplayAsleep = false
                self.bluetoothDevices.setSystemSleeping(false)
                self.volumeMonitor.setDisplayAsleep(false)
                self.displayAsleepSkipCount = 0
                self.recoverAll()
                self.refreshAll()
            }
        }

        systemSleepObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bluetoothDevices.setSystemSleeping(true)
            }
        }

        displaySleepObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplayAsleep = true
                self?.volumeMonitor.setDisplayAsleep(true)
            }
        }

        displayWakeObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isDisplayAsleep = false
                self.volumeMonitor.setDisplayAsleep(false)
                self.displayAsleepSkipCount = 0
                self.recoverAll()
                self.refreshAll()
            }
        }

        batteryMonitor.start()
        wifiMonitor.start()
        connectionMonitor?.start()
        volumeMonitor.start()

        if let inputMonitor {
            let inputUpdates = inputMonitor.updates
            inputUpdateTask = Task { [weak self] in
                for await value in inputUpdates {
                    guard let self else { return }
                    self.applyInput(value)
                }
            }
            inputMonitor.setEnabled(inputSettingEnabled)
            isInputEnabled = inputSettingEnabled
            if inputSettingEnabled {
                inputMonitor.setVisible(isPopoverVisible)
            }
        }

        let batteryUpdates = batteryMonitor.updates
        let wifiUpdates = wifiMonitor.updates
        let connectionUpdates = connectionMonitor?.updates
        let volumeUpdates = volumeMonitor.updates
        var tasks = [
            Task { [weak self] in
                for await value in batteryUpdates {
                    guard let self else { return }
                    self.applyBattery(value)
                }
            },
            Task { [weak self] in
                for await value in wifiUpdates {
                    guard let self else { return }
                    self.applyWiFi(value)
                }
            },
            Task { [weak self] in
                for await value in volumeUpdates {
                    guard let self else { return }
                    self.applyVolume(value)
                }
            }
        ]
        if let connectionUpdates {
            tasks.append(Task { [weak self] in
                for await value in connectionUpdates {
                    guard let self else { return }
                    self.applyConnection(value)
                }
            })
        }
        monitorTasks = tasks

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let sleep = self?.sleep, let interval = self?.refreshInterval else { return }
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.fallbackRefreshTick()
            }
        }
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        isInputEnabled = false
        inputSettingsCancellable?.cancel()
        inputSettingsCancellable = nil
        mobileBatterySettingsCancellable?.cancel()
        mobileBatterySettingsCancellable = nil
        appleDeviceSettingsCancellable?.cancel()
        appleDeviceSettingsCancellable = nil
        appleBackgroundSettingsCancellable?.cancel()
        appleBackgroundSettingsCancellable = nil
        appleEligibilitySettingsCancellable?.cancel()
        appleEligibilitySettingsCancellable = nil
        nearbyBLESettingsCancellables.removeAll()
        inputUpdateTask?.cancel()
        inputUpdateTask = nil
        inputMonitor?.stop()
        stopVPNMonitoringForPopover()

        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let systemSleepObserver {
            wakeNotificationCenter.removeObserver(systemSleepObserver)
            self.systemSleepObserver = nil
        }
        if let displaySleepObserver {
            wakeNotificationCenter.removeObserver(displaySleepObserver)
            self.displaySleepObserver = nil
        }
        if let displayWakeObserver {
            wakeNotificationCenter.removeObserver(displayWakeObserver)
            self.displayWakeObserver = nil
        }

        batteryDetails.deactivate()
        mobileBattery.stop()
        appleDeviceDiscovery.stop()
        batteryMonitor.stop()
        wifiMonitor.stop()
        connectionMonitor?.stop()
        volumeMonitor.stop()
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        popupPublishTask?.cancel()
        popupPublishTask = nil
        clearWiFiNameResolution()
        wifiNetworks.deactivate()
        primaryLink.deactivate()
        bluetoothDevices.shutdown()
        bluetoothListeningModes.stop()
    }

    var isVolumeControlAvailable: Bool {
        volumeController != nil && liveVolume.canSetVolume
    }

    var isVolumeControllerAvailable: Bool { volumeController != nil }

    func setVolume(_ scalar: Double) {
        guard !hasStopped,
              volumeController != nil,
              liveVolume.canSetVolume,
              scalar.isFinite else {
            return
        }
        let previousScalar = liveVolume.scalar
        liveVolume = liveVolume.replacingScalar(min(1, max(0, scalar)))
        publish(snapshot.replacingVolume(liveVolume))
        volumeController?.setVolume(liveVolume.scalar ?? 0)

        // The system plays its own feedback only for the volume changes it
        // mediates; a CoreAudio write is not one of them, so the tick comes
        // from here. Clamping makes a scroll past either end ask for the same
        // scalar again, and that repeat must stay silent.
        if previousScalar != liveVolume.scalar {
            volumeFeedback?.playVolumeChangeFeedback()
        }
    }

    func finishVolumeAdjustment() { volumeController?.flushPendingVolume() }

    func toggleMute() {
        guard !hasStopped,
              volumeController != nil,
              liveVolume.canMute else {
            return
        }
        liveVolume = liveVolume.replacingMuted(!liveVolume.isMuted)
        publish(snapshot.replacingVolume(liveVolume))
        volumeController?.toggleMute()
    }

    func selectOutputDevice(_ device: AudioOutputDevice) {
        guard !hasStopped else { return }
        volumeController?.selectOutputDevice(device.id)
    }

    @discardableResult
    func requestWiFiNameAccess() -> WiFiNameAccessRequestResult {
        guard !hasStopped else { return .notNeeded }
        return wifiMonitor.requestNameAccess()
    }

    func requestBluetoothAuthorization() {
        setBluetoothEnabled(true)
    }

    /// The route where a refused Bluetooth grant is restored. This is not the
    /// Bluetooth pane the gear opens — that one toggles the radio, while a refusal
    /// lives under Privacy & Security. First entry decides the destination; the
    /// second covers the URL scheme itself failing to open.
    static let bluetoothPermissionSettingsURLs: [URL] = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
    ]
    .compactMap(URL.init(string:))

    /// Opens the Privacy & Security pane where a refused Bluetooth grant is
    /// restored. This is not the Bluetooth pane the gear opens — that one toggles
    /// the radio, while a refusal lives under Privacy & Security.
    func openBluetoothPermissionSettings() {
        for url in Self.bluetoothPermissionSettingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }

    func setBluetoothEnabled(_ enabled: Bool) {
        guard !hasStopped else { return }
        isBluetoothEnabled = enabled
        isBluetoothActivatedForPopover = false
        if enabled {
            _ = bluetoothDevices.requestExplicitActivation(BluetoothDeviceController.settingsActivationToken)
        } else {
            bluetoothDevices.releaseActivation(BluetoothDeviceController.settingsActivationToken)
        }
    }

    // The popover's Bluetooth surface claim is spelled once, next to the type
    // that owns the gate: `BluetoothDeviceController.popoverSurfaceToken`. A
    // second literal here would let a rename silently stop the poll forever
    // with no compile error.

    /// Temporarily enables Bluetooth monitoring while the popover is open, so
    /// the row can report device names. Starting the monitor is what raises the
    /// system permission prompt, so this only runs for an app that already
    /// holds the grant. An explicit Settings toggle owns the monitor beyond the
    /// popover lifetime; this activation does not.
    private func activateBluetoothForPopover() {
        guard BluetoothPanelActivation.shouldActivate(
            authorization: bluetoothDevices.authorization
        ) else { return }
        let monitorWasAlreadyActive = bluetoothDevices.isActive
        if !isBluetoothEnabled {
            if !monitorWasAlreadyActive {
                isBluetoothActivatedForPopover = bluetoothDevices.requestActivation(
                    BluetoothDeviceController.popoverActivationToken
                )
            }
        }
        if monitorWasAlreadyActive {
            // An already-running Settings-owned monitor will not report its
            // current state again just because the popover opened.
            bluetoothDevices.refresh()
        }
    }

    func closeBatteryDetails() {
        batteryDetails.deactivate()
    }

    func refreshForPopoverOpening() {
        setPopoverVisible(true)
    }

    func setRefreshInterval(_ interval: Duration) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
    }

    func setPopoverVisible(_ visible: Bool) {
        guard !hasStopped else { return }
        isPopoverVisible = visible
        mobileBattery.setSurfaceVisible(visible)
        updateAppleRefreshDemand()
        inputMonitor?.setVisible(visible)
        if !visible { batteryDetails.deactivate() }
        updateDetailsVisibility()
        updatePrimaryLinkActivation()

        guard visible else {
            stopVPNMonitoringForPopover()
            clearWiFiNameResolution()
            bluetoothDevices.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
            if isBluetoothActivatedForPopover {
                isBluetoothActivatedForPopover = false
                bluetoothDevices.releaseActivation(BluetoothDeviceController.popoverActivationToken)
            }
            // A confirmation is answered inside the panel, so closing the panel
            // cancels an unanswered one. The popover retains its content view
            // controller after a close, which is why this belongs here rather
            // than in the views: their own disappear hooks do not run.
            bluetoothDevices.cancelDisconnectConfirmation()
            return
        }
        popupPublishTask?.cancel()
        popupPublishTask = nil
        startVPNMonitoringForPopover()
        popupSnapshot = snapshot
        startWiFiNameResolutionIfNeeded()
        bluetoothDevices.prepareForPresentation()
        bluetoothDevices.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        activateBluetoothForPopover()
        refreshAll()
        wifiNetworks.refresh(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    func setSettingsVisible(_ visible: Bool) {
        guard !hasStopped, isSettingsVisible != visible else { return }
        isSettingsVisible = visible
        updateDetailsVisibility()

        if visible {
            refreshAll()
        }
    }

    func activateWiFiPanel() {
        guard !hasStopped else { return }
        wifiNetworks.activate(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    /// Leaving the Wi-Fi page stops its scan loop. The page also holds a
    /// 30-second periodic scan and a `networksetup` subprocess per scan, and the
    /// popover can stay open on another page for a long time.
    func closeWiFiDetails() {
        wifiNetworks.deactivate()
    }

    /// Records that the popover is showing the wired link panel. Unlike the
    /// Wi-Fi page there is nothing to start here — the wired controller follows
    /// the popover's own visibility and the connection — but the panel still
    /// keeps SwiftUI state that decides whether the built content can be reused.
    func activatePrimaryLinkPanel() {
        guard !hasStopped else { return }
        isPrimaryLinkPanelOpen = true
    }

    func closePrimaryLinkPanel() {
        isPrimaryLinkPanelOpen = false
    }

    func closePopoverDetails() {
        wifiNetworks.deactivate()
        closePrimaryLinkPanel()
        closeBatteryDetails()
        bluetoothDevices.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
    }

    /// Whether a popover detail panel (Wi-Fi, wired link, Bluetooth, or battery)
    /// is currently open. Query this before `setPopoverVisible(false)`: the
    /// battery page stops its collector when its view disappears, and that
    /// happens while the popover is already closing.
    var hasOpenPopoverPanel: Bool {
        wifiNetworks.isActive || isPrimaryLinkPanelOpen || batteryDetails.isActive
    }

    func refreshAll() {
        guard !hasStopped else { return }
        batteryMonitor.refresh()
        wifiMonitor.refresh()
        volumeMonitor.refresh()
    }

    /// One fallback tick. `refreshAll()` remains the unconditional refresh for
    /// popover opening, Settings opening and wake recovery; this one is the
    /// steady-state poll and only pays for what the menu bar icon and the Dock
    /// icon are currently drawing.
    private func fallbackRefreshTick() {
        guard !hasStopped else { return }

        // Asleep skips this tick's work: the timer keeps ticking, the stride
        // counter does not advance, and either wake notification clears the flag
        // and resumes full refreshes. The skip must still be bounded, because a
        // display-only sleep is cleared by `screensDidWakeNotification` alone —
        // if that one notification is lost, skipping forever would freeze the
        // battery percentage drawn into the menu bar icon while the display is
        // on. `maximumDisplayAsleepSkips` runs a tick anyway once per cap.
        if isDisplayAsleep {
            displayAsleepSkipCount &+= 1
            guard displayAsleepSkipCount >= Self.maximumDisplayAsleepSkips else { return }
        }
        displayAsleepSkipCount = 0
        fallbackTickCount &+= 1
        batteryMonitor.refresh()

        let showsStatusUI = isPopoverVisible || isSettingsVisible
        guard showsStatusUI || fallbackTickCount % Self.hiddenFallbackTickStride == 0 else { return }
        wifiMonitor.refresh()
        volumeMonitor.refresh()
    }

    private func recoverAll() {
        batteryMonitor.recover()
        wifiMonitor.recover()
        connectionMonitor?.recover()
        if isVPNActiveForPopover {
            vpnMonitor?.recover()
        }
        volumeMonitor.recover()
        inputMonitor?.recover()
    }

    private func startVPNMonitoringForPopover() {
        guard !isVPNActiveForPopover, let vpnMonitor else { return }
        isVPNActiveForPopover = true
        let updates = vpnMonitor.updates
        vpnUpdateTask = Task { [weak self] in
            for await value in updates {
                guard let self else { return }
                self.applyVPN(value)
            }
        }
        vpnMonitor.start()
    }

    private func stopVPNMonitoringForPopover() {
        guard isVPNActiveForPopover else { return }
        isVPNActiveForPopover = false
        vpnUpdateTask?.cancel()
        vpnUpdateTask = nil
        vpnMonitor?.stop()
    }

    private func updateDetailsVisibility() {
        let detailsVisible = isPopoverVisible || isSettingsVisible
        wifiMonitor.setDetailsVisible(isPopoverVisible)
        volumeMonitor.setDetailsVisible(detailsVisible)
    }

    func bindInputSettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        inputSettingsCancellable = settings.$enabledPopupSections
            .map { $0.contains(.audioInput) }
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setInputEnabled(enabled)
            }
    }

    func bindMobileBatterySettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        nearbyBLESettingsCancellables.removeAll()
        settings.$showsAppleDevicesAndBattery
            .combineLatest(settings.$nearbyBLESelections, settings.$hiddenBluetoothDeviceAddresses,
                           settings.$showsBluetoothBatteryLevels)
            .combineLatest(settings.$showsBluetoothDeviceList)
            .sink { [weak self] values, listVisible in
                let (enabled, selections, hidden, batteryEnabled) = values
                let expandedHidden = BluetoothDeviceListPresentation.expandedAliasIDs(
                    forHiddenIDs: hidden,
                    among: self?.appleDeviceAliasRows(for: settings) ?? []
                )
                self?.bluetoothDevices.configureNearbyBLEDevices(
                    enabled: enabled, knownIDs: Set(selections.map(\.id)),
                    hiddenIDs: Set(expandedHidden.compactMap { BluetoothDeviceIdentity.bleUUID(from: $0) }),
                    batteryLevelsEnabled: batteryEnabled,
                    listVisible: listVisible,
                    persistedSelections: selections
                )
            }.store(in: &nearbyBLESettingsCancellables)
        bluetoothDevices.$nearbyBatteryDevices
            .sink { [weak settings] readings in settings?.updateNearbyBLEMetadata(readings) }
            .store(in: &nearbyBLESettingsCancellables)
        mobileBatterySettingsCancellable = settings.$showsBluetoothBatteryLevels
            .combineLatest(
                settings.$showsAppleDevicesAndBattery,
                settings.$showsBluetoothDeviceList
            )
            .map { $0.0 && $0.1 && $0.2 }
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.mobileBattery.setReadingEnabled(enabled)
            }
        appleDeviceSettingsCancellable = settings.$showsAppleDevicesAndBattery
            .combineLatest(appleDeviceDiscovery.$candidates)
            .sink { [weak self, weak settings] enabled, candidates in
                self?.trustedAppleDeviceCandidates = candidates
                self?.trustedAppleDeviceDiscoveryGeneration = self?.appleDeviceDiscovery.discoveryGeneration ?? 0
                guard enabled else { return }
                settings?.updateTrustedAppleDeviceMetadata(candidates)
            }
        appleBackgroundSettingsCancellable = settings.$refreshesAppleBatteriesInBackground
            .combineLatest(settings.$appleBatteryRefreshIntervalMinutes)
            .sink { [weak self] enabled, intervalMinutes in
                self?.mobileBattery.setBackgroundRefresh(
                    enabled: enabled,
                    interval: .seconds(intervalMinutes * 60)
                )
                self?.appleDeviceDiscovery.setRefreshInterval(.seconds(intervalMinutes * 60))
                Task { @MainActor [weak self] in self?.updateAppleRefreshDemand() }
            }
        appleEligibilitySettingsCancellable = settings.$showsAppleDevicesAndBattery
            .combineLatest(
                settings.$showsBluetoothBatteryLevels,
                settings.$showsBluetoothDeviceList,
                settings.$enabledPopupSections
            )
            .sink { [weak self] masterEnabled, _, _, _ in
                guard let self else { return }
                self.appleDeviceDiscovery.setEnabled(masterEnabled)
                Task { @MainActor [weak self] in self?.updateAppleRefreshDemand() }
            }
        settings.$hiddenBluetoothDeviceAddresses
            .sink { [weak self, weak settings] values in
                guard let self, let settings else { return }
                let expandedHidden = BluetoothDeviceListPresentation.expandedAliasIDs(
                    forHiddenIDs: values,
                    among: self.appleDeviceAliasRows(for: settings)
                )
                let hidden = Set(expandedHidden.compactMap { rowID -> AppleDeviceID? in
                    if let uuid = BluetoothDeviceIdentity.bleUUID(from: rowID) { return .ble(uuid) }
                    guard let candidate = (settings.trustedAppleDeviceMetadata + self.trustedAppleDeviceCandidates).first(where: {
                        BluetoothDeviceIdentity.preferenceKey($0.id.rowID) == BluetoothDeviceIdentity.preferenceKey(rowID)
                    }) else { return nil }
                    return candidate.id
                })
                self.mobileBattery.revokeDeviceIDs(hidden)
                Task { @MainActor [weak self] in self?.updateAppleRefreshDemand() }
            }.store(in: &nearbyBLESettingsCancellables)
        appleDeviceDiscovery.setEnabled(settings.showsAppleDevicesAndBattery)
        appleDeviceDiscovery.setRefreshInterval(.seconds(settings.appleBatteryRefreshIntervalMinutes * 60))
        self.boundAppleRefreshSettings = settings
        trustedAppleDeviceCandidates = appleDeviceDiscovery.candidates
        trustedAppleDeviceDiscoveryGeneration = appleDeviceDiscovery.discoveryGeneration
        updateAppleRefreshDemand()
    }

    private weak var boundAppleRefreshSettings: SettingsStore?

    private func updateAppleRefreshDemand() {
        guard let settings = boundAppleRefreshSettings else { return }
        let eligible = settings.showsAppleDevicesAndBattery
            && settings.showsBluetoothBatteryLevels
            && settings.showsBluetoothDeviceList
        let background = eligible && settings.refreshesAppleBatteriesInBackground
        let foreground = eligible && isPopoverVisible && settings.enabledPopupSections.contains(.bluetooth)
        appleDeviceDiscovery.setEnabled(eligible)
        let hiddenKeys = Set(BluetoothDeviceListPresentation.expandedAliasIDs(
            forHiddenIDs: settings.hiddenBluetoothDeviceAddresses,
            among: appleDeviceAliasRows(for: settings)
        ).map { BluetoothDeviceIdentity.preferenceKey($0) })
        if background || foreground {
            appleDeviceDiscovery.request("system-status.apple-refresh")
            let backgroundIDs: Set<AppleDeviceID> = settings.refreshesAppleBatteriesInBackground
                ? Set(AppleDeviceCatalog.candidates(trusted: settings.trustedAppleDeviceMetadata)
                    .filter { !hiddenKeys.contains(BluetoothDeviceIdentity.preferenceKey($0.id.rowID)) }
                    .map(\.id))
                : []
            mobileBattery.setBackgroundAuthorizedDeviceIDs(backgroundIDs)
            let bleIDs: Set<UUID> = background
                ? Set(settings.nearbyBLESelections.filter { $0.vendor == .apple }
                    .filter { !hiddenKeys.contains(BluetoothDeviceIdentity.preferenceKey(BluetoothDeviceIdentity.bleRowID($0.id))) }
                    .map(\.id))
                : []
            bluetoothDevices.setNearbyBLEBackgroundRefresh(
                enabled: background,
                selectedIDs: bleIDs,
                interval: .seconds(settings.appleBatteryRefreshIntervalMinutes * 60)
            )
        } else {
            appleDeviceDiscovery.release("system-status.apple-refresh")
            mobileBattery.setBackgroundAuthorizedDeviceIDs([])
            bluetoothDevices.setNearbyBLEBackgroundRefresh(enabled: false, selectedIDs: [])
        }
    }

    private func appleDeviceAliasRows(for settings: SettingsStore) -> [BluetoothDevice] {
        let options = settings.bluetoothDeviceListOptions
        let unhiddenOptions = BluetoothDeviceListOptions(
            showsList: options.showsList,
            maxVisibleDevices: options.maxVisibleDevices,
            order: options.order,
            hidesGhostDevices: options.hidesGhostDevices,
            revealedGhostDeviceAddresses: options.revealedGhostDeviceAddresses
        )
        let trustedRows = AppleDeviceCatalog.projection(
            candidates: AppleDeviceCatalog.candidates(
                trusted: settings.trustedAppleDeviceMetadata + trustedAppleDeviceCandidates
            ),
            trustedSnapshots: mobileBattery.snapshots,
            options: unhiddenOptions
        ).rows.map(\.device)
        let nearbyRows = NearbyBLEDeviceCatalog.panelRows(
            selections: settings.nearbyBLESelections,
            readings: bluetoothDevices.nearbyBatteryDevices,
            failures: bluetoothDevices.nearbyBLEReadFailures,
            options: unhiddenOptions,
            now: Date()
        ).map(\.device)
        return trustedRows + nearbyRows
    }

    func selectInputDevice(_ id: AudioDeviceID) {
        guard !hasStopped else { return }
        inputMonitor?.select(id)
    }

    func setInputScalar(_ value: Double) {
        guard !hasStopped else { return }
        inputMonitor?.setScalar(value)
    }

    func toggleInputMute() {
        guard !hasStopped else { return }
        inputMonitor?.toggleMute()
    }

    private func setInputEnabled(_ enabled: Bool) {
        guard !hasStopped else { return }
        inputSettingEnabled = enabled
        guard hasStarted else { return }

        isInputEnabled = enabled
        inputMonitor?.setEnabled(enabled)
        if enabled {
            inputMonitor?.setVisible(isPopoverVisible)
        }
    }

    private func applyInput(_ value: AudioInputStatus) {
        guard !hasStopped, isInputEnabled else { return }
        liveInput = value
    }

    /// Starts and stops the wired link read.
    ///
    /// It runs only while both conditions hold: the popover is open, and the
    /// primary connection is Ethernet. Nothing draws the address in any other
    /// state, and the read walks the system configuration store, which is not a
    /// cost to pay on Wi-Fi. Because the second condition is sampled here rather
    /// than in the view, plugging a cable in while the popover is open starts
    /// the read on the connection change itself.
    private func updatePrimaryLinkActivation() {
        guard !hasStopped else { return }
        if isPopoverVisible, snapshot.connection == .ethernet {
            primaryLink.activate()
        } else {
            primaryLink.deactivate()
        }
    }
    private func applyBattery(_ value: BatteryStatus) {
        publish(snapshot.replacingBattery(value))
    }

    private func applyWiFi(_ value: WiFiStatus) {
        publish(snapshot.replacingWiFi(value))
        wifiNetworks.refresh(nameAccess: value.nameAccess)
    }

    private func applyConnection(_ path: NetworkPathSnapshot) {
        // Guarded the way `applyVolume` guards its reading: an unchanged value
        // would re-render every observer of this `@Published` on every path
        // update, and `NWPathMonitor` reports often enough for that to matter.
        if isNetworkConstrained != path.constrained {
            isNetworkConstrained = path.constrained
        }
        publish(snapshot.replacingConnection(path.connection))
        updatePrimaryLinkActivation()
    }

    private func applyVPN(_ value: VPNStatus) {
        // The monitor already drops repeats, and this guard keeps an unchanged
        // value from sending `objectWillChange` to every VPN row observer.
        if value != vpnStatus {
            vpnStatus = value
        }
    }

    private func applyVolume(_ value: VolumeStatus) {
        // `liveVolume` drives the popover's volume section through
        // `objectWillChange`, and `publish` only dedupes the snapshot. Writing an
        // unchanged reading here re-rendered every volume observer on every
        // fallback tick, which the equality below stops.
        if value != liveVolume {
            liveVolume = value
        }
        publish(snapshot.replacingVolume(value))
    }

    private func publish(_ next: StatusSnapshot) {
        guard !hasStopped, next != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = next
        snapshot = next
        schedulePopupSnapshot(next)
    }

    private func schedulePopupSnapshot(_ next: StatusSnapshot) {
        guard isPopoverVisible else { return }
        if isResolvingWiFiName, !next.wifi.isAwaitingName {
            // The name the popover is waiting for just arrived: show it right away
            // instead of leaving the row blank for the full debounce interval.
            popupPublishTask?.cancel()
            popupPublishTask = nil
            applyPopupSnapshot(next)
            return
        }
        popupPublishTask?.cancel()
        popupPublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.popupDebounceSleep(Self.popupDebounceInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.applyPopupSnapshot(next)
        }
    }

    private func applyPopupSnapshot(_ next: StatusSnapshot) {
        popupSnapshot = next
        if isResolvingWiFiName, !next.wifi.isAwaitingName {
            clearWiFiNameResolution()
        }
    }

    /// Leaves the Wi-Fi row blank right after the popover opens until the name arrives.
    private func startWiFiNameResolutionIfNeeded() {
        guard isPopoverVisible, popupSnapshot.wifi.isAwaitingName else {
            clearWiFiNameResolution()
            return
        }
        guard !isResolvingWiFiName else { return }

        isResolvingWiFiName = true
        let timeout = nameResolutionTimeout
        let sleep = popupDebounceSleep
        wifiNameResolutionTask = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            // The read never delivered a name: fall back to the plain state text.
            self.isResolvingWiFiName = false
        }
    }

    private func clearWiFiNameResolution() {
        wifiNameResolutionTask?.cancel()
        wifiNameResolutionTask = nil
        isResolvingWiFiName = false
    }
}

private extension VolumeStatus {
    func replacingScalar(_ scalar: Double) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            currentDevice: currentDevice,
            outputDevices: outputDevices,
            canSetVolume: canSetVolume, canMute: canMute
        )
    }

    func replacingMuted(_ isMuted: Bool) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            currentDevice: currentDevice,
            outputDevices: outputDevices,
            canSetVolume: canSetVolume, canMute: canMute
        )
    }
}

extension StatusSnapshot {
    func replacingBattery(_ value: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(battery: value, wifi: wifi, connection: connection, volume: volume)
    }
}

private extension StatusSnapshot {
    func replacingWiFi(_ value: WiFiStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: value, connection: connection, volume: volume)
    }

    func replacingConnection(_ value: NetworkConnection) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: value, volume: volume)
    }

    func replacingVolume(_ value: VolumeStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: value)
    }
}
