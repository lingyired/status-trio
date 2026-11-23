import Foundation

/// Reads the operating system's paired-device database from the system
/// profiler. It deliberately does not perform a Bluetooth inquiry, so nearby
/// BLE advertisements never appear as paired devices.
final class SystemProfilerBluetoothPairedDeviceWorker: @unchecked Sendable, BluetoothPairedDeviceReading {
    typealias OutputProvider = @Sendable () -> Data?
    private static let queueLabel = "StatusTrio.SystemProfilerBluetoothPairedDeviceWorker"

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
            let cacheEpoch = self?.reportCache.currentEpoch
            if let data = outputProvider(),
               let devices = BluetoothPairedDeviceReader.parse(json: data) {
                if let self, let cacheEpoch {
                    self.reportCache.store(data, ifCurrent: cacheEpoch)
                }
                result = .success(devices)
            } else {
                result = .failed
            }
            if let self {
                self.stateLock.withLock {
                    if generation == self.queueGeneration {
                        self.hasOutstandingRead = false
                    }
                }
            }
            completion(result)
        }
    }

    static let readTimeout: Duration = .seconds(4)

    static func readSystemProfilerOutput() -> Data? {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
            arguments: ["-json", "SPBluetoothDataType"],
            timeout: readTimeout
        )
        guard case .exited(let data) = outcome else { return nil }
        return data
    }
}

final class SystemProfilerBluetoothBatteryWorker: @unchecked Sendable, BluetoothBatteryReading {
    typealias OutputProvider = @Sendable () -> Data?
    private let queue = DispatchQueue(label: "StatusTrio.SystemProfilerBluetoothBatteryWorker")
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothBatteryWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        queue.async {
            let data: Data?
            if let cached = self.reportCache.freshData() {
                data = cached
            } else {
                let cacheEpoch = self.reportCache.currentEpoch
                data = self.outputProvider()
                if let fetched = data {
                    self.reportCache.store(fetched, ifCurrent: cacheEpoch)
                }
            }
            guard let data else {
                completion(nil)
                return
            }
            completion(BluetoothBatteryReader.parse(json: data))
        }
    }

    static func readSystemProfilerOutput() -> Data? {
        SystemProfilerBluetoothPairedDeviceWorker.readSystemProfilerOutput()
    }
}

/// Reads accessory power sources out of `pmset -g accps -xml`.
final class PmsetAccessoryBatteryWorker: @unchecked Sendable, BluetoothAccessoryBatteryReading {
    typealias OutputProvider = @Sendable () -> String?

    private static let queueLabel = "StatusTrio.PmsetAccessoryBatteryWorker"

    private let stateLock = NSLock()
    private var queue = DispatchQueue(label: queueLabel, qos: .utility)
    private var queueGeneration: UInt64 = 0
    private var hasOutstandingRead = false
    private let outputProvider: OutputProvider

    init(
        outputProvider: @escaping OutputProvider = PmsetAccessoryBatteryWorker.readAccessoryPowerSources
    ) {
        self.outputProvider = outputProvider
    }

    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
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
            let levels = outputProvider().map { BluetoothAccessoryBatteryReader.parse(xml: $0) }
            if let self {
                self.stateLock.withLock {
                    if generation == self.queueGeneration {
                        self.hasOutstandingRead = false
                    }
                }
            }
            completion(levels)
        }
    }

    static func readAccessoryPowerSources() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps", "-xml"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// Reads preferred-network names without accessing stored passwords.
final class NetworksetupWiFiKnownNetworkProvider: WiFiKnownNetworkProviding, @unchecked Sendable {
    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    static let defaultTimeout: Duration = .seconds(3)

    private let timeout: Duration

    init(timeout: Duration = NetworksetupWiFiKnownNetworkProvider.defaultTimeout) {
        self.timeout = timeout
    }

    func preferredNetworkSSIDs(interface: String) -> Set<String> {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: Self.executableURL,
            arguments: WiFiNetworkSetupCommand
                .listPreferredNetworks(interface: interface)
                .arguments,
            timeout: timeout
        )
        guard case .exited(let outputData) = outcome else { return [] }
        return WiFiPreferredNetworkOutputParser.parse(
            String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
