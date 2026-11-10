import Foundation

/// Per-display brightness backend choice, persisted by display UUID.
///
/// External displays default to direct DDC because it needs no third-party app.
/// Built-in displays can only use BetterDisplay, so their stored backend is
/// normalized to `.betterDisplay` when it is read back.
struct ExternalBrightnessConfiguration: Codable, Equatable, Sendable {
    var backend: BrightnessBackend
    /// The BetterDisplay display UUID, when it differs from the system display
    /// UUID. Nil means "use the system display UUID".
    var betterDisplayUUID: String?

    static let `default` = Self(backend: .directDDC, betterDisplayUUID: nil)
    /// New external displays follow BetterDisplay while it is running, then DDC.
    static let automatic = Self(backend: .automatic, betterDisplayUUID: nil)

    /// Normalizes a stored value. Returns nil only for a configuration that
    /// cannot be repaired into a safe default.
    func sanitized() -> Self? {
        switch backend {
        case .automatic:
            return Self(backend: .automatic, betterDisplayUUID: nil)
        case .directDDC, .displayServices:
            return Self(backend: backend, betterDisplayUUID: nil)
        case .betterDisplay:
            let uuid = betterDisplayUUID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Self(
                backend: .betterDisplay,
                betterDisplayUUID: uuid?.isEmpty == false ? uuid : nil
            )
        }
    }
}
