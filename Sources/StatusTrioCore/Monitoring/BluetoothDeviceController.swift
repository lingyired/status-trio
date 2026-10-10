import AppKit
@preconcurrency import CoreBluetooth
import Foundation

enum BluetoothWorkerResult: Sendable {
    case success([BluetoothDevice])
    case poweredOff
    case unavailable
    case failed
}

protocol BluetoothPairedDeviceReading: AnyObject {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void)
}

@MainActor
protocol BluetoothStateMonitoring: AnyObject {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)? { get set }
    var authorization: BluetoothAuthorizationStatus { get }
    func start()
    func stop()
}


/// Reads the operating system's paired-device database from the system
/// profiler. It deliberately does not perform a Bluetooth inquiry, so nearby
/// BLE advertisements never appear as paired devices.
///
/// The profiler is the only source of device names: `IOBluetoothDevice
/// .nameOrAddress` returns a cached name that keeps reporting the old value
/// after the device is renamed, while the profiler reports what the system
/// currently uses. Battery levels already come from the same report.
final class SystemProfilerBluetoothPairedDeviceWorker: @unchecked Sendable, BluetoothPairedDeviceReading {
    typealias OutputProvider = @Sendable () -> Data?
    private static let queueLabel = "StatusTrio.SystemProfilerBluetoothPairedDeviceWorker"

    /// Guards `queue`, `queueGeneration` and `hasOutstandingRead`. `read` is
    /// called from the controller's main-actor context while a retired queue's
    /// block may still be running, so the retirement state is read and written
    /// under this lock rather than on whatever thread happens to call in.
    private let stateLock = NSLock()
    private var queue = DispatchQueue(label: queueLabel, qos: .utility)
    private var queueGeneration: UInt64 = 0
    private var hasOutstandingRead = false
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothPairedDeviceWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        // A read that never returned would block this one behind it on the same
        // serial queue for the lifetime of the process, so retire that queue and
        // give this read a fresh one. The abandoned block keeps the old queue
        // alive until it eventually returns, which is what lets the controller's
        // watchdog retry a hung `/usr/sbin/system_profiler` at all.
        let generation: UInt64
        let currentQueue: DispatchQueue
        (generation, currentQueue) = stateLock.withLock {
            if hasOutstandingRead {
                queueGeneration &+= 1
                queue = DispatchQueue(label: Self.queueLabel, qos: .utility)
            }
            hasOutstandingRead = true
            return (queueGeneration, queue)
        }

        let outputProvider = self.outputProvider
        currentQueue.async { [weak self] in
            let result: BluetoothWorkerResult
            if let data = outputProvider(),
               let devices = BluetoothPairedDeviceReader.parse(json: data) {
                // The battery reader reuses these exact bytes instead of spawning a
                // second profiler moments later.
                self?.reportCache.store(data)
                result = .success(devices)
            } else {
                result = .failed
            }
            if let self {
                self.stateLock.withLock {
                    // Only the read on the current queue may clear the flag; a
                    // late completion from a retired queue must not, or the next
                    // read would queue behind a block that is still hung.
                    if generation == self.queueGeneration {
                        self.hasOutstandingRead = false
                    }
                }
            }
            completion(result)
        }
    }

    static func readSystemProfilerOutput() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}

enum BluetoothPairedDeviceReader {
    /// `nil` means the report could not be read at all; an empty array means the
    /// machine has no paired devices. The two stay distinct so a read failure is
    /// never displayed as an empty device list.
    static func parse(json: Data) -> [BluetoothDevice]? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              // The profiler wraps the sections in one more level, which JSON
              // reports as an array. A bare section is accepted too, so a
              // wrapped-versus-unwrapped change can never read as "no devices".
              let value = root["SPBluetoothDataType"] else {
            return nil
        }
        let sections: [[String: Any]]
        if let list = value as? [[String: Any]] {
            sections = list
        } else if let single = value as? [String: Any] {
            sections = [single]
        } else {
            return nil
        }

        var devices: [BluetoothDevice] = []
        // The addresses already listed, so one device draws one row.
        //
        // Every consumer treats the address as the device's identity:
        // `Identifiable.id` in the list, the battery-level lookup, the action
        // state and the pending disconnect confirmation. Two entries for one
        // address therefore draw the device twice, hand `ForEach` a duplicate id
        // — which SwiftUI leaves undefined — and share one set of state between
        // the two rows. The report can carry an address twice when a connect or
        // a disconnect is caught mid-flight, when a Mac has more than one
        // controller and the profiler reports a section per controller, or when
        // the paired-device database itself holds a duplicate. Reading the
        // collections connected-first makes that the precedence, so the entry
        // that survives is the one matching the state the device is in.
        var listedAddresses: Set<String> = []
        for section in sections {
            for (collectionKey, isConnected) in [
                ("device_connected", true),
                ("device_not_connected", false)
            ] {
                for entry in entries(from: section[collectionKey]) {
                    guard let properties = entry.properties,
                          let address = properties["device_address"] as? String,
                          !address.isEmpty,
                          !entry.name.isEmpty else {
                        continue
                    }
                    let key = BluetoothBatteryReader.normalizedAddress(address)
                    // An address the normalizer cannot reduce names no device,
                    // so two of them are not necessarily the same one and both
                    // stay.
                    if !key.isEmpty {
                        guard listedAddresses.insert(key).inserted else { continue }
                    }
                    let productID = BluetoothHexIdentifier.value(
                        from: properties["device_productID"] as? String
                    )
                    let vendorID = BluetoothHexIdentifier.value(
                        from: properties["device_vendorID"] as? String
                    )
                    let isUnpairedGhost = Self.isGhost(properties: properties)
                    let deviceKind = Self.kind(properties: properties)
                    let diagnosticRecord = AppleBluetoothAudioDiagnosticRecord.bluetooth(
                        name: entry.name,
                        address: address,
                        kind: deviceKind,
                        vendorID: vendorID,
                        productID: productID,
                        majorType: BluetoothDeviceKindResolver.majorTypeKeys
                            .compactMap { properties[$0] as? String }
                            .first,
                        minorType: BluetoothDeviceKindResolver.minorTypeKeys
                            .compactMap { properties[$0] as? String }
                            .first
                    )
                    devices.append(BluetoothDevice(
                        id: address,
                        name: entry.name,
                        kind: deviceKind,
                        isConnected: isConnected,
                        airPodsModel: AppleBluetoothAudioResolver.airPodsModel(
                            productID: productID,
                            vendorID: vendorID
                        ),
                        vendorID: vendorID,
                        productID: productID,
                        appleBluetoothAudioDiagnostic: diagnosticRecord,
                        isUnpairedGhost: isUnpairedGhost
                    ))
                }
            }
        }
        return devices
    }

    /// Each collection is a list whose entries map a device name to its
    /// properties. A single bare entry is accepted as well.
    private static func entries(from value: Any?) -> [(name: String, properties: [String: Any]?)] {
        let rawEntries: [Any]
        if let list = value as? [Any] {
            rawEntries = list
        } else if let single = value as? [String: Any], !single.isEmpty {
            rawEntries = [single]
        } else {
            return []
        }

        return rawEntries.flatMap { rawEntry -> [(name: String, properties: [String: Any]?)] in
            guard let entry = rawEntry as? [String: Any] else { return [] }
            return entry.map { (name: $0.key, properties: $0.value as? [String: Any]) }
        }
    }

    /// The class the report declares, resolved by the shared table. The
    /// resolution rules and the wording they cover live in
    /// `BluetoothDeviceKindResolver`, so the mapping is unit-tested against the
    /// strings macOS actually reports rather than against this call site.
    private static func kind(properties: [String: Any]) -> BluetoothDeviceKind {
        BluetoothDeviceKindResolver.kind(properties: properties)
    }

    /// A device the profiler could not classify: it carries neither
    /// `device_minorType` nor `device_minorClassOfDevice_string`. The system
    /// settings "My Devices" list shows only paired devices, and a
    /// never-paired scan entry is exactly the kind it omits, so this drives the
    /// panel's "hide devices not in System Settings" option. A device the stack
    /// has classified always carries one of those two keys.
    private static func isGhost(properties: [String: Any]) -> Bool {
        properties["device_minorType"] == nil
            && properties["device_minorClassOfDevice_string"] == nil
    }
}

