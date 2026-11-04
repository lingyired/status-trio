import XCTest
@testable import StatusTrioCore

/// Availability must be decided from OS band + runtime architecture + probe
/// facts, never from a private PowerUI capability. Rosetta on Apple Silicon
/// reports x86_64 but must not be treated as an Intel Mac.
final class LegacyChargeLimitAvailabilityTests: XCTestCase {
    private func probe(
        bclm: Bool = false,
        pair: Bool = false,
        chte: Bool = false,
        battery: Bool = true
    ) -> LegacyChargeLimitProbeFacts {
        LegacyChargeLimitProbeFacts(
            hasInternalBattery: battery,
            intelBCLMPresent: bclm,
            siliconPairPresent: pair,
            siliconCHTEPresent: chte
        )
    }

    func testIntelWithBCLMOnLegacyOSIsAvailable() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(bclm: true),
            architecture: .intel,
            osBand: .thirteenToFourteen,
            helperAvailable: true
        )
        XCTAssertEqual(availability, .available(.intelBCLM))
    }

    func testRosettaIsUnavailableEvenIfKeysLookIntel() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(bclm: true),
            architecture: .rosetta,
            osBand: .thirteenToFourteen,
            helperAvailable: true
        )
        XCTAssertEqual(availability, .unavailable(.rosetta))
    }

    func testAppleSiliconPairIsAvailableOnLegacyOS() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(pair: true),
            architecture: .appleSilicon,
            osBand: .thirteenToFourteen,
            helperAvailable: true
        )
        XCTAssertEqual(availability, .available(.siliconLegacyInhibit))
    }

    func testNativeTahoeReportsUnsupportedOSBeforeHelper() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(pair: true),
            architecture: .appleSilicon,
            osBand: .tahoe,
            helperAvailable: false
        )
        XCTAssertEqual(availability, .unavailable(.unsupportedOS))
    }

    func testNoInternalBatteryIsUnavailable() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(bclm: true, battery: false),
            architecture: .intel,
            osBand: .thirteenToFourteen,
            helperAvailable: true
        )
        XCTAssertEqual(availability, .unavailable(.noInternalBattery))
    }

    func testMissingHelperIsReportedSeparately() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(bclm: true),
            architecture: .intel,
            osBand: .thirteenToFourteen,
            helperAvailable: false
        )
        XCTAssertEqual(availability, .unavailable(.helperUnavailable))
    }

    func testNoSupportedKeysIsUnavailable() {
        let availability = LegacyChargeLimitAvailability.resolve(
            probe: probe(),
            architecture: .intel,
            osBand: .thirteenToFourteen,
            helperAvailable: true
        )
        XCTAssertEqual(availability, .unavailable(.noSupportedKeys))
    }

    func testMacOS15StillResolvesAvailability() {
        XCTAssertEqual(
            LegacyChargeLimitAvailability.resolve(
                probe: probe(bclm: true), architecture: .intel,
                osBand: .fifteen, helperAvailable: true
            ),
            .available(.intelBCLM)
        )
        XCTAssertEqual(
            LegacyChargeLimitAvailability.resolve(
                probe: probe(bclm: true), architecture: .intel,
                osBand: .sixteenToTahoeLegacy, helperAvailable: true
            ),
            .unavailable(.unsupportedOS)
        )
    }

    func testOSBandClassificationMatchesThePlanMatrix() {
        // 16-26.3 is explicitly out of this milestone, not "legacy".
        XCTAssertFalse(LegacyOSBand.sixteenToTahoeLegacy.allowsLegacyLimiter)
        XCTAssertTrue(LegacyOSBand.thirteenToFourteen.allowsLegacyLimiter)
        XCTAssertTrue(LegacyOSBand.fifteen.allowsLegacyLimiter,
                      "The legacy limiter covers macOS 13-15")
    }
}