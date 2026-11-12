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
    private var hasAttemptedCPURead = false

    func reset() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.cpuReader.reset()
                self.hasAttemptedCPURead = false
                continuation.resume()
            }
        }
    }

    func read(ids: Set<HardwareMetricID>, at date: Date) async -> HardwareMetricsSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                let first = !self.hasAttemptedCPURead
                let snapshot = Self.collect(ids: ids, isFirstCPURead: first, at: date,
                                            cpuProvider: { self.cpuReader.read(at: $0) },
                                            gpuProvider: { self.gpuReader.read(at: $0) },
                                            memoryProvider: { self.memoryReader.read(at: $0) },
                                            sensorProvider: { temperature, gpuTemperature, batteryTemperature, fans, date in
                    self.sensorReader.read(includeTemperature: temperature,
                                           includeGPUTemperature: gpuTemperature,
                                           includeBatteryTemperature: batteryTemperature,
                                           includeFans: fans, at: date)
                },
                                            networkProvider: { self.networkReader.read(at: $0) })
                if ids.contains(.cpuUsage) { self.hasAttemptedCPURead = true }
                continuation.resume(returning: snapshot)
            }
        }
    }

    /// Synchronous injection seam. Demand checks here are also the production
    /// path: temperature never triggers GPU usage, and CPU-only never opens SMC.
    static func collect(ids: Set<HardwareMetricID>, isFirstCPURead: Bool, at date: Date,
                        cpuProvider: (Date) -> CPUReading?,
                        gpuProvider: (Date) -> GPUReading?,
                        memoryProvider: (Date) -> MemoryReader.Reading?,
                        sensorProvider: (Bool, Bool, Bool, Bool, Date) -> SensorReading,
                        networkProvider: (Date) -> NetworkThroughputReading? = { _ in nil }) -> HardwareMetricsSnapshot {
        let temperature = ids.contains(.cpuTemperature)
        let gpuTemperature = ids.contains(.gpuTemperature)
        let batteryTemperature = ids.contains(.batteryTemperature)
        let fans = ids.contains { if case .fanRPM = $0 { return true }; return false }
        let cpu = ids.contains(.cpuUsage) ? cpuProvider(date) : nil
        let gpu = ids.contains(.gpuUsage) ? gpuProvider(date) : nil
        let memory = ids.contains(.memoryUsage) ? memoryProvider(date) : nil
        let needsNetwork = ids.contains(.networkDownload) || ids.contains(.networkUpload)
        let sensors = temperature || gpuTemperature || batteryTemperature || fans
            ? sensorProvider(temperature, gpuTemperature, batteryTemperature, fans, date) : nil
        let network = needsNetwork ? networkProvider(date) : nil
        return map(ids: ids, cpu: cpu, gpu: gpu, memory: memory, sensors: sensors, network: network,
                   isFirstCPURead: isFirstCPURead, at: date)
    }

    /// Pure mapping of one read attempt. Reader nil alone cannot establish lack
    /// of platform support, so it becomes temporarilyUnavailable. Only CPU's
    /// first baseline attempt remains collecting; only an explicit FNum==0 is
    /// fanless. Fan-family demand includes all per-fan values and limits.
    static func map(ids: Set<HardwareMetricID>, cpu: CPUReading?, gpu: GPUReading?,
                    memory: MemoryReader.Reading? = nil, sensors: SensorReading?,
                    network: NetworkThroughputReading? = nil,
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
            }
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
