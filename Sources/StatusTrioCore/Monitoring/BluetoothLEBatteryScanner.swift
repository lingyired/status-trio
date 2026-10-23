@preconcurrency import CoreBluetooth
import Foundation

struct BluetoothLEBatteryScanPolicy {
    static let scanWindow: Duration = .seconds(5)
    static let automaticScanInterval: TimeInterval = 60
    static let successfulConnectionCooldown: TimeInterval = 60
    static let failedConnectionCooldown: TimeInterval = 60
    /// A verified row disappears after this long without a successful read.
    static let resultLifetime: TimeInterval = 1200
    static let maxQueuedCandidates = 8
    static let maxConcurrentConnections = 2
    static let connectionTimeout: Duration = .seconds(8)

    private(set) var generation: UInt64 = 0
    private(set) var queuedCandidateCount = 0
    private(set) var inFlightConnectionCount = 0

    private var lastScanStartedAt: Date?
    private var discoveredCandidates: Set<UUID> = []
    private var queuedCandidates: [UUID] = []
    private var inFlightConnections: Set<UUID> = []
    private var retryAfter: [UUID: Date] = [:]

    mutating func beginScan(at date: Date, manual: Bool) -> Bool {
        if !manual,
           let lastScanStartedAt,
           date.timeIntervalSince(lastScanStartedAt) < Self.automaticScanInterval {
            return false
        }

        lastScanStartedAt = date
        retryAfter = retryAfter.filter { $0.value > date }
        discoveredCandidates.removeAll(keepingCapacity: true)
        queuedCandidates.removeAll(keepingCapacity: true)
        queuedCandidateCount = 0
        return true
    }

    mutating func beginAutomaticScan(at date: Date, isRunning: Bool) -> Bool {
        guard isRunning else { return false }
        return beginScan(at: date, manual: false)
    }

    mutating func enqueueCandidate(_ id: UUID, at date: Date) -> Bool {
        guard !discoveredCandidates.contains(id),
              !inFlightConnections.contains(id),
              discoveredCandidates.count < Self.maxQueuedCandidates else {
            return false
        }
        discoveredCandidates.insert(id)

        if let retryDate = retryAfter[id], date < retryDate {
            return false
        }

        queuedCandidates.append(id)
        queuedCandidateCount = queuedCandidates.count
        return true
    }

    mutating func startQueuedConnections() -> [UUID] {
        let availableSlots = max(0, Self.maxConcurrentConnections - inFlightConnections.count)
        guard availableSlots > 0 else { return [] }

        let count = min(availableSlots, queuedCandidates.count)
        let candidates = Array(queuedCandidates.prefix(count))
        queuedCandidates.removeFirst(count)
        inFlightConnections.formUnion(candidates)
        queuedCandidateCount = queuedCandidates.count
        inFlightConnectionCount = inFlightConnections.count
        return candidates
    }

    mutating func discardQueuedCandidates() {
        queuedCandidates.removeAll(keepingCapacity: false)
        queuedCandidateCount = 0
    }

    mutating func removeCandidates(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let now = Date()
        for id in inFlightConnections.intersection(ids) {
            retryAfter[id] = now.addingTimeInterval(Self.failedConnectionCooldown)
        }
        discoveredCandidates.subtract(ids)
        queuedCandidates.removeAll { ids.contains($0) }
        inFlightConnections.subtract(ids)
        queuedCandidateCount = queuedCandidates.count
        inFlightConnectionCount = inFlightConnections.count
    }

    mutating func completeConnection(_ id: UUID, succeeded: Bool, at date: Date) {
        guard inFlightConnections.remove(id) != nil else { return }
        let cooldown = succeeded ? Self.successfulConnectionCooldown : Self.failedConnectionCooldown
        retryAfter[id] = date.addingTimeInterval(cooldown)
        inFlightConnectionCount = inFlightConnections.count
    }

    func acceptsCallback(from generation: UInt64) -> Bool {
        self.generation == generation
    }

    mutating func stop() {
        generation &+= 1
        let now = Date()
        for id in inFlightConnections {
            retryAfter[id] = now.addingTimeInterval(Self.failedConnectionCooldown)
        }
        discoveredCandidates.removeAll(keepingCapacity: false)
        queuedCandidates.removeAll(keepingCapacity: false)
        inFlightConnections.removeAll(keepingCapacity: false)
        // Keep per-device cooldowns across viewport/demand stops.
        queuedCandidateCount = 0
        inFlightConnectionCount = 0
    }
}

enum BluetoothLEBatteryNamePolicy {
    static func resolvedName(formalName: String?, advertisedName _: String?) -> String {
        let formal = formalName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return formal
    }
}

