import Foundation

enum UpdateDelivery: Equatable, Sendable {
    case direct
    case systemManaged
}

struct UpdateControlState: Equatable, Sendable {
    var delivery: UpdateDelivery
    var canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool

    static let systemManaged = UpdateControlState(
        delivery: .systemManaged,
        canCheckForUpdates: false,
        automaticallyChecksForUpdates: false
    )
}

struct PrivilegedHelperPresentation: Equatable, Sendable {
    var availability: CapabilityAvailability
    var isEnabled: Bool
    var requiresApproval: Bool
    var isReady: Bool
    var didFailLastOperation: Bool
    var lastErrorMessage: String?

    static let unsupported = PrivilegedHelperPresentation(
        availability: .unsupported(reason: "distribution.privileged-helper"),
        isEnabled: false,
        requiresApproval: false,
        isReady: false,
        didFailLastOperation: false,
        lastErrorMessage: nil
    )

    var isAvailable: Bool {
        availability == .available
    }
}

struct PlatformCapabilityRecord: Equatable, Sendable {
    let capability: String
    let availability: CapabilityAvailability
    let reason: String?

    static func unsupported(_ capability: String, reason: String) -> Self {
        Self(capability: capability, availability: .unsupported(reason: reason), reason: reason)
    }
}

enum PlatformCapabilities {
    static let direct: [PlatformCapabilityRecord] = []

    /// Stable identifiers only. Localization belongs to the UI layer and must
    /// not consume an English diagnostic string from the platform composition.
    static let appStore: [PlatformCapabilityRecord] = [
        PlatformCapabilityRecord(
            capability: "updates",
            availability: .available,
            reason: "distribution.system-managed-updates"
        ),
        .unsupported("ddc", reason: "distribution.private-ddc"),
        .unsupported("bluetooth.apple-listening-mode", reason: "distribution.private-hal"),
        .unsupported("bluetooth.radio-power", reason: "distribution.private-bluetooth"),
        .unsupported("power.privileged-helper", reason: "distribution.privileged-helper"),
        .unsupported("power.private-readers", reason: "distribution.private-power"),
        .unsupported("wifi.internet-sharing", reason: "distribution.undocumented-detector"),
        PlatformCapabilityRecord(
            capability: "mobile-battery.helper",
            availability: .notVerified,
            reason: "distribution.helper-not-packaged"
        ),
        PlatformCapabilityRecord(
            capability: "bluetooth.huawei-listening-mode",
            availability: .notVerified,
            reason: "distribution.public-vendor-transport"
        ),
        PlatformCapabilityRecord(
            capability: "bluetooth.public-readers",
            availability: .notVerified,
            reason: "distribution.public-readers-sandbox-unverified"
        )
    ]
}
