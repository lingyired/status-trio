import CoreAudio
import Foundation

/// A Bluetooth audio device's Listening Mode, as the CoreAudio HAL reports it.
///
/// The raw cases mirror the undocumented `lstm` integer the HAL exposes, so a
/// value read straight off the device can be resolved with `init?(rawValue:)`
/// and an unknown value fails closed to `nil`. Keeping the raw values here — and
/// nowhere in the view layer — is what lets the rest of the app talk about
/// "Noise Cancellation" while this one type knows it is the number `2`.
enum BluetoothListeningMode: UInt32, CaseIterable, Equatable, Hashable, Sendable {
    case off = 1
    case noiseCancellation = 2
    case transparency = 3
    case adaptive = 4

    /// Legacy capsule modes represented by lsms bits. Off is added separately
    /// by the HAL capability reader because it has no support-mask bit.
    static let v1Selectable: [BluetoothListeningMode] = [
        .noiseCancellation,
        .transparency,
        .adaptive
    ]

    /// The order the control lays the modes out in, left to right, independent of
    /// the `lsms` bit order. A fixed order keeps the buttons from jumping around
    /// as the support mask changes.
    static let displayOrder: [BluetoothListeningMode] = [.noiseCancellation, .transparency, .adaptive]

    /// Whether this mode uses the legacy support-mask path. Off is validated
    /// separately by the HAL writer.
    var isUserSelectable: Bool {
        Self.v1Selectable.contains(self)
    }

    /// The `lsms` bit this mode occupies, or `nil` for `off`, which the support
    /// mask never signals. Bit assignment per the HAL convention:
    /// `bit 0 = Noise Cancellation`, `bit 1 = Transparency`, `bit 2 = Adaptive`.
    var supportBit: UInt32? {
        switch self {
        case .noiseCancellation: return 0x1 << 0
        case .transparency: return 0x1 << 1
        case .adaptive: return 0x1 << 2
        case .off: return nil
        }
    }

    /// The title drawn on the mode's capsule button.
    var titleKey: LocalizationKey {
        switch self {
        case .off: return .bluetoothListeningModeOff
        case .noiseCancellation: return .bluetoothListeningModeNoiseCancellation
        case .transparency: return .bluetoothListeningModeTransparency
        case .adaptive: return .bluetoothListeningModeAdaptive
        }
    }
}

/// The modes a device's `lsms` support mask advertises.
///
/// The mask is a bit field, and Apple may add bits in a future system. Unknown
/// bits are dropped, not guessed at: a bit this code does not name is never
/// promoted to a mode, so an OS update that adds, say, a "Conversation Boost"
/// bit cannot silently surface a half-wired button. The presence of unknown bits
/// is still reported so a debug log can note it without the UI acting on it.
enum BluetoothListeningModeSupport {
    /// The bits V1 recognises, one per selectable mode.
    static let recognizedMask: UInt32 = 0x1 << 0 | 0x1 << 1 | 0x1 << 2

    /// The supported, user-selectable modes, in `displayOrder`.
    ///
    /// `off` has no bit and so never appears here; a mask of `0` therefore yields
    /// an empty array, which the caller treats as "no control".
    static func availableModes(from mask: UInt32) -> [BluetoothListeningMode] {
        BluetoothListeningMode.displayOrder.filter { mode in
            guard let bit = mode.supportBit else { return false }
            return mask & bit != 0
        }
    }

    /// Whether the mask carries bits this build does not name. A future Apple
    /// mode shows up here; the UI ignores it, but a debug log can record it.
    static func hasUnknownBits(_ mask: UInt32) -> Bool {
        mask & ~recognizedMask != 0
    }
}

/// The current-mode integer a device reports through `lstm`, resolved to a mode.
///
/// `0` is "unresolved / unknown" and any value outside the known range is a
/// mode this build cannot name. Both fail closed to `nil`, so the control never
/// highlights a mode it only half understands.
enum BluetoothListeningModeRawValue {
    static func mode(from raw: UInt32) -> BluetoothListeningMode? {
        BluetoothListeningMode(rawValue: raw)
    }
}

/// Everything the control needs to draw one device, decided once from the HAL
/// reads so the view never re-derives a rule the model already owns.
struct BluetoothListeningModeCapability: Equatable, Sendable {
    let audioDeviceID: AudioDeviceID
    /// The modes the device supports, already filtered to user-selectable ones
    /// and in `displayOrder`. Fewer than two means the control stays hidden —
    /// a single-mode device has nothing to switch between.
    let availableModes: [BluetoothListeningMode]
    /// The mode the device is in right now, or `nil` when it reports an
    /// unknown value. `nil` is not "no selection"; it is "the current mode is not
    /// one of the buttons", so no capsule is highlighted.
    let currentMode: BluetoothListeningMode?
    /// Whether `lstm` was readable and settable at probe time. The control hides
    /// itself when this is `false` even if modes are present.
    let canSet: Bool

    /// Whether the control should appear at all: at least two selectable modes and
    /// a writable `lstm`. One mode is a label, not a switch, so it is not worth a
    /// button the user cannot use.
    var isControllable: Bool {
        canSet && availableModes.count >= 2
    }
}

