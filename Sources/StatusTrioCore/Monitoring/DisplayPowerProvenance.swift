import Foundation
import IOKit

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
/// calibration value is the maximum current in milliamps. macpow multiplies the
/// resulting current by an assumed 6 V LED-string voltage. That voltage is not
/// exposed by macOS, so it stays a named assumption and the result is always
/// marked `estimated`.
///
/// There is deliberately no brightness-only fallback: when the current or the
/// calibration constant is missing, this returns nil instead of inventing watts.
final class AppleARMBacklightPowerEstimator: BacklightPowerEstimating, @unchecked Sendable {
    static let shared = AppleARMBacklightPowerEstimator()

    /// macpow's documented assumption. Not a measurement.
    static let assumedVoltage: Double = 6.0
    /// A branch below this is not drawn; it is a UI visibility threshold, not a
    /// sensor validity threshold.
    static let minimumVisibleWatts: Double = 0.05
    static let maximumPlausibleWatts: Double = 60.0
    static let discoveryRetryInterval: TimeInterval = 60

    private let lock = NSLock()
    private var service: io_service_t = 0
    private var calibrationMicroAmps: Double?
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
        calibrationMicroAmps = nil
        retryAfter = .distantPast
        lock.unlock()
    }

    func estimate(at date: Date) -> DisplayPowerSample? {
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
        guard let watts = Self.estimatedWatts(currentMicroAmps: current.value,
                                              maximumMicroAmps: current.max,
                                              calibrationMicroAmps: calibration) else {
            return nil
        }
        guard (Self.minimumVisibleWatts...Self.maximumPlausibleWatts).contains(watts) else {
            return nil
        }
        return DisplayPowerSample(watts: watts, readAt: date, provenance: .estimated,
                                  source: "AppleARMBacklight",
                                  assumedVoltage: Self.assumedVoltage)
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
        if let calibrationMicroAmps { return calibrationMicroAmps }
        guard let parameters = properties["backlight-calibration-parameters"] as? [String: Any],
              let value = Self.number(parameters["current-for-max-backlight"]),
              value.isFinite, (1_000...2_000_000).contains(value) else {
            return nil
        }
        // The key is in microamps (904383 on Mac15,9 = 904.383 mA for the
        // maximum backlight), matching BrightnessMicroAmps' scale.
        calibrationMicroAmps = value
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

    static func estimatedWatts(currentMicroAmps value: Double, maximumMicroAmps maximum: Double,
                               calibrationMicroAmps: Double,
                               assumedVoltage: Double = AppleARMBacklightPowerEstimator.assumedVoltage) -> Double? {
        guard value.isFinite, maximum.isFinite, calibrationMicroAmps.isFinite,
              value > 0, maximum > 0, calibrationMicroAmps > 0 else { return nil }
        let fraction = min(max(value / maximum, 0), 1)
        // microamps -> amps; the 6 V string voltage is the named assumption.
        let watts = fraction * calibrationMicroAmps / 1_000_000 * assumedVoltage
        guard watts.isFinite else { return nil }
        return watts
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
