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

    var designCapacityMAh: Int?
    var maximumCapacityMAh: Int?
    /// Estimated from measured capacities, not the value macOS shows under
    /// Battery Health. The UI must label it as an estimate.
    var healthPercent: Double?
    var temperatureCelsius: Double?
    var chargeTime: ChargeTimeState

    init(
        designCapacityMAh: Int? = nil,
        maximumCapacityMAh: Int? = nil,
        healthPercent: Double? = nil,
        temperatureCelsius: Double? = nil,
        chargeTime: ChargeTimeState = .unavailable
    ) {
        self.designCapacityMAh = designCapacityMAh
        self.maximumCapacityMAh = maximumCapacityMAh
        self.healthPercent = healthPercent
        self.temperatureCelsius = temperatureCelsius
        self.chargeTime = chargeTime
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
    /// value is never divided by an unrelated top-level value, and the
    /// percentage-valued `MaxCapacity` key is never read as milliamp hours.
    static func parseCapacity(registry: [String: Any]) -> Capacity {
        if let batteryData = registry["BatteryData"] as? [String: Any],
           let capacity = capacities(in: batteryData) {
            return capacity
        }
        return capacities(in: registry) ?? Capacity()
    }

    /// Maximum-capacity keys are tried in measured-then-reported order. The
    /// design capacity must come from the same dictionary as the maximum.
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

    /// A capacity pair is only credible inside these bounds. An implausible
    /// ratio leaves health unknown while the raw capacities stay visible.
    static func healthPercent(maximumMAh: Int?, designMAh: Int?) -> Double? {
        guard let maximumMAh, let designMAh, designMAh > 0, maximumMAh > 0 else { return nil }
        let percent = Double(maximumMAh) / Double(designMAh) * 100
        guard percent.isFinite, (1...150).contains(percent) else { return nil }
        return percent
    }

    /// Battery capacities are whole milliamp hours. Booleans, fractional
    /// telemetry, and out-of-range values are rejected rather than truncated.
    static func milliampHours(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        // CFBoolean bridges to NSNumber with "c"/"B"; 0/1 mAh is never valid.
        guard type != "c", type != "B" else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw == raw.rounded() else { return nil }
        let capacity = Int(raw)
        guard (1...100_000).contains(capacity) else { return nil }
        return capacity
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
        if boolValue(description[kIOPSIsPresentKey]) == false { return .unavailable }
        let connected = (description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            || isConnectedToPower
        guard connected else { return .unavailable }
        if boolValue(description[kIOPSIsChargedKey]) == true { return .charged }
        let charging = boolValue(description[kIOPSIsChargingKey]) ?? isCharging ?? false
        guard charging else { return .paused }
        if let minutes = integerValue(description[kIOPSTimeToFullChargeKey]), minutes > 0 {
            return .estimated(minutes: minutes)
        }
        return .calculating
    }

    static func boolValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        return number.boolValue
    }

    static func integerValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw == raw.rounded() else { return nil }
        return Int(raw)
    }
}