/// When a session's reading is settled enough to publish.
///
/// A battery byte on its own is the whole answer for a device that advertises
/// `180F` and nothing else, so it goes out as soon as it arrives. It is not the
/// whole answer for a device that also answers with a model string: that string
/// is what decides which list the row belongs in — a model the app draws is
/// folded onto the row the device already has in the paired list, and a model it
/// does not draw leaves the device in the nearby list. Publishing the level
/// first showed the phone in the nearby list for the tenth of a second the model
/// read needs and then moved it into the paired list, which put the panel's
/// "paired devices" header on screen and took it off again in the same moment.
///
/// The wait is bounded by the session, not by the read: a device that stops
/// answering the model characteristic still publishes what it did answer when
/// the session ends.
enum BluetoothLEBatteryPublishGate {
    static func shouldPublish(
        batteryLevel: Int?,
        modelReadPending: Bool,
        sessionIsEnding: Bool
    ) -> Bool {
        guard batteryLevel != nil else { return false }
        return sessionIsEnding || !modelReadPending
    }
}

@MainActor
protocol BluetoothLEBatteryScanning: AnyObject {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)? { get set }
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)? { get set }
    var onReadFailures: ((Set<UUID>) -> Void)? { get set }
    var onIsScanningChanged: ((Bool) -> Void)? { get set }
    var onInitialReadCandidateCompleted: ((UUID, Bool, DeviceOperationToken?) -> Void)? { get set }
    var isRunning: Bool { get }
    var isScanning: Bool { get }
    var discoveredCandidates: [NearbyBLEDeviceCandidate] { get }

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) -> [UUID: DeviceOperationToken]
    func revokeReadDeviceIDs(_ ids: Set<UUID>)
    func setInitialReadCandidateIDs(
        _ ids: Set<UUID>
    ) -> [UUID: DeviceOperationToken]
    func setBackgroundRefreshInterval(_ interval: Duration?)
    func start()
    func refresh()
    func stop()
}

extension BluetoothLEBatteryScanning {
    var discoveredCandidates: [NearbyBLEDeviceCandidate] { [] }
    var onInitialReadCandidateCompleted: ((UUID, Bool, DeviceOperationToken?) -> Void)? {
        get { nil }
        set { }
    }
    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) -> [UUID: DeviceOperationToken] {
        _ = ids
        return [:]
    }
    func setInitialReadCandidateIDs(
        _ ids: Set<UUID>
    ) -> [UUID: DeviceOperationToken] {
        _ = ids
        return [:]
    }
    func revokeReadDeviceIDs(_ ids: Set<UUID>) { _ = ids }
    func setBackgroundRefreshInterval(_ interval: Duration?) { _ = interval }
}

@MainActor
private final class NearbyBLEPeripheralSessionDelegate: NSObject, @preconcurrency CBPeripheralDelegate {
    weak var scanner: CoreBluetoothLEBatteryScanner?
    let sessionID: UUID

