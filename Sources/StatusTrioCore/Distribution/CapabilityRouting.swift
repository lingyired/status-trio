import Foundation

/// Which provider tier serves a capability. The distribution channel only
/// decides which tiers are *selectable*; the tier itself reports the real
/// availability. See `docs/dual-distribution-v2-capability-model.md` §3.2.
enum CapabilityProviderTier: String, CaseIterable, Sendable {
    case native
    case externalHelper
    case unavailable
}

/// Source ownership of a capability, derived from source audit (the new
/// `direct-only-sources.txt`). Not a runtime guess.
///
/// `.unclassified` is the safe default: excluded from the Store build closure
/// and routed like `.directPrivate` until Phase 1 audit promotes it (design D5).
enum CapabilitySourceClass: String, Sendable {
    case sharedPublic
    case directPrivate
    case unclassified
}

/// Logical service inside the external Enhancer (Phase 2/3 component split).
enum HelperService: String, CaseIterable, Sendable {
    case power
    case charge
    case sensor
    case audioDisplay
    case device
}

/// Runtime snapshot of the external Helper, provided by the versioned handshake
/// (Phase 2). Event-driven; never polled.
struct HelperRuntimeStatus: Equatable, Sendable {
    enum ServiceState: Equatable, Sendable {
        case ready
        case missingAuthorization(reason: String)
        case updateRequired(installed: Int, required: Int)
        case failed(reason: String)
    }

    struct Identity: Equatable, Sendable {
        let marketingVersion: String
        let protocolVersion: Int
        let teamID: String
        let advertisedCapabilities: Set<DistributionCapabilityID>
        let services: [HelperService: ServiceState]
    }

    enum Installation: Equatable, Sendable {
        case notInstalled
        case installed(Identity)
    }

    var installation: Installation

    static let notInstalled = HelperRuntimeStatus(installation: .notInstalled)
}

/// Minimal device facts the router needs. Kept tiny and value-typed so it can be
/// passed across boundaries and into tests without touching AppKit.
struct DeviceProfile: Equatable, Sendable {
    var isAppleSilicon: Bool
    var hasBattery: Bool
    var hasExternalDisplay: Bool

    init(isAppleSilicon: Bool = true, hasBattery: Bool = true, hasExternalDisplay: Bool = false) {
        self.isAppleSilicon = isAppleSilicon
        self.hasBattery = hasBattery
        self.hasExternalDisplay = hasExternalDisplay
    }

    static let `default` = DeviceProfile()
}

struct OSVersion: Equatable, Comparable, Sendable {
    let major: Int
    let minor: Int

    init(_ major: Int, _ minor: Int = 0) {
        self.major = major
        self.minor = minor
    }

