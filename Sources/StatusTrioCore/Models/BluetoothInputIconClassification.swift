import Foundation

/// What glyph an input device's row should draw.
///
/// This is a *display* classification and is deliberately decoupled from
/// `BluetoothDeviceKind`: nothing here decides connection, disconnect
/// confirmation, ordering, battery handling or audio eligibility. It exists
/// because the declared class and the HID interfaces disagree in practice, and
/// for a keyboard/mouse composite neither source can be trusted to name the
/// device (see `docs/bluetooth-status.md`).
enum BluetoothInputIconClassification: Equatable, Sendable {
    case mouse
    case keyboard
    case trackpad
    case gamepad
    /// The device presents both mouse and keyboard interfaces, or its declared
    /// class conflicts with what it enumerates. Neither a mouse nor a keyboard
    /// glyph would be honest, so the row draws a non-committal input glyph
    /// instead of a definite but possibly wrong one.
    case genericInput
}

/// Decides the display classification from the declared class and the HID
/// capabilities the device was observed to present.
///
/// Pure, so the whole decision table is unit-tested rather than inferred from a
/// live Mac's device list. It reads the capabilities as a set — never the order
/// or the first usage — so a composite device that orders its collections
/// differently cannot change the answer.
enum BluetoothInputIconClassifier {
    /// `nil` means "draw the declared class": the device is outside the input
    /// family, or nothing was observed that could refine it. A conflict or a
    /// mixed mouse/keyboard device answers `.genericInput` instead of guessing.
    static func classify(
        declared: BluetoothDeviceKind,
        capabilities: BluetoothHIDCapabilities
    ) -> BluetoothInputIconClassification? {
        let declaredForm: PeripheralForm?
        switch declared {
        case .peripheral(let form):
            declaredForm = form
        case .unknown:
            declaredForm = nil
        case .computer, .mobile, .audio, .imaging, .toy, .health:
            // These families never draw an input glyph, so a stray HID
            // interface on one of them must not move it into the input family.
            return nil
        }

        if capabilities.hasTrackpad { return .trackpad }
        if capabilities.hasGamepad { return .gamepad }

        // Nothing recognizable was observed; keep the declared class.
        guard capabilities.hasMouse || capabilities.hasKeyboard else { return nil }

        // A declared trackpad or gamepad only accepts a matching specialized
        // usage. A pointing or keyboard interface it also exposes must not
        // downgrade it to a mouse or keyboard glyph.
        if declaredForm == .trackpad || declaredForm == .gamepad { return nil }

        if capabilities.hasMouse && capabilities.hasKeyboard { return .genericInput }

        if capabilities.hasMouse {
            return declaredForm == .keyboard ? .genericInput : .mouse
        }
        return declaredForm == .mouse ? .genericInput : .keyboard
    }
}