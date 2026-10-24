import Foundation

/// Stable platform capability identifiers shared by UI, actions, and
/// composition. The raw values match `PlatformCapabilityRecord.capability`.
enum DistributionCapabilityID: String, CaseIterable, Sendable {
    case updates
    case ddc
    case appleListeningMode = "bluetooth.apple-listening-mode"
    case bluetoothRadioPower = "bluetooth.radio-power"
    case privilegedHelper = "power.privileged-helper"
    case privatePowerReaders = "power.private-readers"
    case internetSharing = "wifi.internet-sharing"
    case mobileBatteryHelper = "mobile-battery.helper"
    case huaweiListeningMode = "bluetooth.huawei-listening-mode"
    case publicBluetoothReaders = "bluetooth.public-readers"
}

/// The distribution policy exposed to shared UI and action code.
///
/// Store records are merged over the canonical Store contract, so an omitted or
/// partial composition cannot silently permit a private implementation. Direct
/// has an empty default contract because its existing runtime gates remain
/// authoritative. Public providers that are still `notVerified` are not
/// presented as `available`; they are also not globally disabled because
/// permission and runtime state remain the authoritative gates for them.
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
    /// control or action. Public `notVerified` capabilities stay runtime-driven;
    /// the mobile battery helper is the exception because its implementation is
    /// known to be absent from the Store bundle. A Store lookup with no record is
    /// a composition error and stays blocked; Direct keeps its runtime contract.
    func blocksControl(_ capability: DistributionCapabilityID) -> Bool {
        guard let availability = availability(of: capability) else {
            return channel == .appStore
        }
        switch availability {
        case .unsupported:
            return true
        case .notVerified:
            return capability.requiresAvailableImplementation
        case .available, .permissionRequired, .temporarilyUnavailable:
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
        case .notVerified:
            return .capabilityNotVerified
        case .available, .permissionRequired, .temporarilyUnavailable:
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

private extension DistributionCapabilityID {
    var requiresAvailableImplementation: Bool {
        self == .mobileBatteryHelper
    }
}
