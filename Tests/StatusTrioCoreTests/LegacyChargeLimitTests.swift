import XCTest
@testable import StatusTrioCore

/// Phase 1 pure-model tests for the legacy charge limiter. These test the
/// domain policy with injected fakes and make no IOKit or real-hardware calls.
final class LegacyChargeLimitBackendSelectionTests: XCTestCase {
    private func caps(
        arch: LegacyRuntimeArchitecture,
        band: LegacyOSBand,
        battery: Bool = true,
        keys: Set<String> = [LegacySMCKeys.intelBCLM]
    ) -> LegacyHardwareCapabilities {
        LegacyHardwareCapabilities(
            architecture: arch,
            osBand: band,
            hasInternalBattery: battery,
            presentKeys: keys,
            verifiedWritableKeys: []
        )
    }

    func testIntelOnMacOS13SelectsBCLM() {
        let c = caps(arch: .intel, band: .thirteenToFourteen)
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .intelBCLM)
    }

    func testMacOS13Through15RemainInScope() {
        for band in [LegacyOSBand.thirteenToFourteen, .fifteen] {
            XCTAssertTrue(band.allowsLegacyLimiter)
            XCTAssertEqual(
                LegacyChargeBackend.select(using: caps(arch: .intel, band: band)),
                .intelBCLM
            )
            XCTAssertEqual(
                LegacyChargeBackend.select(using: caps(
                    arch: .appleSilicon, band: band,
                    keys: [LegacySMCKeys.siliconCH0B, LegacySMCKeys.siliconCH0C]
                )),
                .siliconLegacyInhibit
            )
        }
    }

    func testIntelBCLMKeyAbsentIsUnsupported() {
        let c = caps(arch: .intel, band: .thirteenToFourteen, keys: [])
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }

    func testAppleSiliconOnMacOS14SelectsInhibit() {
        let c = caps(
            arch: .appleSilicon,
            band: .thirteenToFourteen,
            keys: [LegacySMCKeys.siliconCH0B, LegacySMCKeys.siliconCH0C]
        )
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .siliconLegacyInhibit)
    }

    func testRosettaIsUnsupported() {
        let c = caps(arch: .rosetta, band: .thirteenToFourteen, keys: [])
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }

    func testUnsupportedArchitecture() {
        let c = caps(arch: .unsupported, band: .thirteenToFourteen, keys: [])
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }

    func testNoBatteryIsUnsupported() {
        let c = caps(arch: .intel, band: .thirteenToFourteen, battery: false)
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }

    func testMacOS16To263IsNotInMilestone() {
        let c = caps(arch: .appleSilicon, band: .sixteenToTahoeLegacy)
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }

    func testMacOS264NativeUsesExistingPath() {
        // Legacy backend must not be chosen on 26.4+; the native PowerUI
        // controller owns it. Even with silicon keys present, we return
        // unsupported for the *legacy* backend.
        let c = caps(
            arch: .appleSilicon,
            band: .tahoe,
            keys: [LegacySMCKeys.siliconCH0B, LegacySMCKeys.siliconCH0C]
        )
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }

    func testUnknownBandIsUnsupported() {
        let c = caps(arch: .intel, band: .unknown)
        XCTAssertEqual(LegacyChargeBackend.select(using: c), .unsupported)
    }
}

final class LegacyOSBandTests: XCTestCase {
    private func v(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    func testBands() {
        XCTAssertEqual(LegacyOSBandFactor.band(v(13, 0)), .thirteenToFourteen)
        XCTAssertEqual(LegacyOSBandFactor.band(v(14, 6)), .thirteenToFourteen)
        XCTAssertEqual(LegacyOSBandFactor.band(v(15, 1)), .fifteen)
        XCTAssertEqual(LegacyOSBandFactor.band(v(16, 0)), .sixteenToTahoeLegacy)
        XCTAssertEqual(LegacyOSBandFactor.band(v(26, 0)), .sixteenToTahoeLegacy)
        XCTAssertEqual(LegacyOSBandFactor.band(v(26, 4)), .tahoe)
        XCTAssertEqual(LegacyOSBandFactor.band(v(27, 2)), .tahoe)
        XCTAssertEqual(LegacyOSBandFactor.band(v(12, 0)), .unknown)
    }
}

final class LegacyChargeLimitValidatorTests: XCTestCase {
    func testValidRange() {
        for limit in 80...100 {
            XCTAssertEqual(LegacyChargeLimitValidator.validatedLimit(limit), .success(limit))
        }
    }

    func testOutOfRangeFails() {
        XCTAssertEqual(LegacyChargeLimitValidator.validatedLimit(79), .failure(.limitOutOfRange(79)))
        XCTAssertEqual(LegacyChargeLimitValidator.validatedLimit(101), .failure(.limitOutOfRange(101)))
        XCTAssertEqual(LegacyChargeLimitValidator.validatedLimit(0), .failure(.limitOutOfRange(0)))
    }

    func testHysteresis() {
        XCTAssertEqual(LegacyChargeLimitValidator.hysteresis, 4)
    }
}

final class LegacySMCBytePolicyTests: XCTestCase {
    func testIntelBCLMEncodeDecode() {
        let encoded = LegacySMCBytePolicy.intelBCLMWriteBytes(forLimit: 80)
        XCTAssertEqual(encoded, Data([80]))
        XCTAssertEqual(LegacySMCBytePolicy.intelBCLMReadValue(from: encoded), 80)

        let full = LegacySMCBytePolicy.intelBCLMWriteBytes(forLimit: 100)
        XCTAssertEqual(full, Data([100]))
        XCTAssertEqual(LegacySMCBytePolicy.intelBCLMReadValue(from: full), 100)
    }