    static func < (lhs: OSVersion, rhs: OSVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

/// Everything the router may consult. `runtimeProbe` results live in the concrete
/// native providers, not here; this context is the *routing* input.
struct CapabilityResolutionContext: Sendable {
    var channel: DistributionChannel
    var osVersion: OSVersion
    var deviceProfile: DeviceProfile
    var helper: HelperRuntimeStatus

    init(
        channel: DistributionChannel,
        osVersion: OSVersion = OSVersion(26),
        deviceProfile: DeviceProfile = .default,
        helper: HelperRuntimeStatus = .notInstalled
    ) {
        self.channel = channel
        self.osVersion = osVersion
        self.deviceProfile = deviceProfile
        self.helper = helper
    }
}

/// Static classification + helper contract per capability. Injected so the
/// router stays pure and testable; the provisional instance mirrors the design
/// matrix and is replaced when Phase 1 finishes the source audit.
struct CapabilityCatalog: Sendable {
    var sourceClass: [DistributionCapabilityID: CapabilitySourceClass]
    var helperService: [DistributionCapabilityID: HelperService]
    var minProtocolVersion: [DistributionCapabilityID: Int]
    /// Optional objective hard gate (OS/device). Return a terminal availability
    /// to stop routing, or nil to continue.
    var hardGate: (@Sendable (DistributionCapabilityID, CapabilityResolutionContext) -> CapabilityAvailability?)?

    init(
        sourceClass: [DistributionCapabilityID: CapabilitySourceClass],
        helperService: [DistributionCapabilityID: HelperService] = [:],
        minProtocolVersion: [DistributionCapabilityID: Int] = [:],
        hardGate: (@Sendable (DistributionCapabilityID, CapabilityResolutionContext) -> CapabilityAvailability?)? = nil
    ) {
        self.sourceClass = sourceClass
        self.helperService = helperService
        self.minProtocolVersion = minProtocolVersion
        self.hardGate = hardGate
    }

    func sourceClass(for id: DistributionCapabilityID) -> CapabilitySourceClass {
        sourceClass[id] ?? .unclassified
    }

    func service(for id: DistributionCapabilityID) -> HelperService? {
        helperService[id]
    }

    func requiredProtocolVersion(for id: DistributionCapabilityID) -> Int {
        minProtocolVersion[id] ?? 1
    }

    /// Provisional classification from the design matrix (§6). Pending source
    /// audit; unlisted capabilities stay `.unclassified` (safe default).
    static let provisional: CapabilityCatalog = {
        let sc: [DistributionCapabilityID: CapabilitySourceClass] = [
            .updates: .sharedPublic,
            .bluetoothBatteryLevels: .sharedPublic,
            .publicBluetoothReaders: .sharedPublic,
            .huaweiListeningMode: .sharedPublic,
            .applicationEnergy: .sharedPublic,
            .appleListeningMode: .directPrivate,
            .bluetoothRadioPower: .directPrivate,
            .ddc: .directPrivate,
            .externalVolume: .directPrivate,
            .chargeToFullNow: .directPrivate,
            .privilegedHelper: .directPrivate,
            .privatePowerReaders: .directPrivate,
            .internetSharing: .directPrivate,
            .mobileBatteryHelper: .directPrivate,
            .sensorsSMC: .directPrivate,
            .sensorsCPUFrequency: .directPrivate,
            .sleepControl: .directPrivate,
            .highPowerMode: .directPrivate,
            .lowPowerMode: .directPrivate,
            .externalBrightness: .directPrivate,
        ]
        // `updates` is injected per channel at composition; leave its class to
        // the caller by treating it as shared here.
        let svc: [DistributionCapabilityID: HelperService] = [
            .appleListeningMode: .audioDisplay,
            .bluetoothRadioPower: .audioDisplay,
            .ddc: .audioDisplay,
            .externalVolume: .audioDisplay,
            .externalBrightness: .audioDisplay,
            .chargeToFullNow: .charge,
            .privilegedHelper: .power,
            .privatePowerReaders: .sensor,
            .sensorsSMC: .sensor,
            .sensorsCPUFrequency: .sensor,
            .sleepControl: .power,
            .highPowerMode: .power,
            .lowPowerMode: .power,
            .mobileBatteryHelper: .device,
        ]
        return CapabilityCatalog(sourceClass: sc, helperService: svc)
    }()
}

struct CapabilityResolution: Equatable, Sendable {
    let capability: DistributionCapabilityID
    let tier: CapabilityProviderTier
    let availability: CapabilityAvailability
}

enum CapabilityPrimaryAction: Equatable, Sendable {
    case perform
    case openEnhancerInstallGuide
    case openEnhancerComponentCheck
    case requestHelperUpdate
    case openSystemPrivacyPane
    case retry
    case learnMoreUnsupported
    case none
}

enum CapabilitySeverity: Equatable, Sendable {
    case normal
    case info
    case needsAction
    case blocked
}

extension CapabilityResolution {
    var primaryAction: CapabilityPrimaryAction {
        switch availability {
        case .nativeAvailable, .helperProvided: return .perform
        case .helperNotInstalled: return .openEnhancerInstallGuide
        case .helperUpdateRequired: return .requestHelperUpdate
        case .helperMissingAuthorization: return .openEnhancerComponentCheck
        case .permissionDenied: return .openSystemPrivacyPane
        case .temporarilyUnavailable: return .retry
        case .unsupported, .notVerified: return .learnMoreUnsupported
        }
    }

    var severity: CapabilitySeverity {
        switch availability {
        case .nativeAvailable, .helperProvided: return .normal
        case .temporarilyUnavailable, .notVerified: return .info
        case .permissionDenied, .helperNotInstalled, .helperUpdateRequired, .helperMissingAuthorization:
            return .needsAction
        case .unsupported: return .blocked
        }
    }
}

/// Pure routing engine. `Native → External Helper → Unavailable`.
enum CapabilityRouter {
    /// Which tiers a channel may select for a capability. The channel never
    /// decides final availability; it only gates provider selection.
    static func allowedTiers(
        for id: DistributionCapabilityID,
        channel: DistributionChannel,
        sourceClass: CapabilitySourceClass
    ) -> [CapabilityProviderTier] {
        switch channel {
        case .direct:
            // Direct keeps every production source; native first, helper optional.
            return [.native, .externalHelper]
        case .appStore:
            switch sourceClass {
            case .sharedPublic: return [.native, .externalHelper]
            case .directPrivate, .unclassified: return [.externalHelper]
            }
        }
    }

    static func resolve(
        _ id: DistributionCapabilityID,
        context: CapabilityResolutionContext,
        catalog: CapabilityCatalog = .provisional
    ) -> CapabilityResolution {
        // 1) Objective hard gate first (OS/hardware). Terminal when present.
        if let hard = catalog.hardGate?(id, context) {
            return CapabilityResolution(capability: id, tier: .unavailable, availability: hard)
        }

        let sourceClass = catalog.sourceClass(for: id)
        // 2) Walk allowed tiers in order.
        for tier in allowedTiers(for: id, channel: context.channel, sourceClass: sourceClass) {
            switch tier {
            case .native:
                if let availability = nativeAvailability(id, context, sourceClass: sourceClass) {
                    return CapabilityResolution(capability: id, tier: .native, availability: availability)
                }
            case .externalHelper:
                if let availability = helperAvailability(id, context.helper, catalog: catalog) {
                    return CapabilityResolution(capability: id, tier: .externalHelper, availability: availability)
                }
            case .unavailable:
                break
            }
        }

        // 3) No provider: report the most accurate reason.
        let fallback: CapabilityAvailability
        if catalog.service(for: id) != nil {
            if case .notInstalled = context.helper.installation {
                fallback = .helperNotInstalled
            } else {
                fallback = .notVerified
            }
        } else {
            fallback = .unsupported(reason: "no-provider")
        }
        return CapabilityResolution(capability: id, tier: .unavailable, availability: fallback)
    }

    /// Native route availability. The concrete native provider owns runtime
    /// gating (permissions, hardware state); this pure router reports the route
    /// as usable when it is selectable. Private capabilities are never selectable
    /// natively on the App Store channel, so they never reach here there.
    private static func nativeAvailability(
        _ id: DistributionCapabilityID,
        _ context: CapabilityResolutionContext,
        sourceClass: CapabilitySourceClass
    ) -> CapabilityAvailability? {
        .nativeAvailable
    }

    /// Helper availability, in strict precedence order (design §5).
    private static func helperAvailability(
        _ id: DistributionCapabilityID,
        _ helper: HelperRuntimeStatus,
        catalog: CapabilityCatalog
    ) -> CapabilityAvailability? {
        // Not a helper-servable capability: skip the tier entirely.
        guard let service = catalog.service(for: id) else { return nil }

        switch helper.installation {
        case .notInstalled:
            return .helperNotInstalled
        case .installed(let identity):
            if identity.protocolVersion < catalog.requiredProtocolVersion(for: id) {
                return .helperUpdateRequired
            }
            guard identity.advertisedCapabilities.contains(id) else {
                return .notVerified
            }
            if let state = identity.services[service] {
                switch state {
                case .ready:
                    return .helperProvided
                case .missingAuthorization:
                    return .helperMissingAuthorization
                case .updateRequired:
                    return .helperUpdateRequired
                case .failed(let reason):
                    return .temporarilyUnavailable(reason: reason)
                }
            }
            // Advertised but no explicit per-service state: still provided.
            return .helperProvided
        }
    }
}
