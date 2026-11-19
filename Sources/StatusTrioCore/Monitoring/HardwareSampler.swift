import Foundation

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

    func reset() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.cpuReader.reset()
                self.cpuFrequencyReader.reset()
                self.networkReader.resetSession()
                self.diskReader.reset()
                self.hasAttemptedCPURead = false
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
                let wantsGPUDetail = detailKinds.contains(.gpu)
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
                                            cpuProvider: { self.cpuReader.read(at: $0) },
                                            frequencyProvider: { wantsFrequency ? self.cpuFrequencyReader.read(at: $0) : nil },
                                            includeCPUFrequency: wantsFrequency,
                                            gpuProvider: gpuProvider,
                                            memoryProvider: { self.memoryReader.read(at: $0) },
                                            sensorProvider: { temperature, gpuTemperature, batteryTemperature, fans, date in
                    self.sensorReader.read(includeTemperature: temperature,
                                           includeGPUTemperature: gpuTemperature,
                                           includeBatteryTemperature: batteryTemperature,
                                           includeFans: fans, at: date)
                },
                                            networkProvider: { self.networkReader.read(at: $0) },
                                            diskProvider: { self.diskReader.read(at: $0) })
                if let gpuDetail {
                    snapshot.gpuDetail = gpuDetail
                }
                if detailKinds.contains(.memory) {
                    snapshot.memoryDetail = self.memoryReader.readDetail(at: date)
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

    /// Synchronous injection seam. Demand checks here are also the production
    /// path: temperature never triggers GPU usage, and CPU-only never opens SMC.
    static func collect(ids: Set<HardwareMetricID>, isFirstCPURead: Bool, at date: Date,
                        cpuProvider: (Date) -> CPUReading?,
                        frequencyProvider: (Date) -> CPUFrequencyReading? = { _ in nil },
                        includeCPUFrequency: Bool = false,
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
                   disk: disk, cpuFrequency: frequency, isFirstCPURead: isFirstCPURead, at: date)
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
                snapshot.samples[id] = HardwareMetricSample(
                    value: value, unit: .celsius, sampledAt: sensors?.sampledAt ?? date, source: .smc,
                    availability: value != nil ? .measured : .temporarilyUnavailable,
                    sensorLabel: id == .cpuTemperature ? sensors?.cpuTemperatureLabel
                        : (id == .gpuTemperature ? "GPU area" : "Battery"),
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
            case .volume, .wifiSignal:
                // Top-marker-only readings come from the status snapshot, not the
                // hardware sampler; leave the slot untouched if ever requested.
                break
            }
        }
        if let cpu {
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