    init(scanner: CoreBluetoothLEBatteryScanner, sessionID: UUID) {
        self.scanner = scanner
        self.sessionID = sessionID
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        scanner?.peripheral(peripheral, didDiscoverServices: error, sessionID: sessionID)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        scanner?.peripheral(
            peripheral,
            didDiscoverCharacteristicsFor: service,
            error: error,
            sessionID: sessionID
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        scanner?.peripheral(
            peripheral,
            didUpdateValueFor: characteristic,
            error: error,
            sessionID: sessionID
        )
    }
}

/// Discovers nearby candidates and opens GATT only for UUIDs currently visible
/// in the status panel. CoreBluetooth is created on first active demand.
@MainActor
final class CoreBluetoothLEBatteryScanner: NSObject,
    BluetoothLEBatteryScanning,
    @preconcurrency CBCentralManagerDelegate {

    private struct PeripheralSession {
        let sessionID: UUID
        let peripheral: CBPeripheral
        let delegate: NearbyBLEPeripheralSessionDelegate
        let generation: UInt64
        let authorizationToken: DeviceOperationToken?
        let initialReadToken: DeviceOperationToken?
        let advertisedName: String?
        var timeoutTask: Task<Void, Never>?
        var pendingCharacteristicDiscoveries = 0
        var pendingReads: Set<CBUUID> = []
        var batteryLevel: Int?
        var model: String?
        var manufacturer: String?
    }

    private struct CancellingPeripheral {
        let sessionID: UUID
        let peripheral: CBPeripheral
        let delegate: NearbyBLEPeripheralSessionDelegate
        let central: CBCentralManager?
    }

    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")
    private static let deviceInformationServiceUUID = CBUUID(string: "180A")
    private static let modelNumberUUID = CBUUID(string: "2A24")
    private static let manufacturerNameUUID = CBUUID(string: "2A29")

    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var isScanning = false
    var discoveredCandidates: [NearbyBLEDeviceCandidate] { candidateCache.candidates }
    var onInitialReadCandidateCompleted: ((UUID, Bool, DeviceOperationToken?) -> Void)?

    /// These references are mutated only on the main actor. `deinit` is
    /// nonisolated, so it reads them only to cancel tasks and hand CoreBluetooth
    /// cleanup back to the main actor, following the controller's teardown rule.
    nonisolated(unsafe) private var centralManager: CBCentralManager?
    nonisolated(unsafe) private var sessions: [UUID: PeripheralSession] = [:]
    nonisolated(unsafe) private var scanWindowTask: Task<Void, Never>?
    nonisolated(unsafe) private var automaticRefreshTask: Task<Void, Never>?
    private var candidateExpiryTask: Task<Void, Never>?

    private var policy = BluetoothLEBatteryScanPolicy()
    private var readAuthorization = NearbyBLEReadAuthorization()
    private var initialReadAuthorization = NearbyBLEReadAuthorization()
    private var initialReadCandidateIDs: Set<UUID> = []
    private var sessionCancellationGate = NearbyBLESessionCancellationGate()
    private var candidatePeripherals: [UUID: CBPeripheral] = [:]
    private var candidateNames: [UUID: String] = [:]
    private var candidateCache = NearbyBLECandidateCache()
    private var cancellingPeripherals: [UUID: CancellingPeripheral] = [:]
    private var readFailures: Set<UUID> = []
    private var nearbyDevices: [UUID: NearbyBluetoothBatteryDevice] = [:]
    private var currentScanGeneration: UInt64 = 0
    private var backgroundRefreshInterval: Duration?

    deinit {
        scanWindowTask?.cancel()
        automaticRefreshTask?.cancel()
        candidateExpiryTask?.cancel()
        let manager = centralManager
        let peripherals = Array(Set(sessions.values.map(\.peripheral) + cancellingPeripherals.values.map(\.peripheral)))
        sessions.values.forEach { $0.timeoutTask?.cancel() }
        guard manager != nil || !peripherals.isEmpty else { return }

        // CoreBluetooth delegates and peripheral teardown run on the manager's
        // main queue. The captured references outlive this scanner only until
        // the teardown block has stopped scans and cancelled its GATT sessions.
        Task { @MainActor in
            manager?.stopScan()
            for peripheral in peripherals {
                peripheral.delegate = nil
                manager?.cancelPeripheralConnection(peripheral)
            }
            manager?.delegate = nil
        }
    }

    func start() {
        guard !isRunning,
              CBManager.authorization == .allowedAlways else {
            return
        }

        isRunning = true
        ensureCentralManager()
        if centralManager?.state == .poweredOn {
            startScanWindow(manual: true)
        }
    }

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) -> [UUID: DeviceOperationToken] {
        let previousIDs = readAuthorization.allowedIDs
        let changed = readAuthorization.allowedIDs != ids
        let migratedTokens = initialReadAuthorization.currentTokens.filter {
            ids.contains($0.key) && !previousIDs.contains($0.key)
        }
        let revokedIDs = readAuthorization.migrate(to: ids, preserving: migratedTokens)
        guard changed else { return readAuthorization.currentTokens }

        if isRunning, automaticRefreshTask == nil {
            scheduleAutomaticRefresh()
        }

        policy.removeCandidates(revokedIDs)
        for id in revokedIDs {
            candidatePeripherals.removeValue(forKey: id)
            candidateNames.removeValue(forKey: id)
            if let session = sessions.removeValue(forKey: id),
               sessionCancellationGate.retire(id, session: session.sessionID) {
                session.timeoutTask?.cancel()
                cancellingPeripherals[id] = CancellingPeripheral(
                    sessionID: session.sessionID,
                    peripheral: session.peripheral,
                    delegate: session.delegate,
                    central: centralManager
                )
                centralManager?.cancelPeripheralConnection(session.peripheral)
            }
        }
        let oldFailures = readFailures
        readFailures.subtract(revokedIDs)
        if oldFailures != readFailures { onReadFailures?(readFailures) }
        for id in ids.subtracting(previousIDs) where isScanning {
            guard !cancellingPeripherals.keys.contains(id),
                  let peripheral = candidatePeripherals[id],
                  policy.enqueueCandidate(id, at: Date()) else { continue }
            candidateNames[id] = candidateCache.candidates.first(where: { $0.id == id })?.name ?? peripheral.name ?? ""
        }
        if !ids.subtracting(previousIDs).isEmpty, isRunning, !isScanning {
            startScanWindow(manual: true)
        }
        startQueuedConnections()
        return readAuthorization.currentTokens
    }

