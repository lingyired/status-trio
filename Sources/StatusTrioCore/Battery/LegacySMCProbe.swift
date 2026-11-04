import Foundation

/// Read-only capability discovery for the legacy charge limiter.
///
/// Phase 2 orchestrates discovery by reading the SMC through the injected
/// `SMCAccessing` surface (real `IOKit` in the helper, `FakeSMC` in tests). It
/// performs **no writes** and makes **no entitlement guesses**: a key is
/// reported `present` when it exists with the expected type/width, and
/// `verifiedWritable` only after an authorized behavioural probe confirms a
/// write on that specific host.
struct LegacySMCProbe {
    /// Maximum data size we will treat as a sane SMC payload (4 bytes for the
    /// charge keys we understand; BCLM is 1). Larger buffers are rejected so a
    /// mis-keyed read cannot be misread as a charge ceiling.
    static let maxSaneDataSize = 4

    /// Keys the legacy limiter recognises, with their expected data types.
    /// Presence means "exists with this type at a sane width"; anything else
    /// is treated as absent so we never write a key we do not understand.
    static let recognizedKeys: [String: String] = [
        LegacySMCKeys.intelBCLM: "ui8",
        LegacySMCKeys.siliconCH0B: "ui8",
        LegacySMCKeys.siliconCH0C: "ui8",
        LegacySMCKeys.siliconCHTE: "ui32",
    ]

    static func probe(
        smc: SMCAccessing,
        architecture: LegacyRuntimeArchitecture,
        osBand: LegacyOSBand,
        hasInternalBattery: Bool
    ) -> LegacyHardwareCapabilities {
        var presentKeys: Set<String> = []
        var keyInfo: [String: LegacySMCKeyInfo] = [:]

        for (key, expectedType) in recognizedKeys {
            guard let info = smc.readKey(key)?.info,
                  info.dataType == expectedType,
                  info.dataSize > 0,
                  info.dataSize <= maxSaneDataSize else {
                continue
            }
            presentKeys.insert(key)
            keyInfo[key] = info
        }

        // BCLM is consumer-relevant for Intel; the inhibit pair/CHTE for
        // Silicon. We record presence independently of architecture so the
        // selection policy can pick the right family.
        return LegacyHardwareCapabilities(
            architecture: architecture,
            osBand: osBand,
            hasInternalBattery: hasInternalBattery,
            presentKeys: presentKeys,
            verifiedWritableKeys: [],
            keyInfo: keyInfo
        )
    }
}

/// Finds whether an internal battery is present.
///
/// This is a read-only registry query used to gate the whole feature on a real
/// internal battery. It is intentionally separate from the SMC key probe so it
/// can run without any entitlement. In Phase 2 the production query is wired in
/// the helper/IOKit layer and injected as a boolean factor into `probe(...)`;
/// tests inject a fixed value so no IOKit call happens in unit tests.
enum LegacyBatteryPresence {
    /// Default representation of "not yet wired" is conservative (false). The
    /// probe takes the value as a parameter, so no global mutable state lives
    /// here.
    static let defaultHasInternalBattery = false
}