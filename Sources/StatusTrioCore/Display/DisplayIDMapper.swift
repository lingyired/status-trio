import CoreGraphics

/// Correlates an external framebuffer's EDID identity with the
/// `CGDirectDisplayID` that CoreGraphics and BetterDisplay actually use.
///
/// Why this exists: on Apple Silicon the IORegistry framebuffer for an external
/// display exposes an `EDID UUID` directly, but *not* a `CGDirectDisplayID`, and
/// the CG UUID of the display is a different string from the EDID UUID. Passing
/// `displayID = 0` (the previous placeholder) is not neutral: CoreGraphics
/// resolves `CGDisplayCreateUUIDFromDisplayID(0)` to the main display, so
/// BetterDisplay and DisplayServices ended up driving the built-in panel.
///
/// Current strategy: correlate the EDID product identity (vendor id, product id,
/// and serial number) against the online CG display list. A mapping is accepted
/// only when exactly one online, non-built-in display matches and that display
/// has a non-zero `CGDirectDisplayID`. Anything ambiguous or incomplete returns
/// `nil` so the caller can fail closed instead of guessing a screen.
///
/// Known limits (deliberate fail-closed behavior):
/// - a display that reports serial `0` cannot be distinguished from another
///   unit of the same model, so automatic mapping is unavailable for it;
/// - duplicate serials among same-model units are likewise ambiguous;
/// - the user can still select the display explicitly by BetterDisplay UUID,
///   which bypasses this heuristic.
/// This is not claimed to be the only possible correlation method, only the
/// conservative one used here.
enum DisplayIDMapper {
    /// Identity as published by the external framebuffer's `DisplayAttributes`.
    struct ExternalIdentity: Equatable, Sendable {
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32
        let edidUUID: String
    }

    /// Identity projection of one online CoreGraphics display.
    struct OnlineDisplay: Equatable, Sendable {
        let displayID: CGDirectDisplayID
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32
        let isBuiltin: Bool
    }

    /// Returns the unique online external display id for `identity`, or `nil`.
    ///
    /// Fail-closed rules:
    /// - `displayID` 0 is never returned (it is not a real screen).
    /// - built-in displays never match an external framebuffer.
    /// - the identity must carry a non-zero serial, because two units of the
    ///   same model otherwise cannot be told apart.
    /// - zero or more than one candidate means "cannot map reliably".
    static func uniqueDisplayID(
        for identity: ExternalIdentity,
        among displays: [OnlineDisplay]
    ) -> CGDirectDisplayID? {
        guard identity.vendorID != 0,
              identity.productID != 0,
              identity.serialNumber != 0,
              !identity.edidUUID.isEmpty
        else { return nil }

        let matches = displays.filter { display in
            !display.isBuiltin
                && display.displayID != 0
                && display.vendorID == identity.vendorID
                && display.productID == identity.productID
                && display.serialNumber == identity.serialNumber
        }
        guard matches.count == 1 else { return nil }
        return matches[0].displayID
    }
}