    func revokeReadDeviceIDs(_ ids: Set<UUID>) {
        _ = readAuthorization.update(readAuthorization.allowedIDs.subtracting(ids))
        initialReadCandidateIDs.subtract(ids)
        _ = initialReadAuthorization.update(initialReadAuthorization.allowedIDs.subtracting(ids))
        nearbyDevices = nearbyDevices.filter { !ids.contains($0.key) }
        readFailures.subtract(ids)
        policy.removeCandidates(ids)
        for id in ids {
            candidatePeripherals.removeValue(forKey: id)
            candidateNames.removeValue(forKey: id)
            if let session = sessions.removeValue(forKey: id),
               sessionCancellationGate.retire(id, session: session.sessionID) {
                session.timeoutTask?.cancel()
                cancellingPeripherals[id] = CancellingPeripheral(
                    sessionID: session.sessionID,
                    peripheral: session.peripheral,
                    delegate: session.delegate,
                    central: centralManager
                )
                centralManager?.cancelPeripheralConnection(session.peripheral)
            }
        }
        onDevicesChanged?(nearbyDevices.values.sorted { $0.id.uuidString < $1.id.uuidString })
        onReadFailures?(readFailures)
    }

    func setInitialReadCandidateIDs(
        _ ids: Set<UUID>
    ) -> [UUID: DeviceOperationToken] {
        let old = initialReadCandidateIDs
        let permitted = ids.subtracting(readAuthorization.allowedIDs)
        let migratedTokens = initialReadAuthorization.currentTokens.filter {
            old.subtracting(permitted).contains($0.key)
                && readAuthorization.accepts($0.key, token: $0.value)
        }
        let removed = initialReadAuthorization.update(permitted)
        initialReadCandidateIDs = permitted
        let cancelled = removed.subtracting(migratedTokens.keys)
        policy.removeCandidates(cancelled)
        for id in cancelled {
            candidatePeripherals.removeValue(forKey: id)
            candidateNames.removeValue(forKey: id)
            if let session = sessions.removeValue(forKey: id),
               sessionCancellationGate.retire(id, session: session.sessionID) {
                session.timeoutTask?.cancel()
                cancellingPeripherals[id] = CancellingPeripheral(
                    sessionID: session.sessionID, peripheral: session.peripheral,
                    delegate: session.delegate, central: centralManager
                )
                centralManager?.cancelPeripheralConnection(session.peripheral)
            }
        }
        for id in initialReadCandidateIDs.subtracting(old) where isScanning {
            guard !cancellingPeripherals.keys.contains(id),
                  let peripheral = candidatePeripherals[id],
                  policy.enqueueCandidate(id, at: Date()) else { continue }
            candidateNames[id] = candidateCache.candidates.first(where: { $0.id == id })?.name ?? peripheral.name ?? ""
        }
        if !initialReadCandidateIDs.subtracting(old).isEmpty, isRunning, !isScanning {
            startScanWindow(manual: true)
        }
        startQueuedConnections()
        return initialReadAuthorization.currentTokens
    }

    func setBackgroundRefreshInterval(_ interval: Duration?) {
        backgroundRefreshInterval = interval
        if isRunning { scheduleAutomaticRefresh() }
    }

    func refresh() {
        guard isRunning else {
            start()
            return
        }
        guard !isScanning else { return }
        startScanWindow(manual: true)
    }

