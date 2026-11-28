import Foundation

/// Stable identifier for a hardware metric, independent of any SMC key.
enum HardwareMetricID: Hashable, Sendable {
    case cpuUsage
    case gpuUsage
    case memoryUsage
    case memoryPressure
    case cpuTemperature
    case gpuTemperature
    case batteryTemperature
    case fanRPM(index: Int)
    /// Aggregate download throughput across physical interfaces (bytes/second).
    case networkDownload
    /// Aggregate upload throughput across physical interfaces (bytes/second).
    case networkUpload
    /// Aggregate read throughput across physical storage devices (bytes/second).
    case diskRead
    /// Aggregate write throughput across physical storage devices (bytes/second).
    case diskWrite
    /// Output volume percentage. Read from the audio snapshot, never sampled by
    /// the hardware service; the identity keeps `HardwareMonitorMetric.metricID`
    /// total without inventing a hardware family.
    case volume
    /// Wi-Fi signal strength percentage. Read from the network snapshot, never
    /// sampled by the hardware service.
    case wifiSignal
    /// Mac battery level percentage. Read from the battery snapshot, never
    /// sampled by the hardware service.
    case batteryLevel
}

/// How a metric sample may be presented. Distinct from a mere missing value so
/// the UI can keep a fixed slot without inventing a number.
enum HardwareMetricAvailability: Equatable, Sendable {
    /// A real measured value. `value` is present and fresh enough to show.
    case measured
    /// The platform does not expose this metric on this machine.
    case unsupported
    /// Exists but is not readable now (device asleep, driver down, transient IPC).
    case temporarilyUnavailable
    /// The last measured value is too old to present as live.
    case stale
    /// No sample has arrived yet (initial loading state).
    case collecting
}

/// Unit of a metric value. Formatters localize the glyph; this is the semantic.
enum HardwareMetricUnit: Equatable, Sendable {
    case percent
    case celsius
    case rpm
    /// Bytes per second (network throughput); formatters pick KB/s or MB/s.
    case bytesPerSecond
    case none
}

/// Where the sample came from, used for diagnostics and accessibility copy.
enum HardwareMetricSource: Equatable, Sendable {
    case mach
    case smc
    /// Apple HID event-system temperature fallback (base Apple M1 only).
    case hid
    case ioAccelerator
    case powerIO
    case network
    case ioStorage
}

/// Optional sample metadata (fan limits, temperature sample statistics).
struct HardwareMetricMetadata: Equatable, Sendable {
    /// The controller's maximum RPM for the fan this sample represents.
    var maximum: Double?
    var minimum: Double?
    /// Number of sensor readings averaged into a temperature sample.
    var sourceCount: Int?
    /// `true` for a machine with no fan sensor at all; distinguishes "no fan"
    /// from "fan temporarily unreadable".
    var isFanless: Bool

    init(maximum: Double? = nil, minimum: Double? = nil, sourceCount: Int? = nil, isFanless: Bool = false) {
        self.maximum = maximum
        self.minimum = minimum
        self.sourceCount = sourceCount
        self.isFanless = isFanless
    }
}

/// One immutable sample of one metric.
struct HardwareMetricSample: Equatable, Sendable {
    var value: Double?
    var unit: HardwareMetricUnit
    var sampledAt: Date
    var source: HardwareMetricSource
    var availability: HardwareMetricAvailability
    var sensorLabel: String?
    var metadata: HardwareMetricMetadata

    init(value: Double? = nil,
         unit: HardwareMetricUnit,
         sampledAt: Date = .distantPast,
         source: HardwareMetricSource,
         availability: HardwareMetricAvailability = .collecting,
         sensorLabel: String? = nil,
         metadata: HardwareMetricMetadata = .init()) {
        self.value = value
        self.unit = unit
        self.sampledAt = sampledAt
        self.source = source
        self.availability = availability
        self.sensorLabel = sensorLabel
        self.metadata = metadata
    }

    /// Value age after which a measured sample is no longer presented as live.
    static let freshnessInterval: TimeInterval = 8
    /// Small negative tolerance absorbs clock skew between the sampling queue
    /// and the presenting surface without accepting genuinely old values.
    static let freshRange = (-5.0)...TimeInterval(8)

    func isFresh(at now: Date) -> Bool {
        availability == .measured &&
            Self.freshRange.contains(now.timeIntervalSince(sampledAt))
    }

    /// How long a non-fresh reading stays available as a cached last value.
    /// Beyond this the number is dropped rather than shown as a days-old reading.
    static let cacheLifetime: TimeInterval = 300

    /// A measured sample that is no longer fresh becomes `stale`. It keeps its
    /// value as a *cached* last reading (shown dimmed, not as live telemetry) so
    /// reopening the panel is not a blank flash; only past `cacheLifetime` is the
    /// value dropped.
    func expiring(at now: Date) -> HardwareMetricSample {
        let age = now.timeIntervalSince(sampledAt)
        // An already-stale value must also be dropped once it is older than the
        // cache lifetime, otherwise a long-closed panel could show it forever.
        if availability == .stale {
            guard age > Self.cacheLifetime || age < -Self.cacheLifetime else { return self }
            var copy = self
            copy.value = nil
            return copy
        }
        guard availability == .measured else { return self }
        guard !Self.freshRange.contains(age) else { return self }
        var copy = self
        copy.availability = .stale
        if age > Self.cacheLifetime || age < -Self.cacheLifetime {
            copy.value = nil
        }
        return copy
    }
}

/// Structured CPU detail for the dedicated CPU page. Carried alongside the
/// plain `cpuUsage` metric so the page subscribes to one leaf snapshot without
/// widening the panel's `@Published` surface.
struct CPUDetailReading: Equatable, Sendable {
    var usage: Double
    var breakdown: CPUTimeBreakdown
    var perCoreUsage: [Double]
    var topology: CPUCoreTopology?
    var groupUsage: CPUCoreGroupUsage?
    /// Estimated cluster frequency; `nil` when IOReport/tables are unavailable.
    var frequency: CPUFrequencyReading?
    var sampledAt: Date

    var coreCount: Int { perCoreUsage.count }
}

struct MemoryPressureReading: Equatable, Sendable {
    let level: MemoryPressureLevel
    let sampledAt: Date

    func isFresh(at now: Date) -> Bool {
        HardwareMetricSample.freshRange.contains(now.timeIntervalSince(sampledAt))
    }
}

/// One refresh's aggregate snapshot. UI layers observe this, never a broad
/// panel snapshot, so a metric tick cannot re-render unrelated sections.
struct HardwareMetricsSnapshot: Equatable, Sendable {
    var samples: [HardwareMetricID: HardwareMetricSample] = [:]
    /// Fan controller count when known; `nil` until read, `0` on fanless Macs.
    var fanCount: Int?
    /// Estimated CPU cluster frequency, sampled only while a ring or the CPU
    /// detail page needs it. Carried beside the samples so the panel ring can
    /// show it without opening the detail page.
    var cpuFrequency: CPUFrequencyReading?
    /// Structured per-page detail, populated only while that detail page is open.
    var cpuDetail: CPUDetailReading?
    var gpuDetail: GPUDetailReading?
    var memoryDetail: MemoryDetailReading?
    var memoryPressure: MemoryPressureReading?
    var networkDetail: NetworkDetailReading?
    var diskDetail: DiskDetailReading?

    static let empty = Self()

    subscript(id: HardwareMetricID) -> HardwareMetricSample {
        samples[id] ?? HardwareMetricSample(
            unit: Self.unit(for: id),
            source: .smc,
            availability: .collecting
        )
    }

    var cpuUsage: HardwareMetricSample { self[.cpuUsage] }
    var gpuUsage: HardwareMetricSample { self[.gpuUsage] }
    var memoryUsage: HardwareMetricSample { self[.memoryUsage] }
    var cpuTemperature: HardwareMetricSample { self[.cpuTemperature] }
    var gpuTemperature: HardwareMetricSample { self[.gpuTemperature] }
    var batteryTemperature: HardwareMetricSample { self[.batteryTemperature] }
    var networkDownload: HardwareMetricSample { self[.networkDownload] }
    var networkUpload: HardwareMetricSample { self[.networkUpload] }
    var diskRead: HardwareMetricSample { self[.diskRead] }
    var diskWrite: HardwareMetricSample { self[.diskWrite] }

    /// Per-fan samples sorted by index, for a future details expansion.
    var fanSamples: [HardwareMetricSample] {
        samples
            .compactMap { id, sample -> (Int, HardwareMetricSample)? in
                guard case let .fanRPM(index) = id else { return nil }
                return (index, sample)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    /// The card's fan tile sample: the hottest currently-readable fan, carrying
    /// that fan's own maximum RPM as the progress denominator.
    ///
    /// Semantics stay explicit: fan count not read yet → `collecting`; a
    /// fanless machine → `unsupported` with `metadata.isFanless`; fans exist but
    /// none measured → `temporarilyUnavailable`, never a fabricated zero.
    var fanSummarySample: HardwareMetricSample {
        let fans = fanSamples
        // A measured fan is the strongest evidence and is used first, so a
        // transient FNum read failure cannot blank a fan that is still reporting.
        if let hottest = fans
            .filter({ $0.availability == .measured && $0.value != nil })
            .max(by: { ($0.value ?? -1) < ($1.value ?? -1) }) {
            return hottest
        }
        if let fanCount, fanCount == 0 {
            return HardwareMetricSample(unit: .rpm, source: .smc,
                                        availability: .unsupported,
                                        metadata: HardwareMetricMetadata(isFanless: true))
        }
        if fans.isEmpty {
            // Fan count and fan samples are both unknown yet: loading, not fanless.
            return HardwareMetricSample(unit: .rpm, source: .smc, availability: .collecting)
        }
        // Keep the precise unavailable reason for VoiceOver: last data expired
        // is `stale`, a platform without fan sensors is `unsupported`, anything
        // else is a transient read failure.
        if fans.contains(where: { $0.availability == .stale }) {
            return HardwareMetricSample(unit: .rpm, source: .smc, availability: .stale)
        }
        if fans.allSatisfy({ $0.availability == .unsupported }) {
            return HardwareMetricSample(unit: .rpm, source: .smc,
                                        availability: .unsupported,
                                        metadata: HardwareMetricMetadata(isFanless: true))
        }
        return HardwareMetricSample(unit: .rpm, source: .smc,
                                    availability: .temporarilyUnavailable)
    }

    /// The status-panel summary's fan reading: the arithmetic mean of every
    /// currently-readable fan's RPM. A real 0 RPM fan participates. Stale,
    /// unreadable, NaN or negative samples never drag the average, and a fanless
    /// machine is reported as unsupported rather than averaging to zero. This is
    /// deliberately separate from `fanSummarySample` (the hottest fan), which
    /// stays the icon/ring source so its semantics do not change.
    var averageFanSample: HardwareMetricSample {
        let fans = fanSamples
        func value(_ s: HardwareMetricSample) -> Double? {
            guard let v = s.value, v.isFinite, v >= 0 else { return nil }
            return v
        }
        let fresh = fans.filter { $0.availability == .measured && value($0) != nil }
        if !fresh.isEmpty {
            let values = fresh.compactMap(value)
            let average = values.reduce(0, +) / Double(values.count)
            return HardwareMetricSample(
                value: average, unit: .rpm,
                sampledAt: fresh.map(\.sampledAt).max() ?? .distantPast, source: .smc,
                availability: .measured,
                metadata: HardwareMetricMetadata(sourceCount: values.count))
        }
        if let fanCount, fanCount == 0 {
            return HardwareMetricSample(unit: .rpm, source: .smc, availability: .unsupported,
                                        metadata: HardwareMetricMetadata(isFanless: true))
        }
        let stale = fans.filter { $0.availability == .stale && value($0) != nil }
        if !stale.isEmpty {
            let values = stale.compactMap(value)
            let average = values.reduce(0, +) / Double(values.count)
            return HardwareMetricSample(
                value: average, unit: .rpm,
                sampledAt: stale.map(\.sampledAt).max() ?? .distantPast, source: .smc,
                availability: .stale,
                metadata: HardwareMetricMetadata(sourceCount: values.count))
        }
        if fans.isEmpty {
            return HardwareMetricSample(unit: .rpm, source: .smc, availability: .collecting)
        }
        if fans.allSatisfy({ $0.availability == .unsupported }) {
            return HardwareMetricSample(unit: .rpm, source: .smc, availability: .unsupported,
                                        metadata: HardwareMetricMetadata(isFanless: true))
        }
        return HardwareMetricSample(unit: .rpm, source: .smc, availability: .temporarilyUnavailable)
    }

    /// Copy this snapshot forward with every measured or stale sample expired as
    /// of `now`. Stale samples are included so a cached value older than
    /// `cacheLifetime` is finally dropped instead of lingering forever.
    func expiring(at now: Date) -> HardwareMetricsSnapshot {
        var copy = self
        for (id, sample) in samples {
            let expired = sample.expiring(at: now)
            if expired != sample { copy.samples[id] = expired }
        }
        if let memoryPressure, !memoryPressure.isFresh(at: now) {
            copy.memoryPressure = nil
        }
        if let frequency = cpuFrequency {
            let age = now.timeIntervalSince(frequency.sampledAt)
            if age < -HardwareMetricSample.freshRange.upperBound || age > HardwareMetricSample.freshRange.upperBound {
                copy.cpuFrequency = nil
            }
        }
        return copy
    }

    static func unit(for id: HardwareMetricID) -> HardwareMetricUnit {
        switch id {
        case .cpuUsage, .gpuUsage, .memoryUsage: .percent
        case .memoryPressure: .none
        case .cpuTemperature, .gpuTemperature, .batteryTemperature: .celsius
        case .fanRPM: .rpm
        case .networkDownload, .networkUpload, .diskRead, .diskWrite: .bytesPerSecond
        case .volume, .wifiSignal, .batteryLevel: .percent
        }
    }
}

/// Metrics a consumer can ask for; CPU/GPU usage and SMC-backed sensors have
/// different cadence and cost, so demand is expressed per metric family.
enum HardwareMetricFamily: Hashable, Sendable, CaseIterable {
    case usage
    case temperature
    case fan
    case network
    case disk

    static func requested(from ids: Set<HardwareMetricID>) -> Set<HardwareMetricFamily> {
        var result: Set<HardwareMetricFamily> = []
        for id in ids {
            switch id {
            case .cpuUsage, .gpuUsage, .memoryUsage, .memoryPressure: result.insert(.usage)
            case .cpuTemperature, .gpuTemperature, .batteryTemperature: result.insert(.temperature)
            case .fanRPM: result.insert(.fan)
            case .networkDownload, .networkUpload: result.insert(.network)
            case .diskRead, .diskWrite: result.insert(.disk)
            case .volume, .wifiSignal, .batteryLevel: break
            }
        }
        return result
    }
}