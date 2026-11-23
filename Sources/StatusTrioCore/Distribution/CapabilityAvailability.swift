/// Final availability of a capability for the current distribution, platform and
/// helper state. This is the single normalized vocabulary shared by UI, actions
/// and composition (see `docs/dual-distribution-v2-capability-model.md`).
///
/// Nine states = the original five plus four helper-related states. The channel
/// only decides which provider tiers may serve a capability; it never equals the
/// final availability on its own.
enum CapabilityAvailability: Equatable, Sendable {
    /// Provided natively inside the main process (including Direct's existing
    /// runtime gates passing).
    case nativeAvailable
    /// Provided by a connected, authorized, protocol-compatible external Helper.
    case helperProvided
    /// The capability is Helper-only, but no Helper is installed.
    case helperNotInstalled
    /// A Helper is installed but its protocol/version is below what this
    /// capability requires.
    case helperUpdateRequired
    /// A Helper is installed and compatible, but a required system
    /// authorization is missing.
    case helperMissingAuthorization
    /// Objectively unsupported on the current macOS / hardware.
    case unsupported(reason: String)
    /// Device/environment temporarily unavailable (unplugged, asleep, switching
    /// devices, ...). Recoverable later.
    case temporarilyUnavailable(reason: String)
    /// The user denied a system permission (can deep-link to Settings).
    case permissionDenied(reason: String)
    /// Not verified. Never treat this as available.
    case notVerified

    /// Whether the user can trigger the capability's *action* right now.
    var isActionable: Bool {
        switch self {
        case .nativeAvailable, .helperProvided: true
        default: false
        }
    }

    /// Whether this state should hard-prevent the control from performing a
    /// write. `permissionDenied` and `temporarilyUnavailable` are recoverable
    /// (the user or environment can fix them), so they are not composition
    /// blocks; `unsupported`/`notVerified`/missing-helper are.
    var isCompositionBlocked: Bool {
        switch self {
        case .unsupported, .notVerified,
             .helperNotInstalled, .helperUpdateRequired, .helperMissingAuthorization:
            true
        case .nativeAvailable, .helperProvided, .permissionDenied, .temporarilyUnavailable:
            false
        }
    }

    // MARK: - Backward-compatible names (design D1)
    //
    // Kept as computed values so existing value/equality use sites keep
    // compiling during the incremental migration (S1 → S6 in the design doc).
    @available(*, deprecated, renamed: "nativeAvailable")
    static var available: CapabilityAvailability { .nativeAvailable }

    @available(*, deprecated, renamed: "permissionDenied")
    static var permissionRequired: CapabilityAvailability {
        .permissionDenied(reason: "permission.required")
    }
}