    func stop() {
        isRunning = false
        stopActiveWork(clearResults: true)
        _ = readAuthorization.update([])
        initialReadCandidateIDs = []
        _ = initialReadAuthorization.update([])
        releaseCentralIfIdle()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager, isRunning else { return }
        switch central.state {
        case .poweredOn:
            startScanWindow(manual: true)
        case .unauthorized, .unsupported:
            stop()
        case .unknown, .resetting, .poweredOff:
            stopActiveWork()
        @unknown default:
            stopActiveWork()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard isRunning,
              isScanning,
              BluetoothLEBatteryAdvertisement.isCandidate(
                  serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                  manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                  name: advertisedName ?? peripheral.name,
                  batteryService: Self.batteryServiceUUID
              ),
              policy.acceptsCallback(from: currentScanGeneration) else {
            return
        }

        let identifier = peripheral.identifier
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let resolvedName = advertisedName ?? peripheral.name ?? ""
        let vendor = NearbyBLEVendor.fromManufacturerData(manufacturerData)
        candidatePeripherals[identifier] = peripheral
        candidateNames[identifier] = resolvedName
        if vendor == .apple, !resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publishCandidate(id: identifier, name: resolvedName, vendor: vendor)
        }
        guard isReadPermitted(identifier),
              cancellingPeripherals[identifier] == nil else { return }
        guard policy.enqueueCandidate(identifier, at: Date()) else { return }
        // The advertisement name is transient, kept only in this in-memory
        // session and never logged or persisted.
        startQueuedConnections()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier
        if let cancelling = cancellingPeripherals[identifier],
           cancelling.peripheral === peripheral,
           cancelling.central === central {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard central === centralManager,
              let current = currentSession(for: identifier), current.peripheral === peripheral, isAuthorized(current) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        var session = current

        peripheral.delegate = current.delegate
        session.pendingCharacteristicDiscoveries = 1
        sessions[identifier] = session
        guard isAuthorized(session) else {
            completeSession(for: identifier, succeeded: false)
            return
        }
        peripheral.discoverServices([
            Self.batteryServiceUUID,
            Self.deviceInformationServiceUUID
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        if finishCancellation(for: peripheral, central: central) { return }
        guard central === centralManager,
              let session = currentSession(for: peripheral.identifier), session.peripheral === peripheral else { return }
        completeSession(for: peripheral.identifier, succeeded: false, session: session, connectionAlreadyEnded: true)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        if finishCancellation(for: peripheral, central: central) { return }
        guard central === centralManager,
              let session = currentSession(for: peripheral.identifier), session.peripheral === peripheral else { return }
        completeSession(
            for: peripheral.identifier,
            succeeded: session.batteryLevel != nil,
            session: session,
            connectionAlreadyEnded: true
        )
    }

    fileprivate func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?, sessionID: UUID) {
        let identifier = peripheral.identifier
        guard let current = currentSession(for: peripheral, sessionID: sessionID), isAuthorized(current) else { return }
        var session = current
        guard error == nil else {
            completeSession(for: identifier, succeeded: false)
            return
        }

        let services = (peripheral.services ?? []).filter { service in
            isUUID(service.uuid, Self.batteryServiceUUID)
                || isUUID(service.uuid, Self.deviceInformationServiceUUID)
        }
        guard services.contains(where: { isUUID($0.uuid, Self.batteryServiceUUID) }) else {
            completeSession(for: identifier, succeeded: false)
            return
        }

        session.pendingCharacteristicDiscoveries = services.count
        sessions[identifier] = session
        for service in services {
            guard isAuthorized(session) else { return }
            let characteristics: [CBUUID]
            if isUUID(service.uuid, Self.batteryServiceUUID) {
                characteristics = [Self.batteryLevelUUID]
            } else {
                characteristics = [Self.modelNumberUUID, Self.manufacturerNameUUID]
            }
            peripheral.discoverCharacteristics(characteristics, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?,
        sessionID: UUID
    ) {
        let identifier = peripheral.identifier
        guard let current = currentSession(for: peripheral, sessionID: sessionID), isAuthorized(current) else { return }
        var session = current
        guard error == nil else {
            if isUUID(service.uuid, Self.batteryServiceUUID) {
                completeSession(for: identifier, succeeded: false)
                return
            }
            session.pendingCharacteristicDiscoveries = max(0, session.pendingCharacteristicDiscoveries - 1)
            sessions[identifier] = session
            finishSessionIfReady(identifier)
            return
        }

        let characteristics = service.characteristics ?? []
        var valuesToRead: [CBCharacteristic] = []
        if isUUID(service.uuid, Self.batteryServiceUUID) {
            guard let batteryCharacteristic = characteristics.first(where: {
                isUUID($0.uuid, Self.batteryLevelUUID)
            }) else {
                completeSession(for: identifier, succeeded: false)
                return
            }
            session.pendingReads.insert(Self.batteryLevelUUID)
            valuesToRead.append(batteryCharacteristic)
        } else if isUUID(service.uuid, Self.deviceInformationServiceUUID) {
            for characteristic in characteristics where
                isUUID(characteristic.uuid, Self.modelNumberUUID)
                    || isUUID(characteristic.uuid, Self.manufacturerNameUUID) {
                session.pendingReads.insert(characteristic.uuid)
                valuesToRead.append(characteristic)
            }
        }

        session.pendingCharacteristicDiscoveries = max(0, session.pendingCharacteristicDiscoveries - 1)
        sessions[identifier] = session
        for characteristic in valuesToRead {
            guard isAuthorized(session) else { return }
            peripheral.readValue(for: characteristic)
        }
        finishSessionIfReady(identifier)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?,
        sessionID: UUID
    ) {
        let identifier = peripheral.identifier
        guard let current = currentSession(for: peripheral, sessionID: sessionID),
              isAuthorized(current) else { return }
        var session = current
        guard
              session.pendingReads.remove(characteristic.uuid) != nil else {
            return
        }

        if error == nil, let value = characteristic.value {
            if isUUID(characteristic.uuid, Self.batteryLevelUUID) {
                guard let batteryLevel = BluetoothLEBatteryParsing.percentage(value) else {
                    completeSession(for: identifier, succeeded: false)
                    return
                }
                session.batteryLevel = batteryLevel
            } else if isUUID(characteristic.uuid, Self.modelNumberUUID) {
                session.model = BluetoothLEBatteryParsing.deviceInfo(value)
            } else if isUUID(characteristic.uuid, Self.manufacturerNameUUID) {
                session.manufacturer = BluetoothLEBatteryParsing.deviceInfo(value)
            }
        }

        sessions[identifier] = session
        if BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: session.batteryLevel,
            modelReadPending: session.pendingReads.contains(Self.modelNumberUUID),
            sessionIsEnding: false
        ) {
            publishDeviceIfAvailable(session)
        }
        finishSessionIfReady(identifier)
    }

    private func ensureCentralManager() {
        guard centralManager == nil,
              CBManager.authorization == .allowedAlways else {
            return
        }

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    private func scheduleAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let interval = self.backgroundRefreshInterval
                    ?? .seconds(Int(BluetoothLEBatteryScanPolicy.automaticScanInterval))
                try await Task.sleep(for: interval)
            } catch {
                return
            }

            guard let self, self.isRunning else { return }
            self.startScanWindow(manual: false)
        }
    }

    private func startScanWindow(manual: Bool) {
        guard isRunning,
              !isScanning,
              let centralManager,
              centralManager.state == .poweredOn else {
            return
        }

        let didBegin = manual
            ? policy.beginScan(at: Date(), manual: true)
            : policy.beginAutomaticScan(at: Date(), isRunning: isRunning)
        guard didBegin else { return }

        candidatePeripherals.removeAll(keepingCapacity: true)
        candidateNames.removeAll(keepingCapacity: true)
        candidateCache.beginScan()
        setScanning(true)
        currentScanGeneration = policy.generation
        for service in [Self.batteryServiceUUID, Self.deviceInformationServiceUUID] {
            for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [service]) {
                let id = peripheral.identifier
                candidatePeripherals[id] = peripheral
                candidateNames[id] = peripheral.name ?? ""
                // A service query supplies a route, never Apple identity or visibility.
                if isReadPermitted(id), cancellingPeripherals[id] == nil,
                   policy.enqueueCandidate(id, at: Date()) {
                    startQueuedConnections()
                }
            }
        }
        // The scan is unfiltered on purpose. `withServices` is applied by the
        // stack, not by this delegate: an advertisement that does not name the
        // service is never delivered at all, so a `180F`-filtered scan cannot
        // see a device that reveals its Battery Service only after the
        // connection — which is every iOS device, and every iPhone row the
        // nearby list is meant to show. CoreBluetooth therefore hands over
        // everything and `BluetoothLEBatteryAdvertisement` decides, in
        // `didDiscover`, which of those are worth a connection.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scheduleAutomaticRefresh()

        let generation = policy.generation
        scanWindowTask?.cancel()
        scanWindowTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: BluetoothLEBatteryScanPolicy.scanWindow)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.policy.acceptsCallback(from: generation),
                  self.isRunning,
                  self.isScanning else {
                return
            }
            self.finishScanWindow()
        }
    }

    private func finishScanWindow() {
        scanWindowTask?.cancel()
        scanWindowTask = nil
        centralManager?.stopScan()
        setScanning(false)
        _ = candidateCache.finishScan(at: Date())
        publishCandidates()
        startQueuedConnections()
        // The scan window is the full discovery budget. Only connections
        // started within it may continue afterward; the remaining candidates
        // are dropped instead of being connected serially as slots open.
        policy.discardQueuedCandidates()
        candidatePeripherals.removeAll(keepingCapacity: false)
        candidateNames.removeAll(keepingCapacity: false)
    }

    private func startQueuedConnections() {
        // Discovery and GATT work share the five-second window. A free slot can
        // start another queued candidate as soon as it opens without waiting
        // for the scanner to stop listening.
        guard isRunning, cancellingPeripherals.isEmpty,
              let centralManager, centralManager.state == .poweredOn else { return }
        let candidates = policy.startQueuedConnections()
        for identifier in candidates {
            guard cancellingPeripherals[identifier] == nil,
                  let peripheral = candidatePeripherals.removeValue(forKey: identifier) else {
                policy.completeConnection(identifier, succeeded: false, at: Date())
                continue
            }

            let sessionID = UUID()
            let explicitToken = readAuthorization.token(for: identifier)
            let initialReadToken = explicitToken == nil
                ? initialReadAuthorization.token(for: identifier)
                : nil
            var session = PeripheralSession(
                sessionID: sessionID,
                peripheral: peripheral,
                delegate: NearbyBLEPeripheralSessionDelegate(scanner: self, sessionID: sessionID),
                generation: policy.generation,
                authorizationToken: explicitToken ?? initialReadToken,
                initialReadToken: initialReadToken,
                advertisedName: candidateNames.removeValue(forKey: identifier) ?? peripheral.name,
                timeoutTask: nil
            )
            guard isAuthorized(session) else {
                policy.removeCandidates([identifier])
                continue
            }
            guard sessionCancellationGate.begin(identifier, session: sessionID) else {
                policy.completeConnection(identifier, succeeded: false, at: Date())
                continue
            }
            let generation = session.generation
            session.timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: BluetoothLEBatteryScanPolicy.connectionTimeout)
                } catch {
                    return
                }
                guard let self,
                      let current = self.currentSession(for: identifier, sessionID: sessionID),
                      current.generation == generation else {
                    return
                }
                self.completeSession(for: identifier, succeeded: current.batteryLevel != nil)
            }
            sessions[identifier] = session
            centralManager.connect(peripheral, options: nil)
        }
    }

    private func finishSessionIfReady(_ identifier: UUID) {
        guard let session = sessions[identifier],
              session.pendingCharacteristicDiscoveries == 0,
              session.pendingReads.isEmpty else {
            return
        }
        completeSession(for: identifier, succeeded: session.batteryLevel != nil)
    }

    private func completeSession(
        for identifier: UUID,
        succeeded: Bool,
        session expectedSession: PeripheralSession? = nil,
        connectionAlreadyEnded: Bool = false
    ) {
        guard let session = sessions[identifier],
              expectedSession == nil || expectedSession?.sessionID == session.sessionID else { return }
        sessions.removeValue(forKey: identifier)
        let authorized = isReadPermitted(identifier, session: session)
        // The session ending is the last chance to publish: a read that never
        // answered must not take the level that did with it.
        if authorized && BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: session.batteryLevel,
            modelReadPending: false,
            sessionIsEnding: true
        ) {
            publishDeviceIfAvailable(session)
        }
        if authorized, session.batteryLevel == nil {
            if succeeded {
                readFailures.remove(identifier)
            } else {
                readFailures.insert(identifier)
            }
            onReadFailures?(readFailures)
        }
        session.timeoutTask?.cancel()
        if connectionAlreadyEnded {
            _ = sessionCancellationGate.finishActive(identifier, session: session.sessionID)
            session.peripheral.delegate = nil
        } else if sessionCancellationGate.retire(identifier, session: session.sessionID) {
            cancellingPeripherals[identifier] = CancellingPeripheral(
                sessionID: session.sessionID,
                peripheral: session.peripheral,
                delegate: session.delegate,
                central: centralManager
            )
            centralManager?.cancelPeripheralConnection(session.peripheral)
        }
        candidatePeripherals.removeValue(forKey: identifier)
        candidateNames.removeValue(forKey: identifier)
        policy.completeConnection(identifier, succeeded: succeeded, at: Date())
        let completedInitialRead = session.initialReadToken.map {
            readAuthorization.accepts(identifier, token: $0)
                || initialReadAuthorization.accepts(identifier, token: $0)
        } ?? false
        initialReadCandidateIDs.remove(identifier)
        _ = initialReadAuthorization.update(initialReadCandidateIDs)
        if completedInitialRead {
            onInitialReadCandidateCompleted?(
                identifier,
                succeeded && session.batteryLevel != nil,
                session.initialReadToken
            )
        }
        startQueuedConnections()
    }

    private func publishDeviceIfAvailable(_ session: PeripheralSession) {
        guard isAuthorized(session), let batteryLevel = session.batteryLevel else { return }
        let now = Date()
        nearbyDevices = nearbyDevices.filter {
            now.timeIntervalSince($0.value.lastUpdated) <= BluetoothLEBatteryScanPolicy.resultLifetime
        }
        let name = BluetoothLEBatteryNamePolicy.resolvedName(
            formalName: session.peripheral.name,
            advertisedName: session.advertisedName
        )
        nearbyDevices[session.peripheral.identifier] = NearbyBluetoothBatteryDevice(
            id: session.peripheral.identifier,
            name: name,
            batteryLevel: batteryLevel,
            model: session.model,
            manufacturer: session.manufacturer,
            lastUpdated: now
        )
        if readFailures.remove(session.peripheral.identifier) != nil {
            onReadFailures?(readFailures)
        }
        onDevicesChanged?(nearbyDevices.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private func publishCandidate(id: UUID, name: String, vendor: NearbyBLEVendor) {
        candidateCache.record(NearbyBLEDeviceCandidate(
            id: id,
            name: name,
            vendor: vendor,
            lastSeen: Date()
        ))
        publishCandidates()
    }

    private func isAuthorized(_ session: PeripheralSession) -> Bool {
        isReadPermitted(session.peripheral.identifier, session: session)
    }

    private func isReadPermitted(_ identifier: UUID, session: PeripheralSession? = nil) -> Bool {
        guard let session else {
            return readAuthorization.token(for: identifier) != nil
                || initialReadAuthorization.token(for: identifier) != nil
        }
        guard let token = session.authorizationToken,
              session.peripheral.identifier == identifier else { return false }
        return readAuthorization.accepts(identifier, token: token)
            || initialReadAuthorization.accepts(identifier, token: token)
    }

    func initialReadToken(for id: UUID) -> DeviceOperationToken? {
        initialReadAuthorization.token(for: id)
    }

    func acceptsInitialRead(_ id: UUID, token: DeviceOperationToken?) -> Bool {
        initialReadAuthorization.permits(id, token: token)
    }

    func currentReadToken(for id: UUID) -> DeviceOperationToken? {
        readAuthorization.token(for: id)
    }

    var initialReadGrantCount: Int {
        initialReadAuthorization.grantCount
    }

    var sessionAuthorizationCheckCount: Int {
        sessions.count + cancellingPeripherals.count
    }

    var readGrantCount: Int {
        readAuthorization.grantCount
    }

    private func setScanning(_ scanning: Bool) {
        guard isScanning != scanning else { return }
        isScanning = scanning
        onIsScanningChanged?(scanning)
    }

    private func currentSession(for identifier: UUID) -> PeripheralSession? {
        guard let session = sessions[identifier],
              policy.acceptsCallback(from: session.generation),
              sessionCancellationGate.isCurrent(identifier, session: session.sessionID) else {
            return nil
        }
        return session
    }

    private func currentSession(for peripheral: CBPeripheral, sessionID: UUID) -> PeripheralSession? {
        guard let session = currentSession(for: peripheral.identifier, sessionID: sessionID),
              session.peripheral === peripheral else { return nil }
        return session
    }

    private func currentSession(for identifier: UUID, sessionID: UUID) -> PeripheralSession? {
        guard let session = sessions[identifier],
              session.sessionID == sessionID,
              sessionCancellationGate.isCurrent(identifier, session: sessionID),
              policy.acceptsCallback(from: session.generation) else { return nil }
        return session
    }

    private func finishCancellation(for peripheral: CBPeripheral, central: CBCentralManager) -> Bool {
        let id = peripheral.identifier
        guard let cancelling = cancellingPeripherals[id],
              cancelling.peripheral === peripheral,
              cancelling.central === central,
              sessionCancellationGate.finishCancellation(id, session: cancelling.sessionID) else { return false }
        cancellingPeripherals.removeValue(forKey: id)
        peripheral.delegate = nil
        releaseCentralIfIdle()
        if isRunning, isScanning { startQueuedConnections() }
        return true
    }

    private func releaseCentralIfIdle() {
        guard !isRunning, sessions.isEmpty, cancellingPeripherals.isEmpty,
              let centralManager else { return }
        centralManager.delegate = nil
        self.centralManager = nil
    }

    private func publishCandidates() {
        onCandidatesChanged?(candidateCache.candidates)
        candidateExpiryTask?.cancel()
        guard let expiration = candidateCache.nextExpiration else { candidateExpiryTask = nil; return }
        candidateExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, expiration.timeIntervalSinceNow))) }
            catch { return }
            guard let self else { return }
            _ = self.candidateCache.expire(at: Date())
            self.onCandidatesChanged?(self.candidateCache.candidates)
        }
    }

    private func stopActiveWork(clearResults: Bool = false) {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        scanWindowTask?.cancel()
        scanWindowTask = nil
        centralManager?.stopScan()
        setScanning(false)
        candidatePeripherals.removeAll(keepingCapacity: false)
        candidateNames.removeAll(keepingCapacity: false)
        _ = candidateCache.clear()
        candidateExpiryTask?.cancel()
        candidateExpiryTask = nil

        let activeSessions = Array(sessions.values)
        sessions.removeAll(keepingCapacity: false)
        for session in activeSessions {
            session.timeoutTask?.cancel()
            if sessionCancellationGate.retire(session.peripheral.identifier, session: session.sessionID) {
                cancellingPeripherals[session.peripheral.identifier] = CancellingPeripheral(
                    sessionID: session.sessionID,
                    peripheral: session.peripheral,
                    delegate: session.delegate,
                    central: centralManager
                )
                centralManager?.cancelPeripheralConnection(session.peripheral)
            }
        }
        policy.stop()
        if clearResults {
            nearbyDevices.removeAll(keepingCapacity: false)
        }
    }

    private func isUUID(_ lhs: CBUUID, _ rhs: CBUUID) -> Bool {
        lhs.uuidString.caseInsensitiveCompare(rhs.uuidString) == .orderedSame
    }
}