    func testIntelBCLMWrongWidthIsNil() {
        XCTAssertNil(LegacySMCBytePolicy.intelBCLMReadValue(from: Data([0, 0])))
        XCTAssertNil(LegacySMCBytePolicy.intelBCLMReadValue(from: Data()))
    }

    func testSiliconKeySetPreference() {
        let both = Set([LegacySMCKeys.siliconCH0B, LegacySMCKeys.siliconCH0C])
        XCTAssertEqual(LegacySMCBytePolicy.siliconKeySet(presentKeys: both), .pairCH0BCH0C)

        let chteOnly = Set([LegacySMCKeys.siliconCHTE])
        XCTAssertEqual(LegacySMCBytePolicy.siliconKeySet(presentKeys: chteOnly), .chte)

        // Both pair AND chte: pair wins per firmware-first preference.
        var bothAndChte = both
        bothAndChte.insert(LegacySMCKeys.siliconCHTE)
        XCTAssertEqual(LegacySMCBytePolicy.siliconKeySet(presentKeys: bothAndChte), .pairCH0BCH0C)

        // Neither present.
        XCTAssertNil(LegacySMCBytePolicy.siliconKeySet(presentKeys: Set()))
    }

    func testSiliconAllowChargingBytes() {
        let allowPair = LegacySMCBytePolicy.siliconAllowCharging(for: .pairCH0BCH0C)
        XCTAssertEqual(allowPair[LegacySMCKeys.siliconCH0B], Data([0x00]))
        XCTAssertEqual(allowPair[LegacySMCKeys.siliconCH0C], Data([0x00]))

        let allowChte = LegacySMCBytePolicy.siliconAllowCharging(for: .chte)
        XCTAssertEqual(allowChte[LegacySMCKeys.siliconCHTE], Data([0, 0, 0, 0]))
    }

    func testSiliconInhibitChargingBytes() {
        let inhibitPair = LegacySMCBytePolicy.siliconInhibitCharging(for: .pairCH0BCH0C)
        XCTAssertEqual(inhibitPair[LegacySMCKeys.siliconCH0B], Data([0x02]))
        XCTAssertEqual(inhibitPair[LegacySMCKeys.siliconCH0C], Data([0x02]))

        let inhibitChte = LegacySMCBytePolicy.siliconInhibitCharging(for: .chte)
        XCTAssertEqual(inhibitChte[LegacySMCKeys.siliconCHTE], Data([0x01, 0, 0, 0]))
    }

    func testSiliconObservesChargingAllowed() {
        XCTAssertTrue(LegacySMCBytePolicy.siliconObservesChargingAllowed(Data([0x00]), keySet: .pairCH0BCH0C))
        XCTAssertFalse(LegacySMCBytePolicy.siliconObservesChargingAllowed(Data([0x02]), keySet: .pairCH0BCH0C))
        XCTAssertTrue(LegacySMCBytePolicy.siliconObservesChargingAllowed(Data([0, 0, 0, 0]), keySet: .chte))
        XCTAssertFalse(LegacySMCBytePolicy.siliconObservesChargingAllowed(Data([0x01, 0, 0, 0]), keySet: .chte))
    }
}

final class LegacySessionTests: XCTestCase {
    @MainActor
    func testVolatileStore() {
        let store = VolatileLegacyChargeLimitSessionStore()
        XCTAssertNil(store.load())
        let s = LegacyChargeLimitSession(requestedLimit: 90, originalLimit: 100)
        store.save(s)
        XCTAssertEqual(store.load()?.requestedLimit, 90)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testValidity() {
        XCTAssertTrue(LegacyChargeLimitSession(requestedLimit: 80, originalLimit: nil).isValid)
        XCTAssertTrue(LegacyChargeLimitSession(requestedLimit: 100, originalLimit: 100).isValid)
        XCTAssertFalse(LegacyChargeLimitSession(requestedLimit: 79, originalLimit: nil).isValid)
    }
}

/// Sleep policy is a pure decision; the IOKit assertion only applies it.
final class LegacySleepPolicyTests: XCTestCase {
    func testPauseChargingNeverHoldsAwake() {
        for level in [10, 60, 84, 100] {
            XCTAssertFalse(LegacySleepPolicy.shouldStayAwake(
                level: level, target: 85, isOnAC: true, hasSession: true, policy: .pauseCharging))
        }
    }

    func testKeepAwakeUntilLimitWhileBelowTheCeilingOnAC() {
        XCTAssertTrue(LegacySleepPolicy.shouldStayAwake(
            level: 60, target: 85, isOnAC: true, hasSession: true, policy: .keepAwakeUntilLimit))
        XCTAssertFalse(LegacySleepPolicy.shouldStayAwake(
            level: 85, target: 85, isOnAC: true, hasSession: true, policy: .keepAwakeUntilLimit))
        XCTAssertFalse(LegacySleepPolicy.shouldStayAwake(
            level: 60, target: 85, isOnAC: false, hasSession: true, policy: .keepAwakeUntilLimit),
            "On battery there is nothing to charge")
        XCTAssertFalse(LegacySleepPolicy.shouldStayAwake(
            level: 60, target: 85, isOnAC: true, hasSession: false, policy: .keepAwakeUntilLimit))
    }
}