/// CoreBluetooth supplies the app authorization and the asynchronous adapter
/// lifecycle; it is never used to enumerate devices. The paired-device database
/// comes from the system profiler above instead.
@MainActor
final class CoreBluetoothStateMonitor: NSObject, @preconcurrency CBCentralManagerDelegate, BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private var centralManager: CBCentralManager?

    var authorization: BluetoothAuthorizationStatus {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func start() {
        guard centralManager == nil else {
            publishState()
            return
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        publishState()
    }

    func stop() {
        centralManager?.delegate = nil
        centralManager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishState()
    }

    private func publishState() {
        onStateChange?(authorization, managerState())
    }

    private func managerState() -> BluetoothManagerState {
        switch centralManager?.state ?? .unknown {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }
}

@MainActor
final class BluetoothDeviceController: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var availability: BluetoothAvailability = .idle
    @Published private(set) var batteryLevels: [String: BluetoothBatteryLevel] = [:]
    @Published private(set) var nearbyBatteryDevices: [NearbyBluetoothBatteryDevice] = []
    /// Whether the last level read failed outright.
    ///
    /// `batteryLevels` cannot say it: an empty dictionary is also what a report
    /// without any readable level looks like.
    @Published private(set) var batteryLevelsReadFailed = false

    private let worker: any BluetoothPairedDeviceReading
    private let appleBluetoothAudioDiagnosticReporter: AppleBluetoothAudioDiagnosticReporter
    /// The state monitor is teardown-owned storage: `deinit` is nonisolated, so
    /// it is held `nonisolated(unsafe)` for that one read. `BluetoothStateMonitoring`
    /// is `@MainActor`, and `stop()` runs on the main actor through the hop in
    /// `deinit` rather than being called off the queue CoreBluetooth was created on.
    nonisolated(unsafe) private let stateMonitor: any BluetoothStateMonitoring
    private let batteryReader: any BluetoothBatteryReading
    /// `deinit` is nonisolated, and the scanner has to be stopped on the main
    /// actor because its CoreBluetooth manager and delegates were created there.
    /// This is teardown-owned storage, captured by the main-actor hop below.
    nonisolated(unsafe) private let nearbyBatteryScanner: (any BluetoothLEBatteryScanning)?
    /// The second battery source, read only for the devices the paired-device
    /// report carries no level for. Optional so a test can build a controller
    /// that never spawns `/usr/bin/pmset`.
    private let accessoryBatteryReader: (any BluetoothAccessoryBatteryReading)?
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    /// The AppKit and workspace registrations, kept in teardown-owned storage so
    /// a nonisolated `deinit` can release them.
    private let systemObservers: SystemEventObserverBag

    /// How often the safety net re-reads the paired-device database while a
    /// Bluetooth surface is visible. Connection notifications deliver the
    /// interesting changes, so this is deliberately slow.
    private let safetyNetInterval: Duration
    private let safetyNetSleep: @Sendable (Duration) async throws -> Void
    /// The connect/disconnect source for the safety net. Optional so a test can
    /// build a controller that never touches the system's Bluetooth service.
    /// Teardown-owned storage: `deinit` is nonisolated and reads it directly.
    nonisolated(unsafe)    private let connectionEvents: (any BluetoothConnectionEventMonitoring)?
    /// The accessory battery-change source. Optional so a test can build a
    /// controller that never touches the system's notification centre, and
    /// teardown-owned storage for the same reason the connect source is:
    /// `deinit` is nonisolated and reads it directly.
    nonisolated(unsafe) private let accessoryBatteryEvents: (any BluetoothAccessoryBatteryEventMonitoring)?
    private let connectionEventDebounceInterval: Duration
    private let connectionEventDebounceSleep: @Sendable (Duration) async throws -> Void
    /// The accessory battery debounce. It is longer than the connect/disconnect
    /// one on purpose: the power manager posts an accessory notification fairly
    /// often while that accessory discharges, and the safety-net poll still runs
    /// behind this as the source that catches whatever no notification delivered.
    private let accessoryBatteryEventDebounceInterval: Duration
    private let accessoryBatteryEventDebounceSleep: @Sendable (Duration) async throws -> Void
    /// Invalidates a debounce that a later stop or deactivate superseded, the
    /// same way `AsyncRequestGate` guards the other asynchronous paths here.
    private var connectionEventGate = AsyncRequestGate()
    private var isConnectionEventReadScheduled = false
    /// Set from the registration result, so "monitoring" means the system
    /// accepted the registration rather than that it was merely attempted.
    private var isMonitoringConnectionEventNotifications = false
    /// The accessory battery debounce latch and gate, shaped exactly like the
    /// connect-event pair above: one read per burst, and a late completion from a
    /// superseded debounce cannot start a read the next registration did not ask
    /// for.
    private var accessoryBatteryEventGate = AsyncRequestGate()
    private var isAccessoryBatteryEventReadScheduled = false
    /// Set from the registration result, so "monitoring" means the system
    /// accepted the registration rather than that it was merely attempted.
    private var isMonitoringAccessoryBatteryNotifications = false
    private(set) var isActive = false
    private var batteryRequestGate = AsyncRequestGate()
    /// One device read at a time, with at most one coalesced follow-up. Without
    /// this, every trigger started its own `/usr/sbin/system_profiler` process.
    private var isDeviceReadInFlight = false
    private var isRefreshPending = false
    /// Identifies the current device read. A completion that belongs to a
    /// superseded token — invalidated, or abandoned by the watchdog — is
    /// discarded, so it can neither publish devices nor release the latch of the
    /// read that replaced it.
    private var readToken: UInt64 = 0
    /// Declares a read stuck once it has been outstanding for too long, so a
    /// hung `/usr/sbin/system_profiler` — a subprocess, so it can hang — cannot
    /// freeze the device row for the rest of the session. The worker moves the
    /// retry to a fresh queue, so the follow-up does not land behind the hung
    /// block on the queue it stalled.
    private let readWatchdog: ReadWatchdog
    private var batteryLevelsEnabled = false
    private var periodicRefreshTask: Task<Void, Never>?
    /// Identifies the current safety-net task. A cancelled task's `defer` only
    /// clears the reference while it is still the current generation, so a
    /// stop/start pair in one main-actor turn cannot leave the new task
    /// untracked and uncancellable.
    private var periodicRefreshGeneration: UInt64 = 0
    private let nearbyBatteryCacheLifetime = BluetoothLEBatteryScanPolicy.resultLifetime
    private var nearbyBLEReadPermit: Set<UUID> = []
    private var nearbyBLEInitialReadPermit: Set<UUID> = []
    private var nearbyBLEInitialReadSuppressedUntil: [UUID: Date] = [:]
    private var nearbyBLEReadRevisions: [UUID: UInt64] = [:]
    private var nearbyBatteryCacheExpirationTask: Task<Void, Never>?
    private var nearbyBatteryCacheGeneration: UInt64 = 0
    private var nearbyRowExpiryTask: Task<Void, Never>?
    private var nearbyRowExpiryGeneration: UInt64 = 0
    private var nearbyBatteryLevelsEnabled = true
    private var nearbyBLEEnabled = false
    private var nearbyBLEHiddenIDs: Set<UUID> = []
    private var nearbyPersistedSelections: [NearbyBLEDeviceSelection] = []
    private var nearbyBLEDiscoveryRequests: Set<String> = []
    private var nearbyBLEListVisible = true
    private var nearbyBLEBackgroundRefreshEnabled = false
    private var nearbyBLEBackgroundSelectedIDs: Set<UUID> = []
    private var nearbyBLEBackgroundRefreshInterval: Duration?
    private var nearbyBLESystemSleeping = false
    private var visibleNearbyBLERequests: [String: Set<UUID>] = [:]
    private var nearbyScannerGeneration: UInt64 = 0
    private var nearbyScannerCallbackIsInstalled = false

    /// The action in flight, or the failure still on screen, keyed by normalized
    /// address. No entry means the row reports the device's own state.
    @Published private(set) var deviceActionStates: [String: BluetoothDeviceActionState] = [:]

    /// The device whose disconnect is waiting for the user to confirm it, by
    /// normalized address.
    ///
    /// This belongs to the controller rather than to a view because the popover
    /// keeps its content view controller — and so its SwiftUI state — alive for a
    /// minute after a close, which is why a view's `onDisappear` never runs when
    /// the panel is closed from the summary. The panel's close is what has to
    /// cancel an unanswered confirmation, and `SystemStatusStore` already handles
    /// exactly that event for the battery page and the surface claim.
    @Published private(set) var pendingDisconnectConfirmation: String?

    @Published private(set) var nearbyBLECandidates: [NearbyBLEDeviceCandidate] = []
    @Published private(set) var nearbyBLEReadFailures: Set<UUID> = []
    @Published private(set) var isDiscoveringNearbyBLEDevices = false

    private let actionPerformer: any BluetoothDeviceActionPerforming
    private let actionTimeout: Duration
    private let actionTimeoutSleep: @Sendable (Duration) async throws -> Void
    private let failureVisibleDuration: Duration
    private let failureVisibleSleep: @Sendable (Duration) async throws -> Void
    private var actionTimeouts: [String: Task<Void, Never>] = [:]
    private var failureClearTasks: [String: Task<Void, Never>] = [:]
    /// Identifies the current request per device. A late completion from a
    /// superseded request must not decide the outcome of the one that replaced
    /// it — an action's result comes from its own request and report pair only.
    private var deviceActionTokens: [String: UInt64] = [:]
    /// Monotonic across the controller, so clearing the map can never hand an old
    /// token to a new request (a per-address gate would restart at zero).
    private var deviceActionTokenCounter: UInt64 = 0

    init(
        worker: any BluetoothPairedDeviceReading = SystemProfilerBluetoothPairedDeviceWorker(),
        appleBluetoothAudioDiagnosticReporter: AppleBluetoothAudioDiagnosticReporter = AppleBluetoothAudioDiagnosticReporter(),
        stateMonitor: any BluetoothStateMonitoring = CoreBluetoothStateMonitor(),
        batteryReader: any BluetoothBatteryReading = SystemProfilerBluetoothBatteryWorker(),
        accessoryBatteryReader: (any BluetoothAccessoryBatteryReading)? = nil,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        safetyNetInterval: Duration = .seconds(30),
        safetyNetSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        systemObservers: SystemEventObserverBag? = nil,
        connectionEvents: (any BluetoothConnectionEventMonitoring)? = nil,
        accessoryBatteryEvents: (any BluetoothAccessoryBatteryEventMonitoring)? = nil,
        connectionEventDebounceInterval: Duration = .milliseconds(750),
        connectionEventDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        accessoryBatteryEventDebounceInterval: Duration = .seconds(3),
        accessoryBatteryEventDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        readTimeout: Duration = .seconds(5),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        actionPerformer: any BluetoothDeviceActionPerforming = IOBluetoothDeviceActionPerformer(),
        actionTimeout: Duration = .seconds(10),
        actionTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        failureVisibleDuration: Duration = .seconds(4),
        failureVisibleSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        nearbyBatteryScanner: (any BluetoothLEBatteryScanning)? = nil,
    ) {
        self.worker = worker
        self.appleBluetoothAudioDiagnosticReporter = appleBluetoothAudioDiagnosticReporter
        self.stateMonitor = stateMonitor
        self.batteryReader = batteryReader
        self.nearbyBatteryScanner = nearbyBatteryScanner
        self.accessoryBatteryReader = accessoryBatteryReader
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.safetyNetInterval = safetyNetInterval
        self.safetyNetSleep = safetyNetSleep
        // The default bag reaches the same centers the controller was given, so
        // an injected `NotificationCenter` keeps driving the controller.
        self.systemObservers = systemObservers ?? SystemEventObserverBag(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        self.connectionEvents = connectionEvents
        self.accessoryBatteryEvents = accessoryBatteryEvents
        self.connectionEventDebounceInterval = connectionEventDebounceInterval
        self.connectionEventDebounceSleep = connectionEventDebounceSleep
        self.accessoryBatteryEventDebounceInterval = accessoryBatteryEventDebounceInterval
        self.accessoryBatteryEventDebounceSleep = accessoryBatteryEventDebounceSleep
        readWatchdog = ReadWatchdog(
            baseTimeout: readTimeout,
            maxTimeout: .seconds(60),
            sleep: readTimeoutSleep
        )
        self.actionPerformer = actionPerformer
        self.actionTimeout = actionTimeout
        self.actionTimeoutSleep = actionTimeoutSleep
        self.failureVisibleDuration = failureVisibleDuration
        self.failureVisibleSleep = failureVisibleSleep
        stateMonitor.onStateChange = { [weak self] authorization, managerState in
            self?.receiveSystemState(authorization: authorization, managerState: managerState)
        }
    }

    deinit {
        periodicRefreshTask?.cancel()
        nearbyBatteryCacheExpirationTask?.cancel()
        // Releasing the registrations here is the whole point: an observer token
        // that is never removed keeps the center's block alive for the life of
        // the process.
        systemObservers.removeAll()
        connectionEvents?.stop()
        accessoryBatteryEvents?.stop()
        // `CBCentralManager` retains its delegate, so the state monitor is never
        // deallocated while it is running. `stop()` has to run on the main actor,
        // which is the queue the manager was created with, so the reference is
        // captured and handed over instead of `self` being used after death.
        let stateMonitor = stateMonitor
        Task { @MainActor in stateMonitor.stop() }
        let nearbyBatteryScanner = nearbyBatteryScanner
        Task { @MainActor in
            nearbyBatteryScanner?.onDevicesChanged = nil
            nearbyBatteryScanner?.onCandidatesChanged = nil
            nearbyBatteryScanner?.onReadFailures = nil
            nearbyBatteryScanner?.onIsScanningChanged = nil
            nearbyBatteryScanner?.setAllowedReadDeviceIDs([])
            nearbyBatteryScanner?.stop()
        }
    }


    var connectedDevices: [BluetoothDevice] {
        BluetoothDevicePresentation.grouped(devices).connected
    }

    /// Whether the controller has an event source at all.
    var hasConnectionEventSource: Bool {
        connectionEvents != nil
    }

    /// Whether connection notifications are being delivered right now.
    var isMonitoringConnectionEvents: Bool {
        isMonitoringConnectionEventNotifications
    }

    /// Whether the controller has an accessory battery-change source at all.
    var hasAccessoryBatteryEventSource: Bool {
        accessoryBatteryEvents != nil
    }

    /// Whether accessory battery notifications are being delivered right now.
    var isMonitoringAccessoryBatteryEvents: Bool {
        isMonitoringAccessoryBatteryNotifications
    }

    /// The app's current CoreBluetooth grant. Reading it never prompts; only
    /// starting the state monitor does.
    var authorization: BluetoothAuthorizationStatus {
        stateMonitor.authorization
    }

    /// A published mirror of `authorization` that changes only while the state
    /// monitor is active, so UI that needs to react to a permission decision
    /// (such as re-surfacing the Settings window after a system prompt) can
    /// subscribe without polling `CBManager.authorization` directly.
    @Published private(set) var authorizationStatus: BluetoothAuthorizationStatus = .notDetermined

    func prepareForPresentation() {
        guard !isActive else { return }
        switch stateMonitor.authorization {
        case .notDetermined:
            availability = .authorizationNotDetermined
        case .denied:
            availability = .authorizationDenied
        case .restricted:
            availability = .authorizationRestricted
        case .allowed:
            availability = .idle
        }
        authorizationStatus = stateMonitor.authorization
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        systemObservers.install(
            applicationActivated: { [weak self] in
                Task { @MainActor in self?.refreshAfterSystemEvent() }
            },
            didWake: { [weak self] in
                Task { @MainActor in self?.refreshAfterSystemEvent() }
            }
        )
        stateMonitor.start()
        schedulePeriodicRefresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        invalidateDeviceRead()
        stopNearbyBatteryScanner(clearResults: true)
        batteryLevelRequests.removeAll()
        updateBatteryLevelRequests()
        stopAccessoryBatteryEvents()
        stopPeriodicRefresh()
        systemObservers.removeAll()
        stateMonitor.stop()
        clearDeviceActions()
        availability = .idle
    }

    func refresh() {
        guard isActive, availability == .available else { return }
        // Coalesce bursts: at most one read and one follow-up are retained,
        // whatever order the triggers arrive in.
        guard !isDeviceReadInFlight else {
            isRefreshPending = true
            return
        }
        isDeviceReadInFlight = true
        readToken &+= 1
        let token = readToken
        readWatchdog.arm { [weak self] in
            self?.abandonTimedOutRead(token: token)
        }
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                // A completion that arrives after the read was declared stuck,
                // or after a later trigger superseded it, belongs to a retired
                // token: it must not release the latch of the read that
                // replaced it, let alone publish over it.
                guard let self, token == self.readToken else { return }
                self.readWatchdog.cancel()
                self.readWatchdog.recordSuccess()
                self.isDeviceReadInFlight = false
                guard self.isActive else { return }
                switch result {
                case let .success(devices):
                    devices.compactMap(\.appleBluetoothAudioDiagnostic).forEach {
                        self.appleBluetoothAudioDiagnosticReporter.report($0)
                    }
                    self.devices = devices
                    self.reconcileDeviceActions()
                    self.availability = .available
                    self.refreshBatteryLevels()
                case .poweredOff:
                    self.availability = .poweredOff
                    self.clearBatteryLevels()
                    self.stopPeriodicRefresh()
                case .unavailable:
                    self.availability = .unavailable
                    self.clearBatteryLevels()
                    self.stopPeriodicRefresh()
                case .failed:
                    self.availability = .failed
                    self.clearBatteryLevels()
                    // No poll can succeed while the read is failing, so the
                    // connection-event registration goes with it: otherwise the
                    // controller would hold a live event registration with no
                    // poll behind it, which is a state no other branch leaves.
                    self.stopPeriodicRefresh()
                }
                if self.isRefreshPending {
                    self.isRefreshPending = false
                    self.refresh()
                }
            }
        }
    }

    /// Performs the paired-device refresh requested by the user and explicitly
    /// asks the Nearby scanner for a new bounded scan when its surface is active.
    /// The ordinary safety-net `refresh()` path never reaches CoreBluetooth.
    func refreshFromUser() {
        refresh()
        guard isNearbyBLEScannerDemanded else { return }
        nearbyBatteryScanner?.refresh()
    }

    /// A system read never returned. Ignore its late completion, release the
    /// single-read latch so the controller is not stuck forever, and start the
    /// coalesced follow-up. The worker moves that retry to a fresh queue, which
    /// is what makes this recovery actually run instead of landing behind the
    /// block that is still hung.
    private func abandonTimedOutRead(token: UInt64) {
        guard token == readToken else { return }
        readToken &+= 1
        isDeviceReadInFlight = false
        // The follow-up started below consumes the coalesced trigger, so the
        // flag has to be cleared here. Leaving it set made the replacement read
        // consume an already-consumed trigger and run one extra profiler pass
        // after every timeout.
        isRefreshPending = false
        refresh()
    }

    /// Invalidates any in-flight device read. The completion that belongs to the
    /// invalidated read is discarded, so the latch has to be released here or no
    /// later refresh could ever start. The watchdog is disarmed for the same
    /// reason: nothing is outstanding any more, and its timeout would otherwise
    /// abandon a read that is already gone. Recording a success with the
    /// cancellation resets the backoff, so a session that deactivated after a
    /// timeout starts again from the 5 s base instead of the previous penalty.
    private func invalidateDeviceRead() {
        readToken &+= 1
        readWatchdog.cancel()
        readWatchdog.recordSuccess()
        isDeviceReadInFlight = false
        isRefreshPending = false
    }

    /// Surfaces that need battery levels, by token. Two of them share this need
    /// — the summary row (for the AirPods it reports) and the detail page (for
    /// every device) — and SwiftUI may run the outgoing surface's disappear hook
    /// either before or after the incoming surface's appear hook. A count makes
    /// the outcome independent of that order, where a single boolean let the
    /// last writer win and left the detail page reading nothing.
    private var batteryLevelRequests: Set<String> = []

    /// Applies the Apple-device feature and persisted UUID metadata. UUIDs are
    /// identities, not a read allowlist; a read still requires a visible row.
    func configureNearbyBLEDevices(
        enabled: Bool,
        knownIDs _: Set<UUID>,
        hiddenIDs: Set<UUID>,
        batteryLevelsEnabled: Bool = true,
        listVisible: Bool = true,
        persistedSelections: [NearbyBLEDeviceSelection] = []
    ) {
        let oldHiddenIDs = nearbyBLEHiddenIDs
        guard nearbyBLEEnabled != enabled
            || nearbyBLEHiddenIDs != hiddenIDs || nearbyBatteryLevelsEnabled != batteryLevelsEnabled
            || nearbyBLEListVisible != listVisible || nearbyPersistedSelections != persistedSelections else { return }
        nearbyBatteryLevelsEnabled = batteryLevelsEnabled
        nearbyBLEEnabled = enabled
        nearbyBLEHiddenIDs = hiddenIDs
        nearbyBLEListVisible = listVisible
        nearbyPersistedSelections = persistedSelections
        let newlyHidden = hiddenIDs.subtracting(oldHiddenIDs)
        if !newlyHidden.isEmpty { nearbyBatteryScanner?.revokeReadDeviceIDs(newlyHidden) }
        nearbyBatteryDevices.removeAll { hiddenIDs.contains($0.id) }
        nearbyBLEReadFailures.subtract(hiddenIDs)
        if !enabled {
            nearbyBatteryDevices = []
            nearbyBLEReadFailures = []
            nearbyBLECandidates = []
        }
        scheduleNearbyRowExpiry()
        updateNearbyBatteryScanner()
    }

    /// Compatibility with the 1.5 presentation-state path: a surface that
    /// explicitly opted into Nearby readings claims the scanner. The actual
    /// read permit still comes from visible rows, so this cannot widen reads.
    func requestNearbyBatteryDevices(_ token: String) {
        requestNearbyBLEDiscovery(token)
    }

    /// Compatibility with the 1.5 presentation-state path. Releasing a scan
    /// claim keeps cached readings only when the caller says the surface may
    /// come back; an opt-out still clears them.
    func releaseNearbyBatteryDevices(_ token: String, keepingResults: Bool = false) {
        let wasClaimed = nearbyBLEDiscoveryRequests.remove(token) != nil
        releaseVisibleNearbyBLEDevices(token)
        if wasClaimed || !keepingResults {
            updateNearbyBatteryScanner()
        }
        if !keepingResults, nearbyBLEDiscoveryRequests.isEmpty {
            nearbyBatteryDevices = []
            nearbyBLEReadFailures = []
            nearbyBLECandidates = []
        }
    }

    /// Requests a bounded discovery scan. Discovery does not add UUIDs to the
    /// GATT read permit.
    func requestNearbyBLEDiscovery(_ token: String) {
        guard nearbyBLEEnabled else { return }
        let inserted = nearbyBLEDiscoveryRequests.insert(token).inserted
        let wasRunning = nearbyBatteryScanner?.isRunning == true
        updateNearbyBatteryScanner()
        if inserted, wasRunning, isNearbyBLEScannerDemanded {
            nearbyBatteryScanner?.refresh()
        }
    }

    func refreshNearbyBLEDiscovery(_ token: String) {
        guard nearbyBLEEnabled,
              nearbyBLEDiscoveryRequests.contains(token),
              isNearbyBLEScannerDemanded else { return }
        nearbyBatteryScanner?.refresh()
    }

    func releaseNearbyBLEDiscovery(_ token: String) {
        guard nearbyBLEDiscoveryRequests.remove(token) != nil else { return }
        updateNearbyBatteryScanner()
    }

    /// Read eligibility is limited to UUID rows actually visible in an active
    /// Bluetooth summary panel; known metadata never grants a read.
    func setVisibleNearbyBLEDevices(_ ids: Set<UUID>, for token: String) {
        visibleNearbyBLERequests[token] = ids
        updateNearbyBatteryScanner()
    }

    func setNearbyBLEBackgroundRefresh(enabled: Bool, selectedIDs: Set<UUID>, interval: Duration? = nil) {
        guard nearbyBLEBackgroundRefreshEnabled != enabled
            || nearbyBLEBackgroundSelectedIDs != selectedIDs
            || nearbyBLEBackgroundRefreshInterval != interval else { return }
        nearbyBLEBackgroundRefreshEnabled = enabled
        nearbyBLEBackgroundSelectedIDs = selectedIDs
        nearbyBLEBackgroundRefreshInterval = enabled ? interval : nil
        nearbyBatteryScanner?.setBackgroundRefreshInterval(nearbyBLEBackgroundRefreshInterval)
        updateNearbyBatteryScanner()
    }

    func setSystemSleeping(_ sleeping: Bool) {
        guard nearbyBLESystemSleeping != sleeping else { return }
        nearbyBLESystemSleeping = sleeping
        if sleeping {
            nearbyBatteryScanner?.stop()
            isDiscoveringNearbyBLEDevices = false
        } else {
            updateNearbyBatteryScanner()
        }
    }

    var backgroundReadNearbyBLEDeviceIDs: Set<UUID> {
        nearbyBLEBackgroundRefreshEnabled
            ? nearbyBLEBackgroundSelectedIDs.subtracting(nearbyBLEHiddenIDs)
            : []
    }

    func releaseVisibleNearbyBLEDevices(_ token: String) {
        guard visibleNearbyBLERequests.removeValue(forKey: token) != nil else { return }
        updateNearbyBatteryScanner()
    }

    /// Claims battery levels for a surface. The read starts when the first
    /// claim arrives and stops when the last one is released.
    func requestBatteryLevels(_ token: String) {
        guard batteryLevelRequests.insert(token).inserted else {
            // The claim is already held: keep the reading warm.
            refreshBatteryLevels()
            return
        }
        updateBatteryLevelRequests()
    }

    /// Releases a surface's claim, whatever the order it arrives in.
    func releaseBatteryLevels(_ token: String) {
        guard batteryLevelRequests.remove(token) != nil else { return }
        updateBatteryLevelRequests()
    }

    private func updateBatteryLevelRequests() {
        let enabled = !batteryLevelRequests.isEmpty
        guard batteryLevelsEnabled != enabled else {
            if enabled {
                refreshBatteryLevels()
                updateAccessoryBatteryEvents()
            }
            return
        }
        batteryLevelsEnabled = enabled
        // Levels read for a released claim must not outlive it.
        clearBatteryLevels()
        // The registration follows the claim: it is only worth holding while a
        // surface is actually showing levels.
        updateAccessoryBatteryEvents()
        if enabled {
            refreshBatteryLevels()
        }
    }

    /// Whether a visible surface has asked for battery levels.
    var isBatteryLevelsRequested: Bool {
        batteryLevelsEnabled
    }

    /// Surfaces that show Bluetooth device state, by token. Every claim is
    /// recorded so insertion and removal stay order-independent, but only the
    /// popover-level claim sustains the safety-net poll.
    private var visibleSurfaces: Set<String> = []

    /// The popover-level claim. `SystemStatusStore` holds it while the popover is
    /// open and releases it on close, so it is the only claim that can start the
    /// poll. The view-level claim (`"bluetooth.summary.surface"` in
    /// `BluetoothStatusView`) is released
    /// only from SwiftUI `onDisappear`, and the popover's content view
    /// controller is retained after close: a skipped `onDisappear` would
    /// otherwise leave the claim set non-empty and restart a 30 s poll for the
    /// life of the process. A view claim may only narrow this one, never
    /// sustain the poll on its own.
    static let popoverSurfaceToken = "bluetooth.popover"
    static let bluetoothSummarySurfaceToken = "bluetooth.summary.surface"

    /// Whether the popover is showing Bluetooth device state. A leaked view
    /// claim cannot make this true.
    var hasVisibleSurface: Bool {
        visibleSurfaces.contains(Self.popoverSurfaceToken)
    }

    private var hasBluetoothSummarySurface: Bool {
        visibleSurfaces.contains(Self.bluetoothSummarySurfaceToken)
    }

    /// Whether the safety-net poll is running.
    var isSafetyNetPolling: Bool {
        periodicRefreshTask != nil
    }

    /// Claims the safety net for a visible Bluetooth surface.
    func holdVisibleSurface(_ token: String) {
        guard visibleSurfaces.insert(token).inserted else { return }
        schedulePeriodicRefresh()
        updateNearbyBatteryScanner()
    }

    /// Releases a surface's claim, whatever order it arrives in. Releasing the
    /// popover claim stops the poll even while a view claim is still held.
    func releaseVisibleSurface(_ token: String) {
        guard visibleSurfaces.remove(token) != nil else { return }
        if !hasVisibleSurface { stopPeriodicRefresh() }
        // Settings may still own discovery without a panel. Recompute the
        // permit independently so closing the panel revokes GATT immediately.
        updateNearbyBatteryScanner()
    }

    private func receiveSystemState(
        authorization: BluetoothAuthorizationStatus,
        managerState: BluetoothManagerState
    ) {
        guard isActive else { return }
        let mappedAvailability = BluetoothAvailabilityMapper.preliminary(
            authorization: authorization,
            managerState: managerState
        )
        availability = mappedAvailability
        authorizationStatus = authorization
        if mappedAvailability != .available {
            nearbyBLESystemSleeping = true
        } else {
            nearbyBLESystemSleeping = false
        }

        if mappedAvailability == .available {
            schedulePeriodicRefresh()
            refresh()
            updateNearbyBatteryScanner()
        } else {
            invalidateDeviceRead()
            clearBatteryLevels()
            stopPeriodicRefresh()
            stopNearbyBatteryScanner(clearResults: true)
        }
    }

    private func refreshBatteryLevels() {
        guard isActive, batteryLevelsEnabled, availability == .available else { return }
        let request = batteryRequestGate.advance()
        batteryReader.read { [weak self] levels in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.batteryLevelsEnabled,
                      self.availability == .available,
                      self.batteryRequestGate.accepts(request) else {
                    return
                }
                // `nil` is a report that could not be read, which is a different
                // state from a report that carries no level for any device: the
                // panel reports it once instead of staying silent.
                self.batteryLevelsReadFailed = levels == nil
                self.batteryLevels = levels ?? [:]
                // The primary source is published first and on its own. The
                // second source is an addition to it, never a precondition for
                // it, so a read that never answers cannot hold the list back.
                self.readAccessoryLevelsIfNeeded(request: request, levels: levels)
            }
        }
    }

    /// Reads the accessory power sources for the devices the paired-device
    /// report carried no level for, and adds what they supply.
    ///
    /// The primary levels stay published while this read is in flight, and the
    /// merge copies them through untouched: this can add a level for a device the
    /// report cannot describe, and cannot change or remove one it can. The gate
    /// is the same request token, so a merge that lands after a newer read
    /// superseded this one is dropped rather than published over it.
    private func readAccessoryLevelsIfNeeded(
        request: UInt64,
        levels: [String: BluetoothBatteryLevel]?
    ) {
        guard let accessoryBatteryReader else { return }
        guard BluetoothBatteryLevelFallback.isNeeded(levels: levels, devices: devices) else {
            return
        }
        let devices = devices
        accessoryBatteryReader.read { [weak self] accessories in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.batteryLevelsEnabled,
                      self.availability == .available,
                      self.batteryRequestGate.accepts(request) else {
                    return
                }
                // A source that could not be read adds no failure of its own:
                // the primary read's verdict stands, and a second line saying the
                // same thing would only repeat it.
                guard let accessories else { return }
                let merged = BluetoothBatteryLevelFallback.merged(
                    levels: self.batteryLevels,
                    accessories: accessories,
                    devices: devices
                )
                self.batteryLevels = merged
                // The report's failure is cleared exactly when the second source
                // gave the list something to show. A failed report that still
                // leaves every row silent keeps its line, so the panel never goes
                // quiet about a read that failed outright.
                if !merged.isEmpty {
                    self.batteryLevelsReadFailed = false
                }
            }
        }
    }

    private func clearBatteryLevels() {
        _ = batteryRequestGate.advance()
        batteryLevelsReadFailed = false
        batteryLevels = [:]
    }

    private var currentNearbyBLEReadPermit: Set<UUID> {
        guard nearbyBLEEnabled, nearbyBatteryLevelsEnabled,
              isActive,
              availability == .available,
              !nearbyBLESystemSleeping,
              (hasVisibleSurface && hasBluetoothSummarySurface || nearbyBLEBackgroundRefreshEnabled) else { return [] }
        let visible = visibleNearbyBLERequests.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        let permitted = nearbyBLEBackgroundRefreshEnabled
            ? visible.union(nearbyBLEBackgroundSelectedIDs)
            : visible
        return permitted.subtracting(nearbyBLEHiddenIDs)
    }

    private var isNearbyBLEScannerDemanded: Bool {
        isActive && availability == .available && nearbyBLEEnabled
            && !nearbyBLESystemSleeping
            && (hasVisibleSurface && hasBluetoothSummarySurface || nearbyBLEBackgroundRefreshEnabled)
    }

    private var hasActiveNearbyBLEDiscoverySurface: Bool {
        hasVisibleSurface && hasBluetoothSummarySurface || nearbyBLEBackgroundRefreshEnabled
    }

    private var currentNearbyBLEInitialReadPermit: Set<UUID> {
        guard nearbyBLEEnabled, nearbyBatteryLevelsEnabled, nearbyBLEListVisible,
              isActive, availability == .available,
              !nearbyBLESystemSleeping,
              (hasActiveNearbyBLEDiscoverySurface || nearbyBLEBackgroundRefreshEnabled),
              let nearbyBatteryScanner else { return [] }
        let now = Date()
        nearbyBLEInitialReadSuppressedUntil = nearbyBLEInitialReadSuppressedUntil.filter {
            BluetoothLEInitialReadPolicy.shouldSuppressInitialRead(until: $0.value, now: now)
        }
        return BluetoothLEInitialReadPolicy.permittedCandidateIDs(
            enabled: nearbyBLEEnabled,
            batteryLevelsEnabled: nearbyBatteryLevelsEnabled,
            hasActiveDiscoverySurface: hasActiveNearbyBLEDiscoverySurface,
            showsDeviceList: nearbyBLEListVisible,
            candidateIDs: nearbyBLEBackgroundRefreshEnabled
                ? nearbyBLEBackgroundSelectedIDs.union(nearbyBatteryScanner.discoveredCandidates.filter { $0.vendor == .apple }.map(\.id))
                : Set(nearbyBatteryScanner.discoveredCandidates.filter { $0.vendor == .apple }.map(\.id)),
            hiddenIDs: nearbyBLEHiddenIDs
        ).subtracting(nearbyBLEReadPermit)
            .subtracting(nearbyBLEBackgroundRefreshEnabled
                ? []
                : BluetoothLEInitialReadPolicy.freshVerifiedIDs(nearbyPersistedSelections, now: now))
            .subtracting(Set(nearbyBLEInitialReadSuppressedUntil.compactMap { id, deadline in
                BluetoothLEInitialReadPolicy.shouldSuppressInitialRead(until: deadline, now: now) ? id : nil
            }))
    }

    private func updateNearbyBatteryScanner() {
        guard let nearbyBatteryScanner else {
            nearbyBLEReadPermit = currentNearbyBLEReadPermit
            return
        }
        let newPermit = currentNearbyBLEReadPermit
        let newInitialPermit = currentNearbyBLEInitialReadPermit
        let oldCombinedPermit = nearbyBLEReadPermit.union(nearbyBLEInitialReadPermit)
        let newCombinedPermit = newPermit.union(newInitialPermit)
        for id in oldCombinedPermit.subtracting(newCombinedPermit) {
            nearbyBLEReadRevisions[id, default: 0] &+= 1
        }
        nearbyBLEReadPermit = newPermit
        nearbyBatteryScanner.setAllowedReadDeviceIDs(newPermit)
        nearbyBLEInitialReadPermit = newInitialPermit
        nearbyBatteryScanner.setInitialReadCandidateIDs(newInitialPermit)
        if newInitialPermit.isEmpty { nearbyBLECandidates = [] }

        guard isNearbyBLEScannerDemanded else {
            if nearbyBatteryScanner.isRunning || nearbyScannerCallbackIsInstalled {
                stopNearbyBatteryScanner(clearResults: !nearbyBLEEnabled)
            } else if !nearbyBLEEnabled {
                nearbyBatteryDevices = []
                nearbyBLEReadFailures = []
                nearbyBLECandidates = []
            }
            return
        }

        pruneNearbyBatteryCache(at: Date())
        guard !nearbyBatteryScanner.isRunning else { return }
        nearbyScannerGeneration &+= 1
        let generation = nearbyScannerGeneration
        nearbyScannerCallbackIsInstalled = true
        nearbyBatteryScanner.onDevicesChanged = { [weak self] devices in
            guard let self else { return }
            // Capture the read permit at callback time, before hopping to the main
            // actor. A revocation followed by re-selection cannot bless a stale
            // aggregate callback from the prior scanner session.
            let permitAtCallback = self.nearbyBLEReadPermit.union(self.nearbyBLEInitialReadPermit)
            let revisionsAtCallback = self.nearbyBLEReadRevisions
            Task { @MainActor [weak self] in
                self?.receiveNearbyBatteryDevices(
                    devices,
                    permittedIDs: permitAtCallback,
                    revisions: revisionsAtCallback,
                    generation: generation
                )
            }
        }
        nearbyBatteryScanner.onCandidatesChanged = { [weak self] candidates in
            Task { @MainActor [weak self] in
                guard let self, generation == self.nearbyScannerGeneration,
                      self.isNearbyBLEScannerDemanded else { return }
                _ = candidates
                self.updateNearbyBatteryScanner()
            }
        }
        nearbyBatteryScanner.onInitialReadCandidateCompleted = { [weak self] id, succeeded in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let verifiedAt = self.nearbyPersistedSelections.first(where: { $0.id == id })?.batteryLastUpdated
                self.nearbyBLEInitialReadSuppressedUntil[id] = BluetoothLEInitialReadPolicy.attemptSuppressionExpiry(
                    attemptedAt: Date(),
                    succeeded: succeeded,
                    verifiedAt: verifiedAt
                )
                if !succeeded { self.nearbyBLEReadFailures.insert(id) }
                self.updateNearbyBatteryScanner()
            }
        }
        nearbyBatteryScanner.onReadFailures = { [weak self] failures in
            guard let self else { return }
            let revisionsAtCallback = self.nearbyBLEReadRevisions
            Task { @MainActor [weak self] in
                guard let self, generation == self.nearbyScannerGeneration else { return }
                let current = self.currentNearbyBLEReadPermit.union(self.currentNearbyBLEInitialReadPermit)
                self.nearbyBLEReadFailures.formUnion(failures.filter {
                    current.contains($0) && self.nearbyBLEReadRevisions[$0, default: 0] == revisionsAtCallback[$0, default: 0]
                })
            }
        }
        nearbyBatteryScanner.onIsScanningChanged = { [weak self] scanning in
            Task { @MainActor [weak self] in
                guard let self, generation == self.nearbyScannerGeneration else { return }
                self.isDiscoveringNearbyBLEDevices = scanning
            }
        }
        nearbyBatteryScanner.start()
        isDiscoveringNearbyBLEDevices = nearbyBatteryScanner.isScanning
        if !nearbyBatteryScanner.isRunning {
            nearbyBatteryScanner.onDevicesChanged = nil
            nearbyBatteryScanner.onCandidatesChanged = nil
            nearbyBatteryScanner.onInitialReadCandidateCompleted = nil
            nearbyBatteryScanner.onReadFailures = nil
            nearbyBatteryScanner.onIsScanningChanged = nil
            nearbyScannerCallbackIsInstalled = false
        }
    }

    private func stopNearbyBatteryScanner(clearResults: Bool) {
        nearbyScannerGeneration &+= 1
        nearbyBatteryCacheGeneration &+= 1
        nearbyBatteryCacheExpirationTask?.cancel()
        nearbyBatteryCacheExpirationTask = nil
        if let nearbyBatteryScanner {
            nearbyBatteryScanner.setAllowedReadDeviceIDs([])
            nearbyBatteryScanner.onDevicesChanged = nil
            nearbyBatteryScanner.onCandidatesChanged = nil
            nearbyBatteryScanner.onInitialReadCandidateCompleted = nil
            nearbyBatteryScanner.onReadFailures = nil
            nearbyBatteryScanner.onIsScanningChanged = nil
            if nearbyBatteryScanner.isRunning || nearbyScannerCallbackIsInstalled {
                nearbyBatteryScanner.stop()
            }
        }
        for id in nearbyBLEReadPermit.union(nearbyBLEInitialReadPermit) {
            nearbyBLEReadRevisions[id, default: 0] &+= 1
        }
        nearbyBLEReadPermit = []
        nearbyBLEInitialReadPermit = []
        nearbyScannerCallbackIsInstalled = false
        isDiscoveringNearbyBLEDevices = false
        if clearResults {
            nearbyBatteryDevices = []
            nearbyBLEReadFailures = []
            nearbyBLECandidates = []
        } else {
            scheduleNearbyBatteryCacheExpiration()
        }
    }

    private func receiveNearbyBatteryDevices(
        _ devices: [NearbyBluetoothBatteryDevice],
        permittedIDs: Set<UUID>,
        revisions: [UUID: UInt64],
        generation: UInt64
    ) {
        guard generation == nearbyScannerGeneration,
              isNearbyBLEScannerDemanded else { return }
        let currentPermit = currentNearbyBLEReadPermit.union(currentNearbyBLEInitialReadPermit)
        let accepted = devices.filter { device in
            (0...100).contains(device.batteryLevel) &&
            permittedIDs.contains(device.id)
                && currentPermit.contains(device.id)
                && nearbyBLEReadRevisions[device.id, default: 0] == revisions[device.id, default: 0]
        }
        let now = Date()
        var devicesByID: [UUID: NearbyBluetoothBatteryDevice] = [:]
        for device in nearbyBatteryDevices + accepted where
            !nearbyBLEHiddenIDs.contains(device.id)
                && now.timeIntervalSince(device.lastUpdated) <= nearbyBatteryCacheLifetime {
            devicesByID[device.id] = device
        }
        nearbyBatteryDevices = devicesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        nearbyBLEReadFailures.subtract(accepted.map(\.id))
        scheduleNearbyBatteryCacheExpiration()
    }

    private func pruneNearbyBatteryCache(at date: Date) {
        let freshDevices = nearbyBatteryDevices.filter {
            date.timeIntervalSince($0.lastUpdated) <= nearbyBatteryCacheLifetime
        }
        guard freshDevices != nearbyBatteryDevices else { return }
        nearbyBatteryDevices = freshDevices
        scheduleNearbyBatteryCacheExpiration()
    }

    private func scheduleNearbyBatteryCacheExpiration() {
        nearbyBatteryCacheExpirationTask?.cancel()
        nearbyBatteryCacheExpirationTask = nil
        guard let oldestUpdate = nearbyBatteryDevices.map(\.lastUpdated).min() else { return }
        nearbyBatteryCacheGeneration &+= 1
        let generation = nearbyBatteryCacheGeneration
        let expiry = oldestUpdate.addingTimeInterval(nearbyBatteryCacheLifetime)
        let delay = max(0, expiry.timeIntervalSinceNow)
        let sleepDuration = Duration.milliseconds(Int64((delay * 1_000).rounded(.up)))
        nearbyBatteryCacheExpirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: sleepDuration)
            } catch {
                return
            }
            guard let self, self.nearbyBatteryCacheGeneration == generation else { return }
            self.pruneNearbyBatteryCache(at: Date())
            self.scheduleNearbyBatteryCacheExpiration()
        }
    }

    private func scheduleNearbyRowExpiry() {
        nearbyRowExpiryTask?.cancel()
        nearbyRowExpiryTask = nil
        nearbyRowExpiryGeneration &+= 1
        let generation = nearbyRowExpiryGeneration
        let now = Date()
        guard nearbyBLEEnabled,
              let expiry = NearbyBLEDeviceCatalog.nextVerifiedRowExpiration(
                selections: nearbyPersistedSelections,
                now: now
              ) else { return }
        let delay = expiry.timeIntervalSince(now)
        nearbyRowExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(Int64((delay * 1_000).rounded(.up)))) }
            catch { return }
            guard let self, self.nearbyRowExpiryGeneration == generation else { return }
            self.objectWillChange.send()
            self.updateNearbyBatteryScanner()
            self.scheduleNearbyRowExpiry()
        }
    }

    private func refreshAfterSystemEvent() {
        guard isActive else { return }
        stateMonitor.start()
    }

    private func schedulePeriodicRefresh() {
        guard isActive, hasVisibleSurface, availability == .available else { return }
        startConnectionEvents()
        updateAccessoryBatteryEvents()
        guard periodicRefreshTask == nil else { return }
        let interval = safetyNetInterval
        let sleep = safetyNetSleep
        periodicRefreshGeneration &+= 1
        let generation = periodicRefreshGeneration
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer {
                // Only the task that is still current may clear the reference.
                // A stop can cancel this task and start a replacement in the
                // same main-actor turn, before this `defer` runs; clearing
                // unconditionally would leave the replacement untracked and
                // uncancellable.
                if let self, self.periodicRefreshGeneration == generation {
                    self.periodicRefreshTask = nil
                }
            }
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive, self.hasVisibleSurface, self.availability == .available else {
                    return
                }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        // Invalidate the running task before cancelling it, so its `defer` can
        // tell that it has been superseded.
        periodicRefreshGeneration &+= 1
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        stopConnectionEvents()
        stopAccessoryBatteryEvents()
    }

    /// Connection notifications only matter while a Bluetooth surface is on
    /// screen: nothing else displays device state, and the registration is a
    /// system resource the app should not hold for its whole lifetime.
    private func startConnectionEvents() {
        guard !isMonitoringConnectionEventNotifications, let connectionEvents else { return }
        // The handler arrives on IOBluetooth's own thread, so it hops to the
        // main actor before touching controller state.
        isMonitoringConnectionEventNotifications = connectionEvents.start { [weak self] in
            Task { @MainActor in self?.receiveConnectionEvent() }
        }
    }

    private func stopConnectionEvents() {
        _ = connectionEventGate.advance()
        isConnectionEventReadScheduled = false
        // Unconditional: a refused registration (`start` returned `false`) can
        // still have stored the handler, so the monitor is told to stop either
        // way and the teardown path has one shape. `stop()` is lock-guarded and
        // idempotent.
        isMonitoringConnectionEventNotifications = false
        connectionEvents?.stop()
    }

    /// Accessory battery notifications only matter while a surface is showing
    /// levels: nothing else displays them, and the registration is a system
    /// resource the app should not hold for its lifetime. So the registration
    /// follows the battery claim and the visible surface together, where the
    /// connect registration follows the surface alone.
    private func updateAccessoryBatteryEvents() {
        guard isActive, batteryLevelsEnabled, hasVisibleSurface, availability == .available else {
            stopAccessoryBatteryEvents()
            return
        }
        startAccessoryBatteryEvents()
    }

    private func startAccessoryBatteryEvents() {
        guard !isMonitoringAccessoryBatteryNotifications, let accessoryBatteryEvents else { return }
        // The handler arrives on the monitor's own queue, so it hops to the main
        // actor before touching controller state.
        isMonitoringAccessoryBatteryNotifications = accessoryBatteryEvents.start { [weak self] in
            Task { @MainActor in self?.receiveAccessoryBatteryEvent() }
        }
    }

    private func stopAccessoryBatteryEvents() {
        _ = accessoryBatteryEventGate.advance()
        isAccessoryBatteryEventReadScheduled = false
        // Unconditional, for the same reason the connect registration is: a
        // refused registration can still have stored the handler, so the monitor
        // is told to stop either way and teardown has one shape.
        isMonitoringAccessoryBatteryNotifications = false
        accessoryBatteryEvents?.stop()
    }

    /// One read per burst of accessory notifications. An accessory discharging
    /// posts these fairly often, so the burst is held for the longer interval and
    /// the read that follows re-fetches the report: the notification says the
    /// system's reading changed, which is exactly what a cached report cannot
    /// show.
    private func receiveAccessoryBatteryEvent() {
        guard isActive, isMonitoringAccessoryBatteryNotifications else { return }
        guard !isAccessoryBatteryEventReadScheduled else { return }
        isAccessoryBatteryEventReadScheduled = true
        let request = accessoryBatteryEventGate.advance()
        let interval = accessoryBatteryEventDebounceInterval
        let sleep = accessoryBatteryEventDebounceSleep
        Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                guard let self, self.accessoryBatteryEventGate.accepts(request) else { return }
                self.isAccessoryBatteryEventReadScheduled = false
                return
            }
            guard let self, self.accessoryBatteryEventGate.accepts(request) else { return }
            self.isAccessoryBatteryEventReadScheduled = false
            guard self.isActive else { return }
            self.refresh()
        }
    }

    // MARK: - Device actions

    /// Asks for a confirmation before disconnecting a device. Only a connected
    /// input device needs one; anything else is ignored, so a stale view cannot
    /// put a question on screen that the policy would not ask.
    func requestDisconnectConfirmation(for device: BluetoothDevice) {
        guard BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        pendingDisconnectConfirmation = BluetoothBatteryReader.normalizedAddress(device.id)
    }

    /// Drops an unanswered confirmation. The row's cancel action calls this, and
    /// so does the panel closing.
    func cancelDisconnectConfirmation() {
        pendingDisconnectConfirmation = nil
    }

    /// Asks the system to toggle a device. The row's state changes when the
    /// report does, never because this call returned: the request only starts a
    /// wait that ends in the report changing or in a visible failure.
    func performDeviceAction(for device: BluetoothDevice) {
        guard isActive, availability == .available else { return }
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        switch deviceActionStates[address] {
        case .none, .failed:
            // Free, or a retry of a failure that is still on screen. The
            // superseded failure's clear no longer has anything to clear, so it
            // goes with the state it was armed for.
            failureClearTasks[address]?.cancel()
            failureClearTasks[address] = nil
        case .connecting, .disconnecting:
            // One action per device at a time.
            return
        }

        // Answering the question is what the tap does, so it is no longer pending.
        pendingDisconnectConfirmation = nil
        let action = BluetoothDeviceActionPolicy.action(for: device)
        deviceActionTokenCounter &+= 1
        let token = deviceActionTokenCounter
        deviceActionTokens[address] = token
        deviceActionStates[address] = action.inFlightState
        armActionTimeout(for: action, address: address, token: token)
        actionPerformer.setConnected(action == .connect, forAddress: address) { [weak self] accepted in
            guard !accepted else { return }
            Task { @MainActor [weak self] in
                // The token alone is not enough: the report can settle the
                // action — a sleeping device reconnecting on its own — before
                // this answer arrives, and the answer would then still match
                // the token it was issued for. Requiring the action to still be
                // in flight is what keeps a settled row from being failed by
                // its own late refusal, exactly as the timeout already does.
                guard let self,
                      self.deviceActionTokens[address] == token,
                      self.deviceActionStates[address] == action.inFlightState else { return }
                self.failDeviceAction(action, address: address)
            }
        }
    }

    /// Clears the actions whose target state the report now shows. This is the
    /// only way an action succeeds.
    private func reconcileDeviceActions() {
        guard !deviceActionStates.isEmpty else { return }
        for device in devices {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard let state = deviceActionStates[address] else { continue }
            let reachedTarget = switch state {
            case .connecting: device.isConnected
            case .disconnecting: !device.isConnected
            case .failed: false
            }
            if reachedTarget {
                finishDeviceAction(address: address)
            }
        }
    }

    private func armActionTimeout(for action: BluetoothDeviceAction, address: String, token: UInt64) {
        actionTimeouts[address]?.cancel()
        let timeout = actionTimeout
        let sleep = actionTimeoutSleep
        actionTimeouts[address] = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard let self,
                  self.deviceActionTokens[address] == token,
                  self.deviceActionStates[address] == action.inFlightState else { return }
            self.failDeviceAction(action, address: address)
        }
    }

    private func failDeviceAction(_ action: BluetoothDeviceAction, address: String) {
        actionTimeouts[address]?.cancel()
        actionTimeouts[address] = nil
        deviceActionStates[address] = .failed(action)

        failureClearTasks[address]?.cancel()
        let visible = failureVisibleDuration
        let sleep = failureVisibleSleep
        failureClearTasks[address] = Task { @MainActor [weak self] in
            do {
                try await sleep(visible)
            } catch {
                return
            }
            guard let self, case .failed = self.deviceActionStates[address] else { return }
            self.deviceActionStates[address] = nil
            self.failureClearTasks[address] = nil
        }
    }

    private func finishDeviceAction(address: String) {
        actionTimeouts[address]?.cancel()
        actionTimeouts[address] = nil
        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = nil
        // Dropped with the state: a settled action has no request left to
        // answer, so its token must not survive to admit a late completion.
        deviceActionTokens[address] = nil
        deviceActionStates[address] = nil
    }

    private func clearDeviceActions() {
        for task in actionTimeouts.values { task.cancel() }
        for task in failureClearTasks.values { task.cancel() }
        actionTimeouts.removeAll()
        failureClearTasks.removeAll()
        deviceActionTokens.removeAll()
        deviceActionStates.removeAll()
        pendingDisconnectConfirmation = nil
    }

    /// One read per burst of connect/disconnect notifications. macOS connects
    /// several devices at once (AirPods plus a Watch, say), and each
    /// notification would otherwise start its own profiler run.
    private func receiveConnectionEvent() {
        guard isActive, isMonitoringConnectionEventNotifications else { return }
        guard !isConnectionEventReadScheduled else { return }
        isConnectionEventReadScheduled = true
        let request = connectionEventGate.advance()
        let interval = connectionEventDebounceInterval
        let sleep = connectionEventDebounceSleep
        Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                guard let self, self.connectionEventGate.accepts(request) else { return }
                self.isConnectionEventReadScheduled = false
                return
            }
            guard let self, self.connectionEventGate.accepts(request) else { return }
            self.isConnectionEventReadScheduled = false
            guard self.isActive else { return }
            self.refresh()
        }
    }
}
