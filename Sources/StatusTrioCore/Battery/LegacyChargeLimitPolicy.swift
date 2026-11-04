import Foundation

/// Pure policy that maps a requested ceiling into concrete SMC write values
/// and knows how to verify a readback for each backend. No IOKit here; tests
/// drive it with `FakeSMC`.
///
/// The byte shapes are derived from the project reference behaviour (batt,
/// battery, charge-limiter), re-implemented independently here. See
/// `docs/legacy-charge-limit.md` §1 for provenance and the licence note that
/// GPL-derived byte shapes are knowledge, not copied code.

enum LegacySMCBytePolicy {
    // MARK: Intel firmware ceiling (BCLM)

    /// Writes the ceiling into a ui8 `BCLM`. `100` means "no cap".
    static func intelBCLMWriteBytes(forLimit limit: Int) -> Data {
        Data([UInt8(limit & 0xFF)])
    }

    /// Reads a ui8 `BCLM` out to an integer ceiling. Returns nil when the key
    /// is not the expected width.
    static func intelBCLMReadValue(from data: Data) -> Int? {
        guard data.count == 1 else { return nil }
        return Int(data[0])
    }

    // MARK: Apple Silicon legacy inhibit

    enum SiliconKeySet: Equatable {
        /// Older firmware: `CH0B` + `CH0C`, both ui8.
        case pairCH0BCH0C
        /// Tahoe-era firmware: `CHTE` ui32.
        case chte
    }

    /// Chooses the legacy inhibit key set strictly from key presence (fact:
    /// batt probes by key, not OS). Prefers the older pair; if either pair key
    /// is missing, falls back to `CHTE`, else nil.
    static func siliconKeySet(presentKeys: Set<String>) -> SiliconKeySet? {
        if presentKeys.contains(LegacySMCKeys.siliconCH0B),
           presentKeys.contains(LegacySMCKeys.siliconCH0C) {
            return .pairCH0BCH0C
        }
        if presentKeys.contains(LegacySMCKeys.siliconCHTE) {
            return .chte
        }
        return nil
    }

    /// Allowed = battery may charge. Pair keys: `0x00` each. `CHTE`: 4 zero
    /// value.
    static func siliconAllowCharging(for keySet: SiliconKeySet) -> [String: Data] {
        switch keySet {
        case .pairCH0BCH0C:
            return [
                LegacySMCKeys.siliconCH0B: Data([0x00]),
                LegacySMCKeys.siliconCH0C: Data([0x00]),
            ]
        case .chte:
            return [
                LegacySMCKeys.siliconCHTE: Data([0x00, 0x00, 0x00, 0x00]),
            ]
        }
    }

    /// Inhibit = battery must not charge. Pair keys: `0x02` each. `CHTE`:
    /// `0x01000000`.
    static func siliconInhibitCharging(for keySet: SiliconKeySet) -> [String: Data] {
        switch keySet {
        case .pairCH0BCH0C:
            return [
                LegacySMCKeys.siliconCH0B: Data([0x02]),
                LegacySMCKeys.siliconCH0C: Data([0x02]),
            ]
        case .chte:
            return [
                LegacySMCKeys.siliconCHTE: Data([0x01, 0x00, 0x00, 0x00]),
            ]
        }
    }

    /// Whether the observed bytes equal "allow charging" for a key set.
    static func siliconObservesChargingAllowed(_ data: Data, keySet: SiliconKeySet) -> Bool {
        switch keySet {
        case .pairCH0BCH0C:
            guard data.count == 1 else { return false }
            return data[0] == 0x00
        case .chte:
            return data == Data([0x00, 0x00, 0x00, 0x00])
        }
    }
}

/// Verifies that a requested limit is within the negotiated range and maps the
/// requested value to the concrete target tolerated by the backend.
enum LegacyChargeLimitValidator {
    static let minLimit = 80
    static let maxLimit = 100

    static func validatedLimit(_ limit: Int) -> Result<Int, LegacyChargeLimitError> {
        guard (minLimit...maxLimit).contains(limit) else {
            return .failure(.limitOutOfRange(limit))
        }
        return .success(limit)
    }

    /// Hysteresis gap between charging-enable and disable thresholds.
    static let hysteresis = 2
}