import Foundation
import OSLog

private let temperatureLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "hardware-temperature"
)

/// One serial utility queue owns all Reader state and keeps IOKit off the main
/// actor. Each result explicitly answers the requested IDs, including failures.
final class HardwareSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.hardware-sampler", qos: .utility)
    private var cpuReader = CPUReader()
    private let gpuReader = GPUReader()
    private let memoryReader = MemoryReader()
    private let sensorReader = SensorSMCReader()
    private let networkReader = NetworkThroughputReader()
    private let diskReader = DiskThroughputReader()
    private let cpuFrequencyReader = CPUFrequencyReader()
    private var hasAttemptedCPURead = false

    /// CPU/GPU temperature fallback. All state is touched only on `queue`.
    private let temperatureCoordinator: TemperatureFallbackCoordinator
    private let hidTransportFactory: () -> HIDTemperatureTransport
    private var hidReader: SensorHIDReader?
    private var loggedHIDMetrics: Set<TemperatureMetric> = []

    init(platform: SensorPlatform = .current(),
         hidTransportFactory: @escaping () -> HIDTemperatureTransport = { LiveHIDTemperatureTransport() }) {
        temperatureCoordinator = TemperatureFallbackCoordinator.production(platform: platform)
        self.hidTransportFactory = hidTransportFactory
    }

    func reset() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.cpuReader.reset()
                self.cpuFrequencyReader.reset()
                self.networkReader.resetSession()
                self.diskReader.reset()
                self.hasAttemptedCPURead = false
                self.temperatureCoordinator.reset()
                self.releaseHIDReader()
                self.loggedHIDMetrics = []
                continuation.resume()
            }
        }
    }

    /// Releases the IOReport subscription when frequency sampling is no longer
    /// needed (CPU detail closed/hidden). Idempotent and cheap.
    func releaseFrequencyReader() {
        queue.async { self.cpuFrequencyReader.reset() }
    }

    /// Drops the network session counters when the network detail page closes.
    func resetNetworkSession() {
        queue.async { self.networkReader.resetSession() }
    }

    /// Mirrors which temperature metrics still have a consumer. Metrics that
    /// lost demand drop their fallback state; if neither metric needs HID any
    /// more, the client and service cache are released.
    func updateTemperatureDemand(hasCPU: Bool, hasGPU: Bool) {
        queue.async {
            var demanded: Set<TemperatureMetric> = []
            if hasCPU { demanded.insert(.cpu) }
            if hasGPU { demanded.insert(.gpu) }
            self.temperatureCoordinator.setDemandedMetrics(demanded)
            if self.temperatureCoordinator.activeHIDMetrics.isEmpty {
                self.releaseHIDReader()
                self.loggedHIDMetrics = []
            }
        }
    }

    /// Drops all fallback state and HID resources (sleep, shutdown, reset).
    func releaseTemperatureFallback() {
        queue.async {
            self.temperatureCoordinator.reset()
            self.releaseHIDReader()
            self.loggedHIDMetrics = []
        }
    }

    private func ensureHIDReader() -> SensorHIDReader {
        if let hidReader { return hidReader }
        let reader = SensorHIDReader(transport: hidTransportFactory())
        hidReader = reader
        return reader
    }

    private func releaseHIDReader() {
        hidReader?.release()
        hidReader = nil
    }

    /// Detail payloads are only built for families that are actually due this
    /// tick. Building a page from a tick that did not read its metric would
    /// overwrite the last good payload with nil (or perturb GPU interval math).
    static func detailKindsToBuild(_ requested: Set<HardwareDetailKind>,
                                  ids: Set<HardwareMetricID>) -> Set<HardwareDetailKind> {
        requested.filter { kind in
            switch kind {
            case .cpu: return ids.contains(.cpuUsage)
            case .gpu: return ids.contains(.gpuUsage)
            case .memory: return ids.contains(.memoryUsage)
            case .network: return true
            case .disk: return ids.contains(.diskRead) || ids.contains(.diskWrite)
            case .fan:
                return ids.contains { id in
                    if case .fanRPM = id { return true }
                    return false
                }
            }
        }
    }

    /// `details` selects which structured detail payloads to build this tick; the
    /// plain metric samples still follow `ids`, so summary consumers are unaffected.
    func read(ids: Set<HardwareMetricID>, at date: Date,
              includeCPUFrequency: Bool = false,
              details: Set<HardwareDetailKind> = []) async -> HardwareMetricsSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                let first = !self.hasAttemptedCPURead
                let wantsFrequency = includeCPUFrequency && ids.contains(.cpuUsage)
                let detailKinds = Self.detailKindsToBuild(details, ids: ids)
                // GPU utilisation counts render work over the interval since the
                // last query; querying IOAccelerator twice in a row makes the
                // second read see an empty interval and report 0%. Read once and
                // derive both the plain sample and the detail from it.
                let wantsCPUDetail = detailKinds.contains(.cpu)
                let wantsGPUDetail = detailKinds.contains(.gpu)
                let memorySnapshot = detailKinds.contains(.memory) && ids.contains(.memoryUsage)
                    ? self.memoryReader.readWithDetail(at: date) : nil
                let gpuDetail: GPUDetailReading? = wantsGPUDetail
                    ? self.gpuReader.readDetail(at: date) : nil
                let gpuReading: GPUReading? = gpuDetail.flatMap { detail in
                    guard let usage = detail.usage else { return nil }
                    return GPUReading(usage: usage, deviceName: detail.deviceName, sampledAt: date)
                }
                // Read IOAccelerator exactly once per tick: reuse the detail read
                // when the GPU page is open, otherwise fall back to the plain read.
                let gpuProvider: (Date) -> GPUReading? = { sampleDate in
                    wantsGPUDetail ? gpuReading : self.gpuReader.read(at: sampleDate)
                }
                var snapshot = Self.collect(ids: ids, isFirstCPURead: first, at: date,
                                            cpuProvider: { self.cpuReader.read(at: $0, includeDetail: wantsCPUDetail) },
                                            frequencyProvider: { wantsFrequency ? self.cpuFrequencyReader.read(at: $0) : nil },
                                            includeCPUFrequency: wantsFrequency,
                                            includeCPUDetail: wantsCPUDetail,
                                            gpuProvider: gpuProvider,
                                            memoryProvider: { sampleDate in
                                                memorySnapshot?.reading ?? self.memoryReader.read(at: sampleDate)
                                            },
                                            sensorProvider: { temperature, gpuTemperature, batteryTemperature, fans, date in
                    self.readSensors(includeCPU: temperature,
                                     includeGPU: gpuTemperature,
                                     includeBattery: batteryTemperature,
                                     includeFans: fans, at: date)
                },
                                            networkProvider: { self.networkReader.read(at: $0) },
                                            diskProvider: { self.diskReader.read(at: $0) })
                if let gpuDetail {
                    snapshot.gpuDetail = gpuDetail
                }
                if let memorySnapshot {
                    snapshot.memoryDetail = memorySnapshot.detail
                }
                if detailKinds.contains(.network) {
                    snapshot.networkDetail = self.networkReader.detailReading(from: nil, at: date)
                }
                if detailKinds.contains(.disk) {
                    let capacity = DiskCapacityReader.read(at: date)
                    snapshot.diskDetail = DiskDetailReading(
                        capacity: capacity,
                        readBytesPerSecond: snapshot.samples[.diskRead]?.value,
                        writeBytesPerSecond: snapshot.samples[.diskWrite]?.value,
                        sampledAt: date)
                }
                if ids.contains(.cpuUsage) { self.hasAttemptedCPURead = true }
                continuation.resume(returning: snapshot)
            }
        }
    }

    /// Unified SMC/HID temperature read for one tick. SMC stays the default; the
    /// coordinator only asks for HID after a metric has failed twice on an
    /// eligible chip. Battery and fan reads ride the same SMC connection.
    private func readSensors(includeCPU: Bool, includeGPU: Bool,
                             includeBattery: Bool, includeFans: Bool,
                             at date: Date) -> SensorReading {
        var demanded: Set<TemperatureMetric> = []
        if includeCPU { demanded.insert(.cpu) }
        if includeGPU { demanded.insert(.gpu) }

        guard !demanded.isEmpty else {
            return sensorReader.read(includeTemperature: false, includeGPUTemperature: false,
                                     includeBatteryTemperature: includeBattery,
                                     includeFans: includeFans, at: date)
        }

        var smcReading: SensorReading?
        let decisions = temperatureCoordinator.resolve(
            demanded: demanded,
            at: date,
            smc: { metrics, sampleDate in
                if metrics.isEmpty, !includeBattery, !includeFans { return [:] }
                let reading = self.sensorReader.read(
                    includeTemperature: metrics.contains(.cpu),
                    includeGPUTemperature: metrics.contains(.gpu),
                    includeBatteryTemperature: includeBattery,
                    includeFans: includeFans,
                    at: sampleDate)
                smcReading = reading
                var values: [TemperatureMetric: Double?] = [:]
                if metrics.contains(.cpu) { values[.cpu] = reading.cpuTemperature }
                if metrics.contains(.gpu) { values[.gpu] = reading.gpuTemperature }
                return values
            },
            hid: { metrics, sampleDate in
                let reader = self.ensureHIDReader()
                return reader.read(targets: metrics, at: sampleDate)
            })

        if temperatureCoordinator.activeHIDMetrics.isEmpty {
            releaseHIDReader()
        }
        logFallbackTransitions(decisions: decisions)
        return mergedSensorReading(smcReading, decisions: decisions, demanded: demanded, at: date)
    }

    private func mergedSensorReading(_ smcReading: SensorReading?,
                                     decisions: [TemperatureMetric: TemperatureDecision],
                                     demanded: Set<TemperatureMetric>,
                                     at date: Date) -> SensorReading {
        var result = smcReading ?? SensorReading(cpuTemperature: nil, cpuTemperatureSource: nil,
                                                 gpuTemperature: nil, fans: [], fanCount: nil,
                                                 sampledAt: date)
        for metric in demanded {
            switch (metric, decisions[metric] ?? .unavailable) {
            case (.cpu, .smc):
                result.cpuTemperatureOrigin = .smc
            case (.cpu, .hid(let measurement)):
                result.cpuTemperature = measurement.value
                result.cpuTemperatureSource = measurement.count == 1 ? .single : .average(measurement.count)
                result.cpuTemperatureOrigin = .hid
            case (.cpu, .unavailable):
                result.cpuTemperature = nil
                result.cpuTemperatureSource = nil
                result.cpuTemperatureOrigin = .smc
            case (.gpu, .smc):
                result.gpuTemperatureOrigin = .smc
            case (.gpu, .hid(let measurement)):
                result.gpuTemperature = measurement.value
                result.gpuTemperatureOrigin = .hid
            case (.gpu, .unavailable):
                result.gpuTemperature = nil
                result.gpuTemperatureOrigin = .smc
            }
        }
        return result
    }

    private func logFallbackTransitions(decisions: [TemperatureMetric: TemperatureDecision]) {
        #if DEBUG
        let active = temperatureCoordinator.activeHIDMetrics
        for metric in active.subtracting(loggedHIDMetrics) {
            temperatureLogger.debug("HID fallback activated: \(metric.rawValue)")
            if case .hid(let measurement) = decisions[metric] {
                temperatureLogger.debug("HID sensor count \(metric.rawValue)=\(measurement.count)")
            }
        }
        for metric in loggedHIDMetrics.subtracting(active) {
            if decisions[metric] == .smc {
                temperatureLogger.debug("SMC recovered: \(metric.rawValue)")
            } else {
                temperatureLogger.debug("HID fallback released: \(metric.rawValue)")
            }
        }
        loggedHIDMetrics = active
        #endif
    }

    /// Synchronous injection seam. Demand checks here are also the production
    /// path: temperature never triggers GPU usage, and CPU-only never opens SMC.
    static func collect(ids: Set<HardwareMetricID>, isFirstCPURead: Bool, at date: Date,
                        cpuProvider: (Date) -> CPUReading?,
                        frequencyProvider: (Date) -> CPUFrequencyReading? = { _ in nil },
                        includeCPUFrequency: Bool = false,
                        includeCPUDetail: Bool = false,
                        gpuProvider: (Date) -> GPUReading?,
                        memoryProvider: (Date) -> MemoryReader.Reading?,
                        sensorProvider: (Bool, Bool, Bool, Bool, Date) -> SensorReading,
                        networkProvider: (Date) -> NetworkThroughputReading? = { _ in nil },
                        diskProvider: (Date) -> DiskThroughputReading? = { _ in nil }) -> HardwareMetricsSnapshot {
        let temperature = ids.contains(.cpuTemperature)
        let gpuTemperature = ids.contains(.gpuTemperature)
        let batteryTemperature = ids.contains(.batteryTemperature)
        let fans = ids.contains { if case .fanRPM = $0 { return true }; return false }
        let cpu = ids.contains(.cpuUsage) ? cpuProvider(date) : nil
        let frequency = (cpu != nil && includeCPUFrequency) ? frequencyProvider(date) : nil
        let gpu = ids.contains(.gpuUsage) ? gpuProvider(date) : nil
        let memory = ids.contains(.memoryUsage) ? memoryProvider(date) : nil
        let needsNetwork = ids.contains(.networkDownload) || ids.contains(.networkUpload)
        let sensors = temperature || gpuTemperature || batteryTemperature || fans
            ? sensorProvider(temperature, gpuTemperature, batteryTemperature, fans, date) : nil
        let network = needsNetwork ? networkProvider(date) : nil
        let needsDisk = ids.contains(.diskRead) || ids.contains(.diskWrite)
        let disk = needsDisk ? diskProvider(date) : nil
        return map(ids: ids, cpu: cpu, gpu: gpu, memory: memory, sensors: sensors, network: network,
                   disk: disk, cpuFrequency: frequency, includeCPUDetail: includeCPUDetail,
                   isFirstCPURead: isFirstCPURead, at: date)
    }

    /// Pure mapping of one read attempt. Reader nil alone cannot establish lack
    /// of platform support, so it becomes temporarilyUnavailable. Only CPU's
    /// first baseline attempt remains collecting; only an explicit FNum==0 is
    /// fanless. Fan-family demand includes all per-fan values and limits.
    static func map(ids: Set<HardwareMetricID>, cpu: CPUReading?, gpu: GPUReading?,
                    memory: MemoryReader.Reading? = nil, sensors: SensorReading?,
                    network: NetworkThroughputReading? = nil,
                    disk: DiskThroughputReading? = nil,
                    cpuFrequency: CPUFrequencyReading? = nil,
                    includeCPUDetail: Bool = true,
                    isFirstCPURead: Bool, at date: Date) -> HardwareMetricsSnapshot {
        var snapshot = HardwareMetricsSnapshot.empty
        for id in ids {
            switch id {
            case .cpuUsage:
                let value = finite(cpu?.usage, in: 0...100)
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .percent, sampledAt: cpu?.sampledAt ?? date, source: .mach,
                    availability: value != nil ? .measured : (isFirstCPURead ? .collecting : .temporarilyUnavailable))
            case .gpuUsage:
                let value = finite(gpu?.usage, in: 0...100)
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .percent, sampledAt: gpu?.sampledAt ?? date, source: .ioAccelerator,
                    availability: value != nil ? .measured : .temporarilyUnavailable,
                    sensorLabel: gpu?.deviceName)
            case .memoryUsage:
                let value = finite(memory?.percent, in: 0...100)
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .percent, sampledAt: memory?.sampledAt ?? date, source: .mach,
                    availability: value != nil ? .measured : .temporarilyUnavailable)
            case .cpuTemperature, .gpuTemperature, .batteryTemperature:
                let value: Double?
                switch id {
                case .cpuTemperature: value = finite(sensors?.cpuTemperature, in: 0...150)
                case .gpuTemperature: value = finite(sensors?.gpuTemperature, in: 0...150)
                default: value = finite(sensors?.batteryTemperature, in: -20...90)
                }
                let source: HardwareMetricSource
                switch id {
                case .cpuTemperature: source = sensors?.cpuTemperatureOrigin ?? .smc
                case .gpuTemperature: source = sensors?.gpuTemperatureOrigin ?? .smc
                default: source = .smc
                }
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .celsius, sampledAt: sensors?.sampledAt ?? date, source: source,
                    availability: value != nil ? .measured : .temporarilyUnavailable,
                    sensorLabel: id == .cpuTemperature ? sensors?.cpuTemperatureLabel
                        : (id == .gpuTemperature ? (sensors?.gpuTemperatureLabel ?? "GPU area") : "Battery"),
                    metadata: HardwareMetricMetadata(sourceCount: id == .cpuTemperature ? sensors?.cpuTemperatureCount : nil))
            case .fanRPM:
                // Fill requested slots even when FNum or a fan read failed.
                snapshot.samples[id] = HardwareMetricSample(
                    unit: .rpm, sampledAt: sensors?.sampledAt ?? date, source: .smc,
                    availability: .temporarilyUnavailable)
            case .networkDownload, .networkUpload:
                let value: Double? = network.map { reading in
                    id == .networkDownload
                        ? max(0, reading.downloadBytesPerSecond)
                        : max(0, reading.uploadBytesPerSecond)
                }
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .bytesPerSecond, sampledAt: network?.sampledAt ?? date,
                    source: .network, availability: value != nil ? .measured : .collecting)
            case .diskRead, .diskWrite:
                let value: Double? = disk.map { reading in
                    id == .diskRead
                        ? max(0, reading.readBytesPerSecond)
                        : max(0, reading.writeBytesPerSecond)
                }
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .bytesPerSecond, sampledAt: disk?.sampledAt ?? date,
                    source: .ioStorage, availability: value != nil ? .measured : .collecting)
            case .volume, .wifiSignal, .batteryLevel:
                // Status-snapshot readings come from the general snapshot, not the
                // hardware sampler; leave the slot untouched if ever requested.
                break
            }
        }
        snapshot.cpuFrequency = cpuFrequency
        if let cpu, includeCPUDetail {
            snapshot.cpuDetail = CPUDetailReading(
                usage: cpu.usage,
                breakdown: cpu.breakdown,
                perCoreUsage: cpu.perCoreUsage,
                topology: cpu.topology,
                groupUsage: cpu.groupUsage,
                frequency: cpuFrequency,
                sampledAt: cpu.sampledAt)
        }
        let requestedFans = ids.compactMap { id -> Int? in
            if case .fanRPM(let index) = id { return index }
            return nil
        }
        guard !requestedFans.isEmpty else { return snapshot }
        snapshot.fanCount = sensors?.fanCount
        let count = sensors?.fanCount
        let fanless = count == 0
        var indices = Set(requestedFans)
        let fans = sensors?.fans ?? []
        indices.formUnion(fans.map { $0.index })
        if let count, (1...16).contains(count) { indices.formUnion(0..<count) }
        for index in indices {
            let fan = fanless ? nil : fans.first { $0.index == index }
            let outsideKnownCount = index < 0 || (count.map { index >= $0 } ?? false)
            let value = outsideKnownCount ? nil : finite(fan?.rpm, in: 0...30_000)
            let availability: HardwareMetricAvailability = value != nil ? .measured :
                (fanless || outsideKnownCount ? .unsupported : .temporarilyUnavailable)
            snapshot.samples[.fanRPM(index: index)] = HardwareMetricSample(
                value: value, unit: .rpm, sampledAt: sensors?.sampledAt ?? date, source: .smc,
                availability: availability, sensorLabel: fan?.name,
                metadata: HardwareMetricMetadata(maximum: fan?.maxRPM, minimum: fan?.minRPM, isFanless: fanless))
        }
        return snapshot
    }

    private static func finite(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }
}
