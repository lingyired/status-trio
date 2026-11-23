import Foundation

/// Stable platform capability identifiers shared by UI, actions, and
/// composition. The raw values match `PlatformCapabilityRecord.capability`.
enum DistributionCapabilityID: String, CaseIterable, Sendable {
    case updates
    case ddc
    case appleListeningMode = "bluetooth.apple-listening-mode"
    case bluetoothBatteryLevels = "bluetooth.battery-levels"
    case bluetoothRadioPower = "bluetooth.radio-power"
    case privilegedHelper = "power.privileged-helper"
    case privatePowerReaders = "power.private-readers"
    case internetSharing = "wifi.internet-sharing"
    case mobileBatteryHelper = "mobile-battery.helper"
    case huaweiListeningMode = "bluetooth.huawei-listening-mode"
    case publicBluetoothReaders = "bluetooth.public-readers"
    case chargeToFullNow = "power.charge-to-full-now"
    case externalVolume = "audio.external-volume"
    case applicationEnergy = "power.application-energy"
    // V2 additions (design §6.1, decisions D3/D4).
    case sensorsSMC = "sensors.smc"
    case sensorsCPUFrequency = "sensors.cpu-frequency"
    case sleepControl = "power.sleep-control"
    case highPowerMode = "power.high-power-mode"
    case lowPowerMode = "power.low-power-mode"
    case externalBrightness = "display.external-brightness"
}

/// The distribution policy exposed to shared UI and action code.
///
/// Store records are merged over the canonical Store contract, so an omitted or
/// partial composition cannot silently permit a private implementation. Direct
/// has an empty default contract because its existing runtime gates remain
/// authoritative. A `notVerified` provider has no evidence that its real
/// operation works in this distribution, so it is blocked rather than allowed to
/// reach a hardware write behind a clickable control.
struct DistributionCapabilityPolicy: Equatable, Sendable {
    let channel: DistributionChannel
    private let records: [String: PlatformCapabilityRecord]

    init(
        channel: DistributionChannel,
        records: [PlatformCapabilityRecord]? = nil
    ) {
        self.channel = channel
        var indexed: [String: PlatformCapabilityRecord] = [:]
        for record in Self.defaultRecords(for: channel) {
            indexed[record.capability] = record
        }
        for record in records ?? [] {
            indexed[record.capability] = record
        }
        self.records = indexed
    }

    /// Safe fallback for previews, tests, synchronizers, and any composition
    /// seam that does not pass records explicitly. The compiled channel chooses
    /// its own capability contract here; Store never falls back to an empty set.
    static var runtimeDefault: DistributionCapabilityPolicy {
        runtimeDefault(for: .current)
    }

    static func runtimeDefault(
        for channel: DistributionChannel
    ) -> DistributionCapabilityPolicy {
        DistributionCapabilityPolicy(channel: channel)
    }

    func availability(of capability: DistributionCapabilityID) -> CapabilityAvailability? {
        records[capability.rawValue]?.availability
    }

    /// Returns true only when this build's capability contract must prevent the
    /// control or action. `notVerified` is a composition-time block: runtime
    /// permission cannot make an unverified implementation safe to write through.
    /// A Store lookup with no record is a composition error and stays blocked;
    /// Direct keeps its runtime contract.
    func blocksControl(_ capability: DistributionCapabilityID) -> Bool {
        guard let availability = availability(of: capability) else {
            return channel == .appStore
        }
        switch availability {
        case .unsupported, .notVerified,
             .helperNotInstalled, .helperUpdateRequired, .helperMissingAuthorization:
            return true
        case .nativeAvailable, .helperProvided, .permissionDenied, .temporarilyUnavailable:
            return false
        }
    }

    func unavailableReasonKey(
        for capability: DistributionCapabilityID
    ) -> LocalizationKey? {
        guard let availability = availability(of: capability) else {
            return channel == .appStore ? .capabilityUnavailableDistribution : nil
        }
        switch availability {
        case .unsupported:
            return .capabilityUnavailableDistribution
        case .helperNotInstalled, .helperUpdateRequired, .helperMissingAuthorization:
            return .capabilityUnavailableDistribution
        case .notVerified:
            return .capabilityNotVerified
        case .nativeAvailable, .helperProvided, .permissionDenied, .temporarilyUnavailable:
            return nil
        }
    }

    private static func defaultRecords(
        for channel: DistributionChannel
    ) -> [PlatformCapabilityRecord] {
        switch channel {
        case .direct:
            PlatformCapabilities.direct
        case .appStore:
            PlatformCapabilities.appStore
        }
    }
}

extension DistributionChannel {
    /// Product identity for the compiled channel. Runtime receipt or bundle
    /// metadata must never choose this label.
    var displayIdentity: String {
        switch self {
        case .direct:
            "GitHub Direct"
        case .appStore:
            "Mac App Store"
        }
    }
}
