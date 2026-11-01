import Foundation
import IOKit
import IOKit.ps

struct BatteryPowerSample: Equatable, Sendable {
    let volts: Double
    let amps: Double
    let updatedAt: Date
    var watts: Double { volts * amps }

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return (-5...90).contains(age) && (notBefore.map { updatedAt >= $0 } ?? true)
    }
}

struct BatteryDetails: Equatable, Sendable {
    enum PowerAvailability: Equatable, Sendable {
        case available
        /// The registry still reports the previous power source or sample.
        case collecting
        /// This Mac does not expose usable battery power telemetry.
        case unavailable
    }

    var adapterWatts: Int?
    var remainingMinutes: Int?
    var cycleCount: Int?
    var power: BatteryPowerSample?
    var systemPower: SystemPowerSample?
    var inputPower: SystemPowerSample?
    var breakdown: BatteryPowerBreakdown?
    var powerAvailability: PowerAvailability

    init(adapterWatts: Int? = nil, remainingMinutes: Int? = nil, cycleCount: Int? = nil,
         power: BatteryPowerSample? = nil, powerAvailability: PowerAvailability = .unavailable,
         systemPower: SystemPowerSample? = nil, inputPower: SystemPowerSample? = nil,
         breakdown: BatteryPowerBreakdown? = nil) {
        self.adapterWatts = adapterWatts
        self.remainingMinutes = remainingMinutes
        self.cycleCount = cycleCount
        self.power = power
        self.systemPower = systemPower
        self.inputPower = inputPower
        self.breakdown = breakdown
        self.powerAvailability = powerAvailability
    }
}

/// A small immutable context, so a percentage update does not restart detail collection.
struct BatteryPowerState: Hashable, Sendable {
    let isPresent: Bool
    let isConnected: Bool
    let isCharging: Bool

    init(_ battery: BatteryStatus) {
        isPresent = battery.isPresent
        isConnected = battery.isConnectedToPower
        isCharging = battery.isCharging
    }
}

struct BatteryDetailsReader: Sendable {
    func read(state: BatteryPowerState, notBefore: Date?, options: BatteryPowerDisplayOptions = .default,
              previousBreakdown: BatteryPowerBreakdown? = nil,
              systemPower sharedSystemPower: SystemPowerSample? = nil,
              usesSharedSystemPower: Bool = false) -> BatteryDetails {
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        var registry: [String: Any] = [:]
        if service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                registry = properties?.takeRetainedValue() as? [String: Any] ?? [:]
            }
        }
        // A caller that already owns a shared sample must not open a second
        // system-power connection here. Only readers without one (previews,
        // standalone tests) fall back to their own read.
        let readsOwnSystemPower = !usesSharedSystemPower
            && Self.readsSystemPower(for: state)
            && options.showsSystem
        let sensors = SystemPowerReader().readSensors(
            system: readsOwnSystemPower,
            input: state.isPresent && state.isConnected && (options.showsInput || options.showsBreakdown),
            // Read the live battery sensor whenever the page can show charging
            // power. macOS can keep the IOPS/registry charging flags false for
            // tens of seconds during a short charge pulse, and a stale flag
            // must not hide real current that the hardware is already moving.
            // The breakdown residual also needs it even when the branch is hidden.
            battery: state.isPresent && (state.isConnected || options.showsBreakdown)
                && (options.showsCharging || options.showsBreakdown),
            breakdown: Self.readsBreakdown(for: state) && options.showsBreakdown
        )
        let now = Date()
        var breakdown: BatteryPowerBreakdown?
        if options.showsBreakdown, state.isPresent {
            let resolved = BatteryPowerBreakdown.resolve(
                adapterInput: sensors.input,
                charging: sensors.battery.map { max(0, $0.watts) },
                discharge: sensors.battery.map { max(0, -$0.watts) },
                display: sensors.display,
                usb: USBOutputReader.parse(registry: registry, now: now),
                now: now
            )
            // One overall refresh can catch the rails mid-update and show a
            // transient negative residual. Hold the last coherent split for a
            // single refresh instead of flickering back to the legacy diagram;
            // never extend it beyond that, and never publish a stale residual
            // as a fresh reading.
            if let resolved {
                breakdown = resolved
            } else if let previous = previousBreakdown,
                      now.timeIntervalSince(previous.readAt) <= Self.breakdownHoldSeconds {
                breakdown = previous
            }
        }
        var result = Self.parse(
            registry: registry,
            adapterWatts: adapter?[kIOPSPowerAdapterWattsKey] as? Int,
            remainingSeconds: IOPSGetTimeRemainingEstimate(),
            state: state,
            now: now,
            notBefore: notBefore,
            systemPower: sharedSystemPower ?? sensors.system,
            inputPower: sensors.input, batteryPower: sensors.battery,
            breakdown: breakdown
        )
        if !options.showsInput { result.inputPower = nil }
        if state.isConnected && !options.showsCharging { result.power = nil }
        return result
    }

    /// Whether this page has a meaningful whole-machine power row. A Mac with
    /// no battery has no discharge or charging row to show, so its only power
    /// reading is the system total; a battery Mac uses it on external power.
    static func readsSystemPower(for state: BatteryPowerState) -> Bool {
        !state.isPresent || state.isConnected
    }

    /// The split covers both directions: an adapter feeding the Mac, or the
    /// pack discharging into it when the charger is idle or absent.
    static func readsBreakdown(for state: BatteryPowerState) -> Bool {
        state.isPresent
    }

    /// How long a coherent split may stand in while a rail update crosses a
    /// refresh boundary. One periodic tick, not a general cache.
    static let breakdownHoldSeconds: TimeInterval = 6

    /// IORegistry is public, but these AppleSmartBattery properties are best-effort,
    /// not a stable cross-model API. Never combine values from nested telemetry sources.
    static func parse(
        registry: [String: Any], adapterWatts: Int?, remainingSeconds: Double,
        state: BatteryPowerState, now: Date, notBefore: Date? = nil,
        systemPower: SystemPowerSample? = nil, inputPower: SystemPowerSample? = nil,
        batteryPower: BatteryPowerSample? = nil, breakdown: BatteryPowerBreakdown? = nil
    ) -> BatteryDetails {
        guard state.isPresent else {
            // No battery: the system total is the whole page. A missing or stale
            // sample is reported as collecting, never as 0 W.
            guard let systemPower else {
                return BatteryDetails(powerAvailability: .collecting)
            }
            guard systemPower.isFresh(at: now, notBefore: notBefore) else {
                return BatteryDetails(powerAvailability: .collecting)
            }
            return BatteryDetails(powerAvailability: .available, systemPower: systemPower)
        }
        var result = BatteryDetails(
            adapterWatts: state.isConnected ? adapterWatts.flatMap { $0 > 0 ? $0 : nil } : nil,
            remainingMinutes: !state.isConnected && remainingSeconds.isFinite && remainingSeconds >= 60
                && remainingSeconds < Double(Int.max) ? Int(remainingSeconds / 60) : nil,
            cycleCount: (registry["CycleCount"] as? Int).flatMap { $0 >= 0 ? $0 : nil },
            systemPower: state.isConnected ? systemPower : nil,
            breakdown: state.isConnected ? breakdown : nil
        )
        let registryMatches = (registry["ExternalConnected"] as? Bool) == state.isConnected
            && (registry["IsCharging"] as? Bool) == state.isCharging
        // A positive SMC battery sample is hardware truth. Charge-limit pulses
        // can deliver real current while both IOPS and the registry still say
        // "not charging", so do not gate this sample on those lagging flags.
        if state.isConnected, let batteryPower, batteryPower.watts > 0,
           batteryPower.isFresh(at: now, notBefore: notBefore) {
            result.power = batteryPower
            result.powerAvailability = .available
        }
        if state.isConnected && registryMatches {
            if let inputPower, inputPower.isFresh(at: now, notBefore: notBefore) {
                result.inputPower = inputPower
            } else if let telemetry = registry["PowerTelemetryData"] as? [String: Any],
                      let raw = telemetry["SystemPowerIn"] as? NSNumber,
                      CFGetTypeID(raw) != CFBooleanGetTypeID(),
                      raw.doubleValue.isFinite, (0...1_000_000).contains(raw.doubleValue),
                      let updated = registry["UpdateTime"] as? NSNumber {
                let sample = SystemPowerSample(watts: raw.doubleValue / 1_000,
                    readAt: Date(timeIntervalSince1970: updated.doubleValue))
                if sample.isFresh(at: now, notBefore: notBefore) { result.inputPower = sample }
            }
            if state.isCharging, let batteryPower, batteryPower.watts > 0,
               batteryPower.isFresh(at: now, notBefore: notBefore) {
                result.power = batteryPower
                result.powerAvailability = .available
                return result
            }
        }
        // A connected Mac can report useful whole-system power even when the
        // battery current is zero or negative because the pack is no longer
        // charging (common on Intel Macs at the charge limit or with an
        // undersized adapter). Treat the system sample as the authoritative
        // connected-power reading and keep the battery sample optional.
        if state.isConnected, let systemPower {
            result.powerAvailability = .available
            result.systemPower = systemPower
        }

        guard let millivolts = (registry["Voltage"] as? NSNumber)?.doubleValue,
              let current = registry["Amperage"] as? NSNumber,
              CFGetTypeID(current) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: current.objCType)),
              let timestamp = (registry["UpdateTime"] as? NSNumber)?.doubleValue,
              millivolts.isFinite, timestamp.isFinite,
              (1_000...30_000).contains(millivolts)
        else {
            result.powerAvailability = state.isConnected
                && (systemPower != nil || result.power != nil)
                ? .available
                : .unavailable
            return result
        }
        // From here a usable sample may exist; failures mean it is not in yet.
        result.powerAvailability = state.isConnected
            && (systemPower != nil || result.power != nil)
            ? .available
            : .collecting
        // A registry that still describes the previous power source is a
        // transition, not a machine that cannot report battery power.
        guard let connected = registry["ExternalConnected"] as? Bool,
              let charging = registry["IsCharging"] as? Bool,
              connected == state.isConnected, charging == state.isCharging
        else { return collecting(&result) }
        // Some IORegistry producers wrap negative current in an unsigned 64-bit
        // NSNumber. Interpret the integer bit pattern, then bound the result.
        let milliamps = Double(current.int64Value)
        guard abs(milliamps) <= 30_000,
              // Zero while unplugged is a power transition, not evidence of zero consumption.
              // Zero while connected means the battery is idle, which is a real reading.
              milliamps != 0 || connected
        else { return collecting(&result) }
        guard
              milliamps > 0 ? (connected && charging) : !charging
        else {
            result.powerAvailability = state.isConnected
                && (systemPower != nil || result.power != nil)
                ? .available
                : .unavailable
            return result
        }
        let updatedAt = Date(timeIntervalSince1970: timestamp)
        let sample = BatteryPowerSample(volts: millivolts / 1_000, amps: milliamps / 1_000, updatedAt: updatedAt)
        // Stale or pre-transition samples are simply not in yet.
        guard sample.isFresh(at: now, notBefore: notBefore) else { return collecting(&result) }
        if state.isConnected {
            if state.isCharging, sample.watts > 0 { result.power = sample }
            result.powerAvailability = systemPower != nil || result.power != nil ? .available : .collecting
            return result
        }
        result.power = sample
        result.powerAvailability = .available
        return result
    }

    private static func collecting(_ details: inout BatteryDetails) -> BatteryDetails {
        details.powerAvailability = .collecting
        return details
    }
}