/// The outcome of asking a device to change its listening mode.
///
/// The naming matters: a successful `AudioObjectSetPropertyData` only means the
/// macOS control surface accepted the write, not that the earbuds acknowledged
/// it. `confirmed` therefore reports that a later read-back of `lstm` still shows
/// the target, which is the strongest statement this path can honestly make.
enum BluetoothListeningModeWriteResult: Equatable, Sendable {
    /// The write landed and `lstm` read back as the target within the retry budget.
    case confirmed(BluetoothListeningMode)
    /// The setter returned no error but read-back never matched the target — the
    /// device ended on `observed` (or, if it vanished, `nil`). The caller must
    /// fall back to this value, not to the requested one.
    case unconfirmed(observed: BluetoothListeningMode?)
    /// The write could not be attempted or completed at the HAL level.
    case failed(BluetoothListeningModeWriteFailure)
}

/// Why a mode write did not happen at all.
enum BluetoothListeningModeWriteFailure: Equatable, Sendable {
    /// `lstm` was gone or unreadable before the write.
    case propertyUnavailable
    /// `lstm` existed but was not settable.
    case notSettable
    /// The requested mode is not in the device's supported set.
    case modeUnsupported
    /// `AudioObjectSetPropertyData` returned an error. Carries the `OSStatus`.
    case setterFailed(status: Int32)
}

/// What the control shows while a change is in flight, per device.
///
/// A single `isLoading` flag is not enough: the capsule that is spinning is the
/// one the user tapped, so the state names its target. `failed` lingers just long
/// enough for the row to fall back to the observed mode, then clears.
enum BluetoothListeningModeActionState: Equatable, Sendable {
    case idle
    case changing(to: BluetoothListeningMode)
    case failed
}

/// The device-facing, view-ready form of a capability plus its in-flight state.
///
/// The controller publishes one of these per connected, eligible device, keyed by
/// the normalized Bluetooth address. The view reads `availableModes` and
/// `selectedMode` to draw, and `actionState` to show progress — and never touches
/// the `AudioDeviceID` behind it.
struct BluetoothListeningModePresentation: Equatable, Sendable {
    let availableModes: [BluetoothListeningMode]
    /// The mode to highlight, or `nil` when the device reports an unknown mode or in the
    /// middle of a change to a mode the read-back has not confirmed yet.
    let selectedMode: BluetoothListeningMode?
    let actionState: BluetoothListeningModeActionState

    /// A presentation the control will not draw, for a device with nothing to
    /// switch. Kept as a value rather than `nil` so callers can branch on
    /// `isControllable` uniformly.
    var isControllable: Bool {
        availableModes.count >= 2
    }

    init(
        availableModes: [BluetoothListeningMode],
        selectedMode: BluetoothListeningMode?,
        actionState: BluetoothListeningModeActionState = .idle
    ) {
        self.availableModes = availableModes
        self.selectedMode = selectedMode
        self.actionState = actionState
    }

    /// The presentation a capability maps to before any user action.
    init(capability: BluetoothListeningModeCapability) {
        // The current mode is only highlighted when it is one of the selectable
        // buttons; an unavailable or unknown value shows no selection.
        let highlighted = capability.currentMode.flatMap { mode in
            capability.availableModes.contains(mode) ? mode : nil
        }
        self.init(
            availableModes: capability.availableModes,
            selectedMode: highlighted,
            actionState: .idle
        )
    }

    /// The presentation while a change to `mode` is in flight: the caller keeps
    /// showing the last confirmed selection, and the target capsule renders busy.
    func changing(to mode: BluetoothListeningMode) -> BluetoothListeningModePresentation {
        BluetoothListeningModePresentation(
            availableModes: availableModes,
            selectedMode: selectedMode,
            actionState: .changing(to: mode)
        )
    }

    /// The presentation after a change settles on `mode`: the selection moves to
    /// the observed value and the busy state clears. A `nil` mode (unknown)
    /// clears the highlight rather than inventing a selection.
    func settled(on mode: BluetoothListeningMode?) -> BluetoothListeningModePresentation {
        BluetoothListeningModePresentation(
            availableModes: availableModes,
            selectedMode: mode.flatMap { availableModes.contains($0) ? $0 : nil },
            actionState: .idle
        )
    }
}

extension BluetoothListeningModePresentation {
    /// The mode a tap on `mode` should request from the device.
    ///
    /// Tapping the capsule that is already the confirmed selection asks the
    /// device to turn its listening mode *off*; tapping any other capsule selects
    /// it. Off can also be selected explicitly. Keeping the rule here means
    /// both the CoreAudio and HUAWEI write
    /// paths — and the preview — resolve a tap identically.
    func requestedMode(forTapped mode: BluetoothListeningMode) -> BluetoothListeningMode {
        selectedMode == mode ? .off : mode
    }

    /// Whether a write to this device is currently in flight.
    var isChanging: Bool {
        if case .changing = actionState { return true }
        return false
    }

    /// Whether the in-flight write is specifically heading for `mode` — the capsule
    /// that renders busy.
    func isChanging(to mode: BluetoothListeningMode) -> Bool {
        if case .changing(let target) = actionState { return target == mode }
        return false
    }

    /// Whether the last change failed and the failure is still on screen.
    var isFailed: Bool {
        if case .failed = actionState { return true }
        return false
    }

    /// Clears a lingering failure back to idle, keeping the current selection.
    func settledAfterFailure() -> BluetoothListeningModePresentation {
        BluetoothListeningModePresentation(
            availableModes: availableModes,
            selectedMode: selectedMode,
            actionState: .idle
        )
    }
}
