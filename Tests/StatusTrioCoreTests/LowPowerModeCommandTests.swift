import XCTest
@testable import PowerHelperProtocol

final class LowPowerModeCommandTests: XCTestCase {
    func testArgumentsApplyToEveryPowerProfile() {
        // `-a` matches the system switch, which flips Low Power Mode for both
        // the battery and charger profiles rather than only the active one.
        XCTAssertEqual(LowPowerModeCommand.arguments(enabled: true), ["-a", "lowpowermode", "1"])
        XCTAssertEqual(LowPowerModeCommand.arguments(enabled: false), ["-a", "lowpowermode", "0"])
    }

    func testParserReadsTheClassicLowPowerKey() {
        let output = """
        Currently in use:
         lowpowermode         1
         displaysleep         2
        """
        XCTAssertEqual(LowPowerModeCommand.parseEnabled(fromPmsetOutput: output), true)
    }

    func testParserReadsTheUnifiedPowerModeKey() {
        // macOS 26+ prints `powermode` instead of `lowpowermode`; 1 is Low Power.
        let output = """
        Battery Power:
         powermode            1
        AC Power:
         powermode            0
        """
        XCTAssertEqual(LowPowerModeCommand.parseEnabled(fromPmsetOutput: output), true)
    }

    func testParserReturnsNilWhenNeitherKeyIsPresent() {
        let output = """
        Currently in use:
         displaysleep         2
         sleep                1
        """
        XCTAssertNil(LowPowerModeCommand.parseEnabled(fromPmsetOutput: output))
    }
}
