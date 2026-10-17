import Foundation

/// Pure, hardware-free description of one external framebuffer branch.
///
/// The hardware layer fills these in from the IORegistry; the resolver only
/// works on the plain values so every decision is deterministic and testable
/// without touching IOKit.
struct DDCFramebufferSnapshot: Equatable, Sendable {
    /// Registry identity of the framebuffer entry (stable while connected).
    let entryID: UInt64
    /// The `dispextN` node name shared with the owning DCP branch.
    let branchName: String
    /// `EDID UUID`, only present for a connected external display.
    let edidUUID: String?
}

/// Pure description of one external `DCPAVServiceProxy`.
struct DDCServiceSnapshot: Equatable, Sendable {
    /// Registry identity of the proxy entry (stable while connected).
    let entryID: UInt64
    /// The `dispextN` branch token carried by the proxy's ancestor chain, or
    /// nil when the running macOS registers no recognizable token. Nil is
    /// "evidence unavailable", not "matches anything".
    let branchName: String?
    /// Proxy reported `Location`; only `"External"` enters the resolver.
    let location: String?
}

/// Why the resolver could not produce a single writable target.
enum DDCResolutionFailure: Equatable, Sendable {
    case missingAudioUID
    case noMatchingFramebuffer
    case ambiguousFramebuffer
    case noAssociatedService
    case ambiguousService
    /// This Mac is not Apple Silicon, so DDC/CI is not offered.
    case unsupportedArchitecture
    /// The registry or `IOAVService` could not be created.
    case transportUnavailable
    /// The display answered, but not with a valid VCP `0x62` reply.
    case unsupportedVolumeVCP
    /// I2C traffic failed before a valid reply arrived.
    case readFailed
    /// A read never returned inside the watchdog window.
    case timeout

    /// Single-line, identifier-free description for diagnostics.
    var diagnosticName: String {
        switch self {
        case .missingAudioUID: "missingAudioUID"
        case .noMatchingFramebuffer: "noMatchingFramebuffer"
        case .ambiguousFramebuffer: "ambiguousFramebuffer"
        case .noAssociatedService: "noAssociatedService"
        case .ambiguousService: "ambiguousService"
        case .unsupportedArchitecture: "unsupportedArchitecture"
        case .transportUnavailable: "transportUnavailable"
        case .unsupportedVolumeVCP: "unsupportedVolumeVCP"
        case .readFailed: "readFailed"
        case .timeout: "timeout"
        }
    }
}

/// Outcome of the pure matching step.
enum DDCResolution: Equatable, Sendable {
    case matched(framebufferEntryID: UInt64, serviceEntryID: UInt64)
    case unavailable(DDCResolutionFailure)
}

/// Decides which external framebuffer and DDC proxy belong to the current
/// Core Audio output. Identity is established in two independent steps:
///
/// 1. The output UID must equal exactly one connected external framebuffer's
///    `EDID UUID`. This is the same identity macOS itself uses, so names,
///    enumeration order, and display models never participate.
/// 2. That framebuffer's `dispextN` branch name must equal the branch token of
///    exactly one external `DCPAVServiceProxy`. The token comes from the proxy's
///    own `dispextN:dcpav-service-epic:*` ancestor, which the DCP firmware
///    registers under the matching `dcpextN` branch.
///
/// When the firmware exposes no branch token at all, the previous behavior is
/// preserved for the strictly unambiguous one-framebuffer/one-service case,
/// and nothing else. Concrete-but-mismatching tokens are contradictory
/// evidence and are refused.
///
/// Any doubt fails closed: no service is returned and no I2C is attempted.
enum DDCTargetResolver {
    static func resolve(
        outputUID: String?,
        framebuffers: [DDCFramebufferSnapshot],
        services: [DDCServiceSnapshot]
    ) -> DDCResolution {
        guard let outputUID, !outputUID.isEmpty else {
            return .unavailable(.missingAudioUID)
        }

        // Only external branches can own a DDC service; the internal display
        // branch must never become a DDC target even if its EDID happened to
        // equal the output UID.
        let externalFramebuffers = framebuffers.filter { $0.branchName.hasPrefix("dispext") }
        let externalServices = services.filter { $0.location == "External" }

        let framebufferMatches = externalFramebuffers.filter { $0.edidUUID == outputUID }
        guard !framebufferMatches.isEmpty else {
            return .unavailable(.noMatchingFramebuffer)
        }
        guard framebufferMatches.count == 1 else {
            return .unavailable(.ambiguousFramebuffer)
        }
        let framebuffer = framebufferMatches[0]

        let serviceMatches = externalServices.filter { $0.branchName == framebuffer.branchName }
        if serviceMatches.count == 1 {
            return .matched(
                framebufferEntryID: framebuffer.entryID,
                serviceEntryID: serviceMatches[0].entryID
            )
        }
        if serviceMatches.count > 1 {
            return .unavailable(.ambiguousService)
        }

        // Legacy fallback: machines whose DCP firmware exposes no branch token
        // at all keep the pre-#115 behavior, and only when the topology is the
        // strictly unambiguous one-framebuffer/one-service case.
        let tokensUnavailable = externalServices.allSatisfy { $0.branchName == nil }
        guard tokensUnavailable,
              externalFramebuffers.count == 1,
              externalServices.count == 1,
              let legacyService = externalServices.first else {
            return .unavailable(.noAssociatedService)
        }

        return .matched(
            framebufferEntryID: framebuffer.entryID,
            serviceEntryID: legacyService.entryID
        )
    }

    /// Opens only the service the resolver selected.
    ///
    /// Selecting identity before calling `open` guarantees that an ambiguous or
    /// unavailable decision can never open — let alone write to — any service.
    static func openResolvedTarget<Handle, Opened>(
        _ resolution: DDCResolution,
        services: [(entryID: UInt64, handle: Handle)],
        open: (Handle) -> Opened?
    ) -> (framebufferEntryID: UInt64, serviceEntryID: UInt64, opened: Opened)? {
        guard case let .matched(framebufferEntryID, serviceEntryID) = resolution,
              let candidate = services.first(where: { $0.entryID == serviceEntryID }),
              let opened = open(candidate.handle) else { return nil }
        return (framebufferEntryID, serviceEntryID, opened)
    }
}
