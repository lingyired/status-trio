import Foundation
import IOKit.ps

/// Best-effort, read-only battery health telemetry taken from the same
/// on-demand snapshot the details page already reads. Every field is optional:
/// a missing or unverifiable value stays `nil` (or `.unavailable`) instead of
/// being filled in with a fabricated zero. No new permission, helper, daemon,
/// or sampling loop is involved.
struct BatteryHealthSnapshot: Equatable, Sendable {
    /// What the system says about charging completion. `unavailable` is used
    /// when the Mac is not on external power or has no internal battery.
    enum ChargeTimeState: Equatable, Sendable {
        /// IOPS published a positive minute estimate.
        case estimated(minutes: Int)
        /// The system is charging but has not published an estimate yet (-1).
        case calculating
        /// IOPS reports the battery as fully charged.
        case charged
        /// External power is connected but charging is paused or inactive
        /// (charge limit, optimized charging, thermal pause, held pulse).
        case paused
        /// Not connected, no battery, or no usable state.
        case unavailable
    }

    enum Condition: Equatable, Sendable {
        case normal
        case service
    }

    var designCapacityMAh: Int?
    var maximumCapacityMAh: Int?
    /// macOS's own Maximum Capacity percentage, read from
    /// `system_profiler`'s `sppower_battery_health_maximum_capacity` so the
    /// details row matches System Settings › Battery. Not the registry
    /// `MaxCapacity` counter, which can stay pinned at 100.
    var maximumCapacityPercent: Double?
    /// Estimated from measured capacities, not the value macOS shows under
    /// Battery Health. Kept as diagnostic/derived data, but never substituted
    /// for the system-reported Maximum Capacity (the two can disagree).
    var healthPercent: Double?
    var temperatureCelsius: Double?
    var chargeTime: ChargeTimeState
    /// `nil` means the system exposed no explicit condition evidence.
    var condition: Condition?

    init(
        designCapacityMAh: Int? = nil,
        maximumCapacityMAh: Int? = nil,
        maximumCapacityPercent: Double? = nil,
        healthPercent: Double? = nil,
        temperatureCelsius: Double? = nil,
        chargeTime: ChargeTimeState = .unavailable,
        condition: Condition? = nil
    ) {
        self.designCapacityMAh = designCapacityMAh
        self.maximumCapacityMAh = maximumCapacityMAh
        self.maximumCapacityPercent = maximumCapacityPercent
        self.healthPercent = healthPercent
        self.temperatureCelsius = temperatureCelsius
        self.chargeTime = chargeTime
        self.condition = condition
    }

    /// A health card is only worth showing when at least one capacity or
    /// temperature value exists. Cycle count alone keeps its plain detail row.
    var hasMetrics: Bool {
        designCapacityMAh != nil || maximumCapacityMAh != nil
            || healthPercent != nil || temperatureCelsius != nil
    }

    /// A charge estimate is informative even when no capacity telemetry is
    /// exposed, so it can justify the card on its own. Paused charging is not
    /// informative enough to open a card by itself.
    var hasDisplayableChargeTime: Bool {
        switch chargeTime {
        case .estimated, .calculating, .charged: return true
        case .paused, .unavailable: return false
        }
    }
}

/// Pure parsing for the health snapshot so each source and unit rule can be
/// tested without an IORegistry or SMC read.
enum BatteryHealthParser {
    struct Capacity: Equatable, Sendable {
        var designMAh: Int? = nil
        var maximumMAh: Int? = nil
        var healthPercent: Double? = nil
    }

    /// Capacities are paired inside one dictionary only. A nested telemetry
    /// value is never divided by an unrelated top-level value.
    static func parseCapacity(registry: [String: Any]) -> Capacity {
        if let batteryData = registry["BatteryData"] as? [String: Any],
           let capacity = capacities(in: batteryData) {
            return capacity
        }
        return capacities(in: registry) ?? Capacity()
    }

    /// Maximum-capacity keys are tried in measured-then-reported order. The
    /// design capacity must come from the same dictionary as the maximum.
    ///
    /// AppleSmartBattery's percentage-valued `MaxCapacity` is deliberately not
    /// read here. It is a relative counter that can stay pinned at 100 while
    /// the real battery health (macOS「最大容量」) has dropped to ~94%, so it is
    /// never a trustworthy display value. The macOS-consistent percentage is
    /// read from `system_profiler` instead (`maximumCapacityPercent(systemProfilerJSON:)`).
    private static func capacities(in values: [String: Any]) -> Capacity? {
        let design = milliampHours(values["DesignCapacity"])
        let maximum = ["AppleRawMaxCapacity", "FullChargeCapacity", "NominalChargeCapacity"]
            .compactMap { milliampHours(values[$0]) }
            .first
        guard design != nil || maximum != nil else { return nil }
        return Capacity(
            designMAh: design,
            maximumMAh: maximum,
            healthPercent: healthPercent(maximumMAh: maximum, designMAh: design)
        )
    }

    /// A missing health value or a zero failure bitmask does not prove the
    /// battery is healthy. Service evidence wins over a simultaneous Good value.
    static func condition(registry: [String: Any]) -> BatteryHealthSnapshot.Condition? {
        var sources = [registry]
        if let batteryData = registry["BatteryData"] as? [String: Any] {
            sources.append(batteryData)
        }
        let conditions = sources.flatMap { source in
            [source["BatteryHealth"] as? String, source["BatteryHealthCondition"] as? String]
                .compactMap { $0 }
        }
        if sources.contains(where: {
            (integerValue($0["PermanentFailureStatus"]) ?? 0) > 0
        }) || conditions.contains(where: { condition(named: $0) == .service }) {
            return .service
        }
        return conditions.contains { condition(named: $0) == .normal } ? .normal : nil
    }

