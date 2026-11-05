import Foundation

/// Stable identifier for a hardware metric, independent of any SMC key.
enum HardwareMetricID: Hashable, Sendable {
    case cpuUsage
    case gpuUsage
    case cpuTemperature
    case gpuTemperature
    case fanRPM(index: Int)
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
    case none
}

/// Where the sample came from, used for diagnostics and accessibility copy.
enum HardwareMetricSource: Equatable, Sendable {
    case mach
    case smc
    case ioAccelerator
    case powerIO
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
        guard availability == .measured else { return self }
        let age = now.timeIntervalSince(sampledAt)
        guard !Self.freshRange.contains(age) else { return self }
        var copy = self
        copy.availability = .stale
        if age > Self.cacheLifetime || age < -Self.cacheLifetime {
            copy.value = nil
        }
        return copy
    }
}

/// One refresh's aggregate snapshot. UI layers observe this, never a broad
/// panel snapshot, so a metric tick cannot re-render unrelated sections.
struct HardwareMetricsSnapshot: Equatable, Sendable {
    var samples: [HardwareMetricID: HardwareMetricSample] = [:]
    /// Fan controller count when known; `nil` until read, `0` on fanless Macs.
    var fanCount: Int?

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
    var cpuTemperature: HardwareMetricSample { self[.cpuTemperature] }
    var gpuTemperature: HardwareMetricSample { self[.gpuTemperature] }

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

    /// Copy this snapshot forward with every measured sample expired as of `now`.
    func expiring(at now: Date) -> HardwareMetricsSnapshot {
        var copy = self
        for (id, sample) in samples where sample.availability == .measured {
            copy.samples[id] = sample.expiring(at: now)
        }
        return copy
    }

    static func unit(for id: HardwareMetricID) -> HardwareMetricUnit {
        switch id {
        case .cpuUsage, .gpuUsage: .percent
        case .cpuTemperature, .gpuTemperature: .celsius
        case .fanRPM: .rpm
        }
    }
}

/// Metrics a consumer can ask for; CPU/GPU usage and SMC-backed sensors have
/// different cadence and cost, so demand is expressed per metric family.
enum HardwareMetricFamily: Hashable, Sendable, CaseIterable {
    case usage
    case temperature
    case fan

    static func requested(from ids: Set<HardwareMetricID>) -> Set<HardwareMetricFamily> {
        var result: Set<HardwareMetricFamily> = []
        for id in ids {
            switch id {
            case .cpuUsage, .gpuUsage: result.insert(.usage)
            case .cpuTemperature, .gpuTemperature: result.insert(.temperature)
            case .fanRPM: result.insert(.fan)
            }
        }
        return result
    }
}