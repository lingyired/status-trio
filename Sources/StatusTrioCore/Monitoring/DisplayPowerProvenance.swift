import Foundation
import IOKit
import CoreGraphics

/// Whether a displayed power branch is a sensor reading or a derived estimate.
/// The distinction is part of the data model, not a presentation-only hint, so a
/// residual that depends on an estimate can be marked as estimated too.
enum PowerMeasurementProvenance: String, Equatable, Sendable {
    case measured
    case estimated
}

struct DisplayPowerSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date
    let provenance: PowerMeasurementProvenance
    /// `PDBR`, `PBwo`, `PBLR`, or `AppleARMBacklight`.
    let source: String
    /// Only set for the backlight-current estimate. It is an assumption, not a
    /// measured rail voltage, and the UI/help text must say so.
    let assumedVoltage: Double?

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...90).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

/// A source of display-backlight power estimates. The live implementation reads
/// `AppleARMBacklight`; tests inject a fake so no IORegistry is required.
protocol BacklightPowerEstimating: Sendable {
    func estimate(at date: Date) -> DisplayPowerSample?
    func reset()
}

/// Estimates built-in backlight power from the backlight current and the
/// display's calibration constant, following macpow's method.
///
/// `BrightnessMicroAmps` is the current fraction of the panel's maximum; the
/// calibration value is a 16.16 fixed-point maximum current. The resulting
/// current is multiplied by an explicit effective rail voltage. macOS exposes
/// neither the LED voltage nor a power reading, so the voltage stays a named
/// assumption and the result is always marked `estimated`.
///
/// There is deliberately no brightness-only fallback: when the current or the
/// calibration constant is missing, this returns nil instead of inventing watts.
final class AppleARMBacklightPowerEstimator: BacklightPowerEstimating, @unchecked Sendable {
    static let shared = AppleARMBacklightPowerEstimator()

    private let panelIsOn: @Sendable () -> Bool

    init(panelIsOn: @escaping @Sendable () -> Bool = { AppleARMBacklightPowerEstimator.builtInPanelIsOn() }) {
        self.panelIsOn = panelIsOn
    }

    /// Effective backlight rail voltage used for an XDR estimate. macpow's
    /// generic 6 V assumption underestimates Apple Silicon XDR panels by
    /// roughly 8×: on Mac15,9 the calibration-derived 3.199 A and the measured
    /// 10.69 W PDBR imply ≈3.34 V. It is still an assumption, never presented
    /// as a measured voltage.
    static let xdrAssumedVoltage: Double = 3.34
    /// SDR panels (including MacBook Air) use macpow's original 6 V model; it
    /// was designed for this class and there is no XDR HDR current scaling.
    static let sdrAssumedVoltage: Double = 6.0
    /// A branch below this is not drawn; it is a UI visibility threshold, not a
    /// sensor validity threshold.
    static let minimumVisibleWatts: Double = 0.05
    static let maximumPlausibleWatts: Double = 60.0
    static let discoveryRetryInterval: TimeInterval = 60

    private let lock = NSLock()
    private var service: io_service_t = 0
    private var calibrationFixedPoint: Double?
    private var retryAfter: Date = .distantPast

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    func reset() {
        lock.lock()
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
        calibrationFixedPoint = nil
        retryAfter = .distantPast
        lock.unlock()
    }

    func estimate(at date: Date) -> DisplayPowerSample? {
        // AppleARMBacklight keeps the last BrightnessMicroAmps value after the
        // built-in panel goes offline (lid closed with an external display) or
        // sleeps, so the IORegistry reading alone would keep reporting a stale
        // backlight. The display branch is the built-in backlight only; when no
        // built-in panel is online and awake there is nothing to estimate.
        guard panelIsOn() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard date >= retryAfter else { return nil }
        guard let properties = propertiesLocked() else {
            retryAfter = date.addingTimeInterval(Self.discoveryRetryInterval)
            return nil
        }
        guard let current = Self.currentMicroAmps(from: properties),
              let calibration = calibrationLocked(from: properties),
              current.value > 0, current.max > 0, calibration > 0 else {
            return nil
        }
        let profile = Self.panelProfile(maxNits: Self.maxNits(from: properties))
        let voltage = Self.assumedVoltage(for: profile)
        guard let watts = Self.estimatedWatts(currentMicroAmps: current.value,
                                              maximumMicroAmps: current.max,
                                              calibrationFixedPoint: calibration,
                                              profile: profile) else {
            return nil
        }
        guard (Self.minimumVisibleWatts...Self.maximumPlausibleWatts).contains(watts) else {
            return nil
        }
        return DisplayPowerSample(watts: watts, readAt: date, provenance: .estimated,
                                  source: "AppleARMBacklight",
                                  assumedVoltage: voltage)
    }