    /// The raw health strings powerd publishes. Anything else stays unknown.
    /// system_profiler's JSON carries the same raw strings: its loctable maps
    /// Good to "Normal" and Fair, Poor and Check Battery to "Service
    /// Recommended" only for display (SPPowerReporter, macOS 27).
    static func condition(named value: String) -> BatteryHealthSnapshot.Condition? {
        if ["Fair", "Poor", "Check Battery"].contains(value) { return .service }
        return value == "Good" ? .normal : nil
    }

    /// `system_profiler SPPowerDataType -json` output. Apple Silicon Macs on
    /// recent macOS (measured: Mac18,1, macOS 27) no longer publish the
    /// condition in AppleSmartBattery or the public IOPS description; the
    /// private API that carries it needs an Apple entitlement.
    static func condition(systemProfilerJSON data: Data) -> BatteryHealthSnapshot.Condition? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        return items.lazy
            .compactMap { ($0["sppower_battery_health_info"] as? [String: Any])?["sppower_battery_health"] as? String }
            .first
            .flatMap(condition(named:))
    }

    /// The same `system_profiler SPPowerDataType -json` object carries macOS's
    /// own「最大容量」as `sppower_battery_health_maximum_capacity`, e.g. `"94%"`.
    /// That is the value shown in System Settings › Battery, so it is the only
    /// source the details row may present as Maximum Capacity. Anything that is
    /// not a plain `NN%` in `1...100` stays unknown instead of guessing.
    static func maximumCapacityPercent(systemProfilerJSON data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        return items.lazy
            .compactMap { ($0["sppower_battery_health_info"] as? [String: Any])?["sppower_battery_health_maximum_capacity"] as? String }
            .first
            .flatMap(percent(fromReported:))
    }

    /// Parses a reported `"94%"` (whitespace tolerated) into `94`. A bare
    /// number without `%`, or one outside a credible range, is rejected so a
    /// mislabelled field can never masquerade as a health percentage.
    static func percent(fromReported raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("%") else { return nil }
        let digits = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
        guard let value = Double(digits), value.isFinite, (1...100).contains(value) else { return nil }
        return value
    }

    /// A capacity pair is only credible inside these bounds. An implausible
    /// ratio leaves health unknown while the raw capacities stay visible.
    static func healthPercent(maximumMAh: Int?, designMAh: Int?) -> Double? {
        guard let maximumMAh, let designMAh, designMAh > 0, maximumMAh > 0 else { return nil }
        let percent = Double(maximumMAh) / Double(designMAh) * 100
        // Below ~20% a "capacity" is almost certainly a different field
        // wearing the same name; above 150% it is not the same battery.
        guard percent.isFinite, (20...150).contains(percent) else { return nil }
        return percent
    }

    /// Battery capacities are whole milliamp hours. Booleans, fractional
    /// telemetry, and out-of-range values are rejected rather than truncated.
    static func milliampHours(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        // Apple's shipped Mac battery packs all fall inside this range; smaller
        // values are percentages or counters, and the Smart Battery 0xffff
        // unknown sentinel (65,535) is rejected by the upper bound. Bound the
        // Double before converting so hostile NSNumber values cannot trap.
        guard raw.isFinite, raw == raw.rounded(), (1_000...20_000).contains(raw) else { return nil }
        return Int(exactly: raw)
    }

    /// Battery temperature in degrees Celsius from AppleSMC `TB0T`. The SMC
    /// type decides the encoding; unknown types and implausible values are
    /// unavailable rather than guessed. IORegistry `Temperature` is
    /// deliberately unused because its scale differs by model (1/10 vs
    /// 1/100 °C) and cannot be verified on every Mac.
    static func temperatureCelsius(smcType: UInt32, bytes: [UInt8]) -> Double? {
        let value: Double
        switch smcType {
        case 0x666c7420: // flt, little-endian host float
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            value = Double(Float(bitPattern: bits))
        case 0x73703738, 0x66706532: // sp78, fpe2 (big-endian fixed point)
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            value = smcType == 0x73703738
                ? Double(Int16(bitPattern: raw)) / 256
                : Double(raw) / 4
        default:
            return nil
        }
        guard value.isFinite, (-20...80).contains(value) else { return nil }
        return value
    }

    /// Time to full comes from the IOPS description, never from a linear
    /// extrapolation of the current charge power. Only the internal battery's
    /// own state is used; a system that reports charging without an estimate
    /// stays `.calculating` instead of showing 0 W or 0 min.
    static func parseChargeTime(
        description: [String: Any],
        isConnectedToPower: Bool,
        isCharging: Bool?
    ) -> BatteryHealthSnapshot.ChargeTimeState {
        // The description is the fresh source: the event-driven cached flag is
        // documented to trail a short charge pulse by tens of seconds. The AC
        // power-source check alone rules out a stale snapshot from the battery.
        guard boolValue(description[kIOPSIsPresentKey]) == true,
              isConnectedToPower,
              description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
              let charging = boolValue(description[kIOPSIsChargingKey]),
              let charged = boolValue(description[kIOPSIsChargedKey])
        else { return .unavailable }
        if charged { return charging ? .unavailable : .charged }
        guard charging else { return .paused }
        guard let minutes = integerValue(description[kIOPSTimeToFullChargeKey]) else { return .unavailable }
        if minutes == -1 || minutes == 0 { return .calculating }
        // Reject sentinels and implausible durations before formatting them.
        guard (1...10_080).contains(minutes) else { return .unavailable }
        return .estimated(minutes: minutes)
    }

    static func boolValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        switch number.doubleValue {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    static func integerValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }
}
