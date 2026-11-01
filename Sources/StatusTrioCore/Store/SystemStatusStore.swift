import AppKit
import AudioToolbox
import Combine
import Foundation

private struct BluetoothDemandSettingsSnapshot: Equatable {
    var enabledPopupSections: Set<PopupSection> = []
    var replacesNetworkIconWithBluetoothAudio = false
    var bluetoothNetworkIconDeviceAddress: String?
    var showsAppleDevicesAndBattery = false
    var refreshesAppleBatteriesInBackground = false
    var showsBluetoothBatteryLevels = false
    var showsBluetoothDeviceList = false
}

private enum BluetoothDemandSource: Hashable {
    case popover
    case settings
    case selectedDeviceIcon
    case backgroundRefresh
    case audioListeningModes
    case legacyToggle
    case authorizationRequest
}

struct BluetoothSettingsDemandToken: Hashable, Sendable {
    fileprivate let id = UUID()
}

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
    @Published private(set) var betterDisplayState = BetterDisplayCatalogUpdate(
        devices: [], availability: .idle
    )
    var betterDisplayDevices: [BetterDisplayDevice] { betterDisplayState.devices }
    var betterDisplayAvailability: BetterDisplayAvailability { betterDisplayState.availability }
    let batteryDetails: BatteryDetailsController
    /// The single owner of periodic whole-machine power reads shared by the
    /// icon centre slot, the panel summary and the details page.
    let powerSampling: PowerSamplingService
    let wifiNetworks: WiFiNetworkController
    /// The wired link's address configuration. Read while the popover is open on
    /// an Ethernet connection and dropped when either stops being true, so the
    /// row never shows the address of a link the user has left.
    let primaryLink: PrimaryLinkController
    /// The private LAN address. Popover-only state like `primaryLink`, and read
    /// only while the popover is open with the Local IP row switched on.
    let localIP: LocalIPController
    let bluetoothDevices: BluetoothDeviceController
    let bluetoothPower: BluetoothRadioPowerController
    let mobileBattery: MobileBatteryController
    let appleDeviceDiscovery: AppleDeviceDiscoveryController
    /// The AirPods listening-mode surface. A separate owner from `bluetoothDevices`
    /// (the plan's Option B): its own discovery/write lifecycle, so the delicate
    /// paired-device controller is not widened by it. The Bluetooth view drives it
    /// from the same appear/disappear and refresh hooks the device list uses.
    let bluetoothListeningModes: BluetoothListeningModeController
    /// The Low Power Mode write path. Dormant until the opt-in enables it, so
    /// the privileged helper is never contacted while the feature is off.
    let lowPowerMode: LowPowerModeController

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let connectionMonitor: (any NetworkConnectionMonitoring)?
    private let vpnMonitor: (any VPNMonitoring)?
    private let volumeMonitor: any VolumeMonitoring
    private let inputMonitor: (any AudioInputMonitoring)?
    private let volumeController: (any VolumeControlling)?
    private let volumeFeedback: (any VolumeFeedbackPlaying)?
    private let bluetoothProfilerCache: BluetoothProfilerReportCache
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
    private var externalVolumeSettingsCancellable: AnyCancellable?
    private weak var boundExternalVolumeSettings: SettingsStore?
    private var localIPSettingsCancellable: AnyCancellable?
    private var applicationEnergySettingsCancellable: AnyCancellable?
    private var isApplicationEnergyEnabled = false
    private var isApplicationEnergySystemAsleep = false
    private var isApplicationEnergyDisplayAsleep = false
    private var mobileBatterySettingsCancellable: AnyCancellable?
    private var lowPowerModeSettingsCancellable: AnyCancellable?
    private var lowPowerModeSnapshotCancellable: AnyCancellable?
    private var appleDeviceSettingsCancellable: AnyCancellable?
    private var appleBackgroundSettingsCancellable: AnyCancellable?
    private var appleEligibilitySettingsCancellable: AnyCancellable?
    private var nearbyBLESettingsCancellables: Set<AnyCancellable> = []
    private var bluetoothSettingsCancellables: Set<AnyCancellable> = []
    private var bluetoothAuthorizationCancellable: AnyCancellable?
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
    private(set) var popoverOpenGeneration: UInt64 = 0
    @Published private(set) var trustedAppleDeviceCandidates: [AppleDeviceCandidate] = []
    @Published private(set) var trustedAppleDeviceDiscoveryGeneration: UInt64 = 0
    /// True while the display is asleep. The fallback poll skips its work then,
    /// because no menu bar or Dock tile is on screen to keep fresh.
    @Published private(set) var isDisplayAsleep = false
    private var isSettingsVisible = false
    private var isBluetoothMonitoringSuspendedForPower = false
    private weak var boundBluetoothSettings: SettingsStore?
    private var hasBluetoothSettingsBinding = false
    private var bluetoothSettingsSnapshot = BluetoothDemandSettingsSnapshot()
    private var bluetoothSettingsDemandTokens: Set<BluetoothSettingsDemandToken> = []
    private var legacyBluetoothSettingsDemandClaimCount = 0
    private var isLegacyBluetoothDemandEnabled = false
    private var isBluetoothAuthorizationRequestPending = false
    private var isReconcilingBluetoothDemand = false
    private var needsBluetoothDemandReconciliation = false
    private var appliedBluetoothDemandSources: Set<BluetoothDemandSource> = []
    private var bluetoothProfilerReaderToken: BluetoothProfilerReportCache.ReaderToken?
    /// Whether the wired link panel is the open detail panel. The controller
    /// itself follows the connection; this only records that the panel is on
    /// screen, which is what decides whether the built popover content can be
    /// kept for a rapid reopen.
    private var isPrimaryLinkPanelOpen = false
    /// Whether the Local IP row is switched on. The controller itself follows
    /// the popover's own visibility; this is the settings half of its
    /// activation, so the read runs only while the row is actually drawn.
    private var isLocalIPEnabled = false

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
        powerSampling: PowerSamplingService = PowerSamplingService(),
        wifiNetworks: WiFiNetworkController = WiFiNetworkController(),
        primaryLink: PrimaryLinkController = PrimaryLinkController(),
        localIP: LocalIPController = LocalIPController(),
        bluetoothDevices: BluetoothDeviceController = BluetoothDeviceController(),
        bluetoothPower: BluetoothRadioPowerController = BluetoothRadioPowerController(),
        bluetoothProfilerCache: BluetoothProfilerReportCache = .shared,
        mobileBattery: MobileBatteryController = MobileBatteryController(),
        appleDeviceDiscovery: AppleDeviceDiscoveryController = AppleDeviceDiscoveryController(),
        bluetoothListeningModes: BluetoothListeningModeController = BluetoothListeningModeController(),
        lowPowerMode: LowPowerModeController = LowPowerModeController(),
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
        self.powerSampling = powerSampling
        batteryDetails.powerSampling = powerSampling
        self.wifiNetworks = wifiNetworks
        self.primaryLink = primaryLink
        self.localIP = localIP
        self.bluetoothDevices = bluetoothDevices
        self.bluetoothPower = bluetoothPower
        self.bluetoothProfilerCache = bluetoothProfilerCache
        self.mobileBattery = mobileBattery
        self.appleDeviceDiscovery = appleDeviceDiscovery
        self.bluetoothListeningModes = bluetoothListeningModes
        self.lowPowerMode = lowPowerMode
        self.snapshot = initialSnapshot
        self.popupSnapshot = initialSnapshot
        self.vpnStatus = .placeholder
        self.liveVolume = initialSnapshot.volume
        bluetoothAuthorizationCancellable = bluetoothDevices.$authorizationStatus
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileBluetoothDemand()
            }
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
        updateApplicationEnergyDemand()
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
                // Unlike the icon fallback poll, an energy scan must stay
                // paused through a dark wake while the display is still off.
                self.isApplicationEnergySystemAsleep = false
                self.updateApplicationEnergyDemand()
                self.bluetoothDevices.setSystemSleeping(false)
                self.volumeMonitor.setDisplayAsleep(false)
                self.displayAsleepSkipCount = 0
                self.reconcileBluetoothDemand()
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
                self?.isApplicationEnergySystemAsleep = true
                self?.updateApplicationEnergyDemand()
                self?.bluetoothDevices.setSystemSleeping(true)
                self?.reconcileBluetoothDemand()
            }
        }

        displaySleepObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplayAsleep = true
                self?.isApplicationEnergyDisplayAsleep = true
                self?.updateApplicationEnergyDemand()
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
                self.isApplicationEnergyDisplayAsleep = false
                // A display wake also proves that the system is awake, even
                // when its separate system-wake notification was missed.
                self.isApplicationEnergySystemAsleep = false
                self.updateApplicationEnergyDemand()
                self.volumeMonitor.setDisplayAsleep(false)
                self.displayAsleepSkipCount = 0
                self.reconcileBluetoothDemand()
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
                inputMonitor.setDeviceListVisible(isSettingsVisible)
            }
        }

        let batteryUpdates = batteryMonitor.updates
        let wifiUpdates = wifiMonitor.updates
        let connectionUpdates = connectionMonitor?.updates
        let volumeUpdates = volumeMonitor.updates
        let betterDisplayCatalogUpdates = volumeMonitor.betterDisplayCatalogUpdates
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
            },
            Task { [weak self] in
                for await value in betterDisplayCatalogUpdates {
                    guard let self else { return }
                    self.applyBetterDisplayCatalog(value)
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
        reconcileBluetoothDemand()

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
        externalVolumeSettingsCancellable?.cancel()
        externalVolumeSettingsCancellable = nil
        applicationEnergySettingsCancellable?.cancel()
        applicationEnergySettingsCancellable = nil
        batteryDetails.energyApps.stop()
        mobileBatterySettingsCancellable?.cancel()
        mobileBatterySettingsCancellable = nil
        lowPowerModeSettingsCancellable?.cancel()
        lowPowerModeSettingsCancellable = nil
        lowPowerModeSnapshotCancellable?.cancel()
        lowPowerModeSnapshotCancellable = nil
        appleDeviceSettingsCancellable?.cancel()
        appleDeviceSettingsCancellable = nil
        appleBackgroundSettingsCancellable?.cancel()
        appleBackgroundSettingsCancellable = nil
        appleEligibilitySettingsCancellable?.cancel()
        appleEligibilitySettingsCancellable = nil
        nearbyBLESettingsCancellables.removeAll()
        bluetoothSettingsCancellables.removeAll()
        bluetoothAuthorizationCancellable?.cancel()
        bluetoothAuthorizationCancellable = nil
        bluetoothSettingsDemandTokens.removeAll()
        legacyBluetoothSettingsDemandClaimCount = 0
        boundBluetoothSettings = nil
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

        powerSampling.stopAll()
        batteryDetails.deactivate()
        mobileBattery.stop()
        lowPowerMode.stop()
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
        localIP.deactivate()
        bluetoothDevices.releaseTransientState()
        releaseBluetoothProfilerReader()
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
        guard !hasStopped else { return }
        isBluetoothAuthorizationRequestPending = true
        bluetoothDevices.prepareForPresentation()
        reconcileBluetoothDemand()
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

    func setBluetoothDeviceMonitoringEnabled(_ enabled: Bool) {
        guard !hasStopped else { return }
        isLegacyBluetoothDemandEnabled = enabled
        isBluetoothMonitoringSuspendedForPower = false
        if enabled {
            bluetoothDevices.prepareForPresentation()
        }
        reconcileBluetoothDemand()
    }

    /// The Bluetooth page owns a consumer only while it is actually visible.
    /// Merely opening Settings on another page must not start CoreBluetooth.
    func setBluetoothSettingsVisible(_ visible: Bool) {
        guard !hasStopped else { return }
        if visible, hasStarted {
            bluetoothDevices.prepareForPresentation()
            legacyBluetoothSettingsDemandClaimCount += 1
            reconcileBluetoothDemand()
        } else if !visible, legacyBluetoothSettingsDemandClaimCount > 0 {
            legacyBluetoothSettingsDemandClaimCount -= 1
            reconcileBluetoothDemand()
        }
    }

    func setBluetoothPower(_ enabled: Bool) async {
        guard !hasStopped else { return }
        guard bluetoothDevices.authorization == .allowed else { return }
        guard await bluetoothPower.setPower(enabled), !hasStopped else { return }
        isBluetoothMonitoringSuspendedForPower = !enabled
        reconcileBluetoothDemand()
    }

    func beginBluetoothSettingsDemand() -> BluetoothSettingsDemandToken? {
        guard !hasStopped, hasStarted else { return nil }
        // Called only when the page is about to be shown, but the canonical
        // authorization value is always safe to publish without starting
        // CoreBluetooth.
        bluetoothDevices.prepareForPresentation()
        let token = BluetoothSettingsDemandToken()
        bluetoothSettingsDemandTokens.insert(token)
        reconcileBluetoothDemand()
        return token
    }

    func endBluetoothSettingsDemand(_ token: BluetoothSettingsDemandToken) {
        guard !hasStopped,
              bluetoothSettingsDemandTokens.remove(token) != nil else {
            return
        }
        reconcileBluetoothDemand()
    }

    /// Binds demand inputs without retaining the settings object itself. Every
    /// consumer uses the value delivered by Combine: `@Published` publishes from
    /// `willSet`, so reading `settings` inside the sink would observe the prior
    /// value during a same-turn toggle.
    func bindBluetoothSettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        let previouslyNeededVolumeDetails = needsVolumeDetails
        boundBluetoothSettings = settings
        hasBluetoothSettingsBinding = true
        bluetoothSettingsSnapshot = Self.bluetoothDemandSettingsSnapshot(settings)
        bluetoothSettingsCancellables.removeAll()

        let panelAndDisplay = Publishers.CombineLatest4(
            settings.$enabledPopupSections,
            settings.$replacesNetworkIconWithBluetoothAudio,
            settings.$bluetoothNetworkIconDeviceAddress,
            settings.$showsAppleDevicesAndBattery
        )
        let backgroundAndRows = Publishers.CombineLatest3(
            settings.$refreshesAppleBatteriesInBackground,
            settings.$showsBluetoothBatteryLevels,
            settings.$showsBluetoothDeviceList
        )

        Publishers.CombineLatest(panelAndDisplay, backgroundAndRows)
            .sink { [weak self] panelAndDisplay, backgroundAndRows in
                guard let self else { return }
                let previouslyNeededVolumeDetails = self.needsVolumeDetails
                self.bluetoothSettingsSnapshot = BluetoothDemandSettingsSnapshot(
                    enabledPopupSections: panelAndDisplay.0,
                    replacesNetworkIconWithBluetoothAudio: panelAndDisplay.1,
                    bluetoothNetworkIconDeviceAddress: panelAndDisplay.2,
                    showsAppleDevicesAndBattery: panelAndDisplay.3,
                    refreshesAppleBatteriesInBackground: backgroundAndRows.0,
                    showsBluetoothBatteryLevels: backgroundAndRows.1,
                    showsBluetoothDeviceList: backgroundAndRows.2
                )
                self.updateVolumeDetailsAfterSettingsChange(
                    previouslyNeeded: previouslyNeededVolumeDetails
                )
                self.reconcileBluetoothDemand()
            }
            .store(in: &bluetoothSettingsCancellables)

        updateVolumeDetailsAfterSettingsChange(
            previouslyNeeded: previouslyNeededVolumeDetails
        )
        reconcileBluetoothDemand()
    }

    private static func bluetoothDemandSettingsSnapshot(
        _ settings: SettingsStore
    ) -> BluetoothDemandSettingsSnapshot {
        BluetoothDemandSettingsSnapshot(
            enabledPopupSections: settings.enabledPopupSections,
            replacesNetworkIconWithBluetoothAudio: settings.replacesNetworkIconWithBluetoothAudio,
            bluetoothNetworkIconDeviceAddress: settings.bluetoothNetworkIconDeviceAddress,
            showsAppleDevicesAndBattery: settings.showsAppleDevicesAndBattery,
            refreshesAppleBatteriesInBackground: settings.refreshesAppleBatteriesInBackground,
            showsBluetoothBatteryLevels: settings.showsBluetoothBatteryLevels,
            showsBluetoothDeviceList: settings.showsBluetoothDeviceList
        )
    }

    private func currentBluetoothDemandSources() -> Set<BluetoothDemandSource> {
        var sources: Set<BluetoothDemandSource> = []

        let isPopoverBluetoothVisible: Bool
        if hasBluetoothSettingsBinding {
            isPopoverBluetoothVisible = isPopoverVisible
                && bluetoothSettingsSnapshot.enabledPopupSections.contains(.bluetooth)
            if !bluetoothSettingsDemandTokens.isEmpty
                || legacyBluetoothSettingsDemandClaimCount > 0 {
                sources.insert(.settings)
            }
            if bluetoothSettingsSnapshot.replacesNetworkIconWithBluetoothAudio,
               bluetoothSettingsSnapshot.bluetoothNetworkIconDeviceAddress?.isEmpty == false {
                sources.insert(.selectedDeviceIcon)
            }
            let backgroundEligible = bluetoothSettingsSnapshot.showsAppleDevicesAndBattery
                && bluetoothSettingsSnapshot.showsBluetoothBatteryLevels
                && bluetoothSettingsSnapshot.showsBluetoothDeviceList
            if backgroundEligible,
               bluetoothSettingsSnapshot.refreshesAppleBatteriesInBackground {
                sources.insert(.backgroundRefresh)
            }
            if isPopoverVisible,
               bluetoothSettingsSnapshot.enabledPopupSections.contains(.volume),
               (
                   liveVolume.currentDevice?.isBluetoothAudio == true
                       || liveVolume.outputDevices.contains(where: \.isBluetoothAudio)
               ) {
                sources.insert(.audioListeningModes)
            }
        } else {
            // The pre-binding API is kept for tests and embedders. Production
            // binds settings before start and is gated by the snapshot above.
            isPopoverBluetoothVisible = isPopoverVisible
        }

        if isPopoverBluetoothVisible {
            sources.insert(.popover)
        }
        if isLegacyBluetoothDemandEnabled {
            sources.insert(.legacyToggle)
        }
        if isBluetoothAuthorizationRequestPending {
            sources.insert(.authorizationRequest)
        }
        return sources
    }

    private func reconcileBluetoothDemand() {
        guard !hasStopped else { return }
        if hasBluetoothSettingsBinding && !hasStarted {
            return
        }
        if isReconcilingBluetoothDemand {
            needsBluetoothDemandReconciliation = true
            return
        }
        isReconcilingBluetoothDemand = true
        while !hasStopped {
            needsBluetoothDemandReconciliation = false
            reconcileBluetoothDemandOnce()
            if !needsBluetoothDemandReconciliation {
                break
            }
        }
        if !hasStopped {
            isReconcilingBluetoothDemand = false
        }
    }

    private func reconcileBluetoothDemandOnce() {
        let previousSources = appliedBluetoothDemandSources
        let sources = currentBluetoothDemandSources()
        appliedBluetoothDemandSources = sources
        let popoverNeedsBluetooth = sources.contains(.popover)

        if popoverNeedsBluetooth {
            bluetoothDevices.prepareForPresentation()
            bluetoothDevices.holdVisibleSurface(
                BluetoothDeviceController.popoverSurfaceToken
            )
        } else {
            bluetoothDevices.releaseVisibleSurface(
                BluetoothDeviceController.popoverSurfaceToken
            )
        }

        let canActivateWithoutExplicitIntent = BluetoothPanelActivation.shouldActivate(
            authorization: bluetoothDevices.authorization
        )
        let explicitAuthorizationRequest = sources.contains(.authorizationRequest)
        let explicitActivation = sources.contains(.legacyToggle) || explicitAuthorizationRequest
        let shouldRead = !isBluetoothMonitoringSuspendedForPower
            && !sources.isEmpty
            && (canActivateWithoutExplicitIntent || explicitActivation)

        if shouldRead {
            if !bluetoothDevices.isActive {
                acquireBluetoothProfilerReader()
                bluetoothDevices.activate()
            } else if popoverNeedsBluetooth,
                      !previousSources.contains(.popover),
                      bluetoothDevices.availability == .available {
                // The state monitor reports its value only when it starts. A
                // panel opened while a background or Settings demand is already
                // active needs an explicit fresh read.
                bluetoothDevices.refresh()
            }
            if explicitAuthorizationRequest,
               bluetoothDevices.authorization != .notDetermined {
                // An explicit permission action is one-shot once the system
                // grant is already decided. A not-determined grant remains the
                // owner until the prompt resolves, so deactivation cannot cancel
                // an in-flight decision.
                isBluetoothAuthorizationRequestPending = false
                needsBluetoothDemandReconciliation = true
            }
            return
        }

        if bluetoothDevices.isActive {
            bluetoothDevices.deactivate()
        }
        bluetoothDevices.releaseTransientState()
        releaseBluetoothProfilerReader()
        if popoverNeedsBluetooth {
            // The read is intentionally idle without authorization, but the row
            // still needs to explain why and offer its explicit permission action.
            bluetoothDevices.prepareForPresentation()
        }
        if sources.isEmpty {
            bluetoothProfilerCache.resetIfUnused()
        }
    }

    private func acquireBluetoothProfilerReader() {
        guard bluetoothProfilerReaderToken == nil else { return }
        bluetoothProfilerReaderToken = bluetoothProfilerCache.acquireReader()
    }

    private func releaseBluetoothProfilerReader() {
        guard let token = bluetoothProfilerReaderToken else { return }
        bluetoothProfilerReaderToken = nil
        bluetoothProfilerCache.releaseReader(token)
    }

    func closeBatteryDetails() {
        batteryDetails.deactivate()
    }

    func refreshForPopoverOpening() {
        setPopoverVisible(true)
    }

    func bindExternalVolumeSettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        boundExternalVolumeSettings = settings
        volumeMonitor.setExternalVolumeConfigurations(
            settings.externalVolumeConfigurations
        )
        externalVolumeSettingsCancellable = settings.$externalVolumeConfigurations
            .removeDuplicates()
            .sink { [weak self] configurations in
                self?.volumeMonitor.setExternalVolumeConfigurations(configurations)
            }
    }

    func refreshBetterDisplayDevices() {
        guard !hasStopped else { return }
        betterDisplayState = BetterDisplayCatalogUpdate(
            devices: betterDisplayState.devices,
            availability: .discovering,
            isCatalogLoaded: false,
            outputUID: betterDisplayState.outputUID,
            displayUUID: betterDisplayState.displayUUID
        )
        volumeMonitor.refreshBetterDisplayDevices()
    }

    func setRefreshInterval(_ interval: Duration) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
    }

    func setPopoverVisible(_ visible: Bool) {
        guard !hasStopped else { return }
        // Preserve reopen events even when presentation updates coalesce a close
        // and an open into a single visible snapshot.
        if visible && !isPopoverVisible { popoverOpenGeneration &+= 1 }
        isPopoverVisible = visible
        // The system's own state may have changed while the popover was closed
        // (Control Center, the battery menu), so re-read it through the helper
        // before the battery row shows a stale Low Power Mode value.
        if visible {
            // A visible user surface repairs a missed display-wake signal
            // without resuming background work during network-only wakes.
            isApplicationEnergySystemAsleep = false
            isApplicationEnergyDisplayAsleep = false
            updateApplicationEnergyDemand()
            lowPowerMode.refresh()
        }
        mobileBattery.setSurfaceVisible(visible)
        updateAppleRefreshDemand()
        inputMonitor?.setVisible(visible)
        if !visible { batteryDetails.deactivate() }
        updateDetailsVisibility()
        updatePrimaryLinkActivation()
        updateLocalIPActivation()

        guard visible else {
            bluetoothListeningModes.stop()
            stopVPNMonitoringForPopover()
            clearWiFiNameResolution()
            reconcileBluetoothDemand()
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
        reconcileBluetoothDemand()
        refreshAll()
        wifiNetworks.refresh(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    func setSettingsVisible(_ visible: Bool) {
        guard !hasStopped, isSettingsVisible != visible else { return }
        isSettingsVisible = visible
        updateDetailsVisibility()
        inputMonitor?.setDeviceListVisible(visible)

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

    private var needsVolumeDetails: Bool {
        let popoverNeedsDetails = !hasBluetoothSettingsBinding
            || bluetoothSettingsSnapshot.enabledPopupSections.contains(.volume)
            || bluetoothSettingsSnapshot.enabledPopupSections.contains(.bluetooth)
        return isSettingsVisible || (isPopoverVisible && popoverNeedsDetails)
    }

    private func updateVolumeDetailsAfterSettingsChange(previouslyNeeded: Bool) {
        let needed = needsVolumeDetails
        guard needed != previouslyNeeded else { return }
        volumeMonitor.setDetailsVisible(needed)
        // Visibility entry points already call refreshAll(). A section enabled
        // inside an open popover has no such entry point, so fill its list now.
        if needed { volumeMonitor.refresh() }
    }

    private func updateDetailsVisibility() {
        wifiMonitor.setDetailsVisible(isPopoverVisible)
        volumeMonitor.setDetailsVisible(needsVolumeDetails)
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

    /// Binds the Local IP address read to its Settings toggle.
    ///
    /// The read only runs while the toggle is on, so the address is not looked
    /// up for a user who never enabled it, and switching it on while the
    /// popover is already open fills the row without a reopen.
    func bindLocalIPSettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        localIPSettingsCancellable = settings.$showsLocalIPAddress
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.isLocalIPEnabled = enabled
                self.updateLocalIPActivation()
            }
    }

    func bindApplicationEnergySettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        applicationEnergySettingsCancellable = settings.$showsHighEnergyApps
            .combineLatest(settings.$highEnergyAppsRefreshIntervalSeconds)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] enabled, intervalSeconds in
                guard let self else { return }
                self.isApplicationEnergyEnabled = enabled
                self.batteryDetails.energyApps.setBackgroundInterval(
                    .seconds(Int(intervalSeconds.rounded()))
                )
                self.updateApplicationEnergyDemand()
            }
    }

    private func updateApplicationEnergyDemand() {
        batteryDetails.energyApps.setSuspended(isApplicationEnergySystemAsleep || isApplicationEnergyDisplayAsleep)
        batteryDetails.energyApps.setBackgroundMonitoringEnabled(hasStarted && !hasStopped && isApplicationEnergyEnabled)
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

    /// Binds the Low Power Mode opt-in to the write controller and seeds its
    /// displayed value from the battery snapshot the app already reads.
    func bindLowPowerModeSettings(_ settings: SettingsStore) {
        guard !hasStopped else { return }
        lowPowerModeSettingsCancellable = settings.$controlsLowPowerMode
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.lowPowerMode.setEnabled(enabled)
            }
        lowPowerModeSnapshotCancellable = $snapshot
            .map(\.battery.isLowPowerMode)
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.lowPowerMode.updateFromSystemRead(enabled)
            }
    }

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

    func setInputScalar(_ value: Double, requestID: UUID = UUID()) {
        guard !hasStopped else { return }
        inputMonitor?.setScalar(value, requestID: requestID)
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
        // The monitor keeps the two surfaces separate: the popover owns the
        // 1 Hz usage poll, while Settings only keeps the device inventory live.
        inputMonitor?.setVisible(isPopoverVisible)
        inputMonitor?.setDeviceListVisible(isSettingsVisible)
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

    /// Starts and stops the LAN address read.
    ///
    /// It runs only while both conditions hold: the popover is open, and the
    /// Local IP row is switched on. Nothing draws the address in any other
    /// state, and the read walks the interface list, which is not a cost to pay
    /// for a row the user has not enabled.
    private func updateLocalIPActivation() {
        guard !hasStopped else { return }
        if isPopoverVisible, isLocalIPEnabled {
            localIP.activate()
        } else {
            localIP.deactivate()
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
        // The LAN address follows the primary link even when the connection
        // kind does not change — a cable swap, or a VPN taking the default
        // route — so a fresh read is asked for on every path update.
        localIP.refresh()
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
        associateCurrentBetterDisplayOutputIfNeeded()
        reconcileBluetoothDemand()
    }

    private func applyBetterDisplayCatalog(_ value: BetterDisplayCatalogUpdate) {
        guard betterDisplayState != value else { return }
        betterDisplayState = value
        associateCurrentBetterDisplayOutputIfNeeded()
    }

    private func associateCurrentBetterDisplayOutputIfNeeded() {
        guard !hasStopped, liveVolume.controlSource != .native,
              let settings = boundExternalVolumeSettings,
              let uid = liveVolume.currentDevice?.uid,
              betterDisplayState.outputUID == uid,
              betterDisplayState.isCatalogLoaded,
              let uuid = betterDisplayState.automaticDisplayUUID,
              betterDisplayState.devices.contains(where: { $0.uuid == uuid })
        else { return }
        let configuration = settings.externalVolumeConfiguration(for: uid)
        guard configuration.backend == .betterDisplay,
              configuration.betterDisplayUUID == nil
        else { return }
        settings.setExternalVolumeConfiguration(
            .init(backend: .betterDisplay, betterDisplayUUID: uuid), for: uid
        )
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
            canSetVolume: canSetVolume, canMute: canMute,
            muteState: muteState,
            externalVolumeTransitionGeneration:
                externalVolumeTransitionGeneration,
            controlSource: controlSource
        )
    }

    func replacingMuted(_ isMuted: Bool) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            currentDevice: currentDevice,
            outputDevices: outputDevices,
            canSetVolume: canSetVolume, canMute: canMute,
            muteState: isMuted ? .muted : .unmuted,
            externalVolumeTransitionGeneration:
                externalVolumeTransitionGeneration,
            controlSource: controlSource
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
