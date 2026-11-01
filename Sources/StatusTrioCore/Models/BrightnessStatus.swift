import Foundation

/// Which mechanism is allowed to read and write one display's brightness.
enum BrightnessBackend: String, Codable, CaseIterable, Sendable {
    /// Direct DDC/CI over I2C. External displays default to this.
    case directDDC
    /// Apple's private DisplayServices framework. Built-in displays use this so
    /// no third-party app is required (maintainer-approved private API).
    case displayServices
    /// BetterDisplay's notification API. Kept as an optional backend for
    /// external displays; no longer required for built-in displays.
    case betterDisplay
}

/// Why a display has no adjustable brightness, in stable identifier-free form.
enum BrightnessUnavailableReason: String, Equatable, Sendable {
    /// No backend is available for this display (e.g. built-in without BetterDisplay).
    case noBackend
    /// BetterDisplay is not running.
    case appAbsent
    /// The backend stopped responding.
    case unresponsive
    /// A write was acknowledged but a read-back did not confirm it.
    case writeNotConfirmed
    /// No unique DDC service could be resolved for this display.
    case resolveFailed
    /// The display answered, but not with a valid brightness VCP reply.
    case readFailed
    /// A read never completed inside the watchdog window.
    case timeout
    /// The display refused VCP `0x10`.
    case unsupportedVCP
}

/// Where one display's current brightness reading came from.
enum BrightnessControlSource: Equatable, Sendable {
    case directDDC
    case displayServices
    case betterDisplay
    case unavailable(BrightnessUnavailableReason)
}

/// One connected display's brightness, as published to the panel.
struct DisplayBrightness: Equatable, Sendable, Identifiable {
    /// Stable display identity (`CGDisplayCreateUUIDFromDisplayID`).
    let id: String
    let name: String
    let isBuiltin: Bool
    /// 0...1, or nil while the value is unknown or unreadable.
    let scalar: Double?
    let canAdjust: Bool
    let backend: BrightnessBackend
    let source: BrightnessControlSource

    init(
        id: String,
        name: String,
        isBuiltin: Bool,
        scalar: Double? = nil,
        canAdjust: Bool = false,
        backend: BrightnessBackend,
        source: BrightnessControlSource
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.scalar = scalar
        self.canAdjust = canAdjust
        self.backend = backend
        self.source = source
    }
}

struct BrightnessStatus: Equatable, Sendable {
    let displays: [DisplayBrightness]
    let transitionGeneration: UInt64

    init(displays: [DisplayBrightness], transitionGeneration: UInt64 = 0) {
        self.displays = displays
        self.transitionGeneration = transitionGeneration
    }

    static let placeholder = BrightnessStatus(displays: [])
}
