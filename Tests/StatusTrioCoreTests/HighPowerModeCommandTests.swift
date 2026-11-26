import XCTest
@testable import PowerHelperProtocol

final class HighPowerModeCommandTests: XCTestCase {
    func testArgumentsUseTheUnifiedKeyOnMacOS26AndLater() {
        // High Power Mode is system-wide, so the write has to use `-a` like the
        // Low Power Mode write instead of only the active profile. macOS 26
        // unified the switch: `powermode 2` is High, `0` is Automatic.
        XCTAssertEqual(
            HighPowerModeCommand.arguments(enabled: true, usesUnifiedPowerModeKey: true),
            ["-a", "powermode", "2"]
        )
        XCTAssertEqual(
            HighPowerModeCommand.arguments(enabled: false, usesUnifiedPowerModeKey: true),
            ["-a", "powermode", "0"]
        )
    }

    func testArgumentsUseTheDedicatedHighPowerKeyBeforeMacOS26() {
        // Before macOS 26 the dedicated `highpowermode` key is the write key:
        // `1` is High, `0` returns to Automatic.
        XCTAssertEqual(
            HighPowerModeCommand.arguments(enabled: true, usesUnifiedPowerModeKey: false),
            ["-a", "highpowermode", "1"]
        )
        XCTAssertEqual(
            HighPowerModeCommand.arguments(enabled: false, usesUnifiedPowerModeKey: false),
            ["-a", "highpowermode", "0"]
        )
    }

    func testCapabilityProbeReadsTheCapabilityList() {
        let output = """
        Capabilities for AC Power:
         displaysleep
         lowpowermode
         highpowermode
        """
        XCTAssertTrue(HighPowerModeCommand.isSupported(fromCapabilitiesOutput: output))
    }

    func testCapabilityProbeIsFalseWhenTheKeyIsMissing() {
        // A Mac without High Power Mode support simply does not list the key.
        // That has to be "unsupported", not "unknown", so the control is hidden.
        let output = """
        Capabilities for AC Power:
         displaysleep
         lowpowermode
        """
        XCTAssertFalse(HighPowerModeCommand.isSupported(fromCapabilitiesOutput: output))
        XCTAssertFalse(HighPowerModeCommand.isSupported(fromCapabilitiesOutput: ""))
    }

    func testParserReadsTheUnifiedHighPowerValue() {
        // macOS 26+ prints the unified `powermode` key: 2 is High Power.
        let output = """
        Battery Power:
         powermode            2
        AC Power:
         powermode            2
        """
        XCTAssertEqual(HighPowerModeCommand.parseEnabled(fromPmsetOutput: output), true)
    }

    func testParserTreatsAutomaticAndLowPowerAsHighPowerOff() {
        // 0 is Automatic and 1 is Low Power; neither means High Power.
        XCTAssertEqual(
            HighPowerModeCommand.parseEnabled(fromPmsetOutput: " powermode            0"),
            false
        )
        XCTAssertEqual(
            HighPowerModeCommand.parseEnabled(fromPmsetOutput: " powermode            1"),
            false
        )
    }

    func testParserReadsTheLegacyHighPowerKey() {
        XCTAssertEqual(
            HighPowerModeCommand.parseEnabled(fromPmsetOutput: " highpowermode        1"),
            true
        )
    }

    func testParserReturnsNilWithoutAnyPowerModeKey() {
        // Unknown must stay unknown: reporting "off" would let the app write
        // over a mode it never observed.
        XCTAssertNil(
            HighPowerModeCommand.parseEnabled(
                fromPmsetOutput: """
                 displaysleep         2
                 sleep                1
                """
            )
        )
    }
}
