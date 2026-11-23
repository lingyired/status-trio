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
///
/// Safe fallback (issue #313): many panels (including several Redmi models)
/// publish EDID serial `0`, so the identity match above never succeeds for them.
/// When the identity match fails we fall back to the *only* online external
/// display, but only under a condition that cannot repeat #285: there must be no
/// built-in display online at all and exactly one online external display. In
/// that shape the single external id is unambiguous and cannot be the built-in
/// panel. Multiple externals, or any built-in present, still fail closed.
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

    /// Resolves the display id for `identity`, preferring the strict identity
    /// match and falling back to the single-external case when that fails.
    ///
    /// The fallback exists because an EDID serial of `0` (common on several
    /// panel models) makes the strict match impossible, which regressed these
    /// displays from adjustable to "unavailable" in 1.9.4. It stays safe against
    /// #285 by requiring that no built-in display be online at all and that
    /// exactly one online external display exist; anything else fails closed.
    static func resolvedDisplayID(
        for identity: ExternalIdentity,
        among displays: [OnlineDisplay]
    ) -> CGDirectDisplayID? {
        uniqueDisplayID(for: identity, among: displays)
            ?? soleExternalDisplayID(among: displays)
    }

    /// The id of the only online external display, or `nil`.
    ///
    /// Only returns a value when there is no built-in display online and exactly
    /// one online external display with a non-zero id. That shape cannot alias
    /// the built-in panel (#285) and cannot be ambiguous.
    static func soleExternalDisplayID(
        among displays: [OnlineDisplay]
    ) -> CGDirectDisplayID? {
        guard !displays.contains(where: { $0.isBuiltin }) else { return nil }
        let externals = displays.filter { !$0.isBuiltin && $0.displayID != 0 }
        guard externals.count == 1 else { return nil }
        return externals[0].displayID
    }
}