    private func propertiesLocked() -> [String: Any]? {
        if service == 0 {
            service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                 IOServiceMatching("AppleARMBacklight"))
            guard service != 0 else { return nil }
        }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            // A stale handle after sleep/topology change: drop it and retry on
            // the next demand instead of holding a dead service forever.
            if service != 0 { IOObjectRelease(service); service = 0 }
            return nil
        }
        return properties
    }

    private func calibrationLocked(from properties: [String: Any]) -> Double? {
        if let calibrationFixedPoint { return calibrationFixedPoint }
        guard let parameters = properties["backlight-calibration-parameters"] as? [String: Any],
              let value = Self.number(parameters["current-for-max-backlight"]),
              value.isFinite, (1_000...2_000_000).contains(value) else {
            return nil
        }
        // 16.16 fixed point: 904383 / 65536 = 13.799 A maximum backlight
        // current on Mac15,9, matching BrightnessMicroAmps max 13799 mA.
        calibrationFixedPoint = value
        return value
    }

    static func currentMicroAmps(from properties: [String: Any]) -> (value: Double, max: Double)? {
        guard let display = properties["IODisplayParameters"] as? [String: Any],
              let current = display["BrightnessMicroAmps"] else { return nil }
        let value: Double?
        let maximum: Double?
        if let dictionary = current as? [String: Any] {
            value = number(dictionary["value"])
            maximum = number(dictionary["max"])
        } else {
            value = number(current)
            maximum = nil
        }
        guard let value, let maximum, value.isFinite, maximum.isFinite else { return nil }
        return (value, maximum)
    }

    enum PanelProfile: String, Equatable, Sendable {
        case xdr
        case sdr
    }

    static func panelProfile(maxNits: Double?) -> PanelProfile {
        (maxNits ?? 0) >= 1_000 ? .xdr : .sdr
    }

    static func assumedVoltage(for profile: PanelProfile) -> Double {
        profile == .xdr ? xdrAssumedVoltage : sdrAssumedVoltage
    }

    /// `BrightnessMilliNits.max` is the panel's peak (HDR) nits. It separates
    /// XDR panels (where BrightnessMicroAmps' max is the HDR peak current) from
    /// SDR Air-style panels (where macpow's 6 V model applies).
    static func maxNits(from properties: [String: Any]) -> Double? {
        guard let display = properties["IODisplayParameters"] as? [String: Any],
              let nits = display["BrightnessMilliNits"] as? [String: Any],
              let maximum = number(nits["max"]), maximum.isFinite else { return nil }
        return maximum / 1000
    }

    static func estimatedWatts(currentMicroAmps value: Double, maximumMicroAmps maximum: Double,
                               calibrationFixedPoint: Double,
                               profile: PanelProfile = .xdr,
                               assumedVoltage: Double? = nil) -> Double? {
        guard value.isFinite, maximum.isFinite, calibrationFixedPoint.isFinite,
              value > 0, maximum > 0, calibrationFixedPoint > 0 else { return nil }
        let fraction = min(max(value / maximum, 0), 1)
        // XDR calibration is 16.16 fixed-point amps; SDR keeps macpow's
        // microamp/milliamp interpretation. Power uses the named profile voltage.
        let maxAmps: Double
        switch profile {
        case .xdr: maxAmps = calibrationFixedPoint / 65_536
        case .sdr: maxAmps = calibrationFixedPoint / 1_000_000
        }
        let voltage = assumedVoltage ?? Self.assumedVoltage(for: profile)
        let watts = fraction * maxAmps * voltage
        guard watts.isFinite else { return nil }
        return watts
    }

    /// True when an online, awake built-in display exists. If CoreGraphics
    /// cannot answer, do not suppress a potentially valid estimate.
    static func builtInPanelIsOn() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return true
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return true
        }
        return panelIsOn(displays: Array(displays.prefix(Int(count))),
                         isBuiltIn: { CGDisplayIsBuiltin($0) != 0 },
                         isAsleep: { CGDisplayIsAsleep($0) != 0 })
    }

    /// Pure display-topology decision, separated from CoreGraphics so the
    /// lid-closed/external-only and display-asleep cases are unit-testable.
    static func panelIsOn(displays: [CGDirectDisplayID],
                          isBuiltIn: (CGDirectDisplayID) -> Bool,
                          isAsleep: (CGDirectDisplayID) -> Bool) -> Bool {
        guard let builtIn = displays.first(where: isBuiltIn) else { return false }
        return !isAsleep(builtIn)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
