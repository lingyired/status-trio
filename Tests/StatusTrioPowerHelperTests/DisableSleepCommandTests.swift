import Foundation
import XCTest
@testable import PowerHelperProtocol
@testable import StatusTrioPowerHelper

final class DisableSleepCommandTests: XCTestCase {
    func testArgumentsEnableAndDisable() {
        XCTAssertEqual(DisableSleepCommand.arguments(enabled: true), ["-a", "disablesleep", "1"])
        XCTAssertEqual(DisableSleepCommand.arguments(enabled: false), ["-a", "disablesleep", "0"])
    }

    func testParseSleepDisabledReadsTabSeparatedTrue() {
        XCTAssertEqual(DisableSleepCommand.parseSleepDisabled(fromPmsetOutput: " SleepDisabled\t\t1"), true)
    }

    func testParseSleepDisabledReadsSpaceSeparatedFalse() {
        XCTAssertEqual(DisableSleepCommand.parseSleepDisabled(fromPmsetOutput: " SleepDisabled 0"), false)
    }

    func testParseSleepDisabledReadsWithoutLeadingSpace() {
        XCTAssertEqual(DisableSleepCommand.parseSleepDisabled(fromPmsetOutput: "SleepDisabled 1"), true)
    }

    func testParseSleepDisabledReturnsNilWhenAbsent() {
        XCTAssertNil(DisableSleepCommand.parseSleepDisabled(fromPmsetOutput: "Battery Power:\n lowpowermode 0"))
        XCTAssertNil(DisableSleepCommand.parseSleepDisabled(fromPmsetOutput: ""))
    }

    func testRunnerReadsSleepDisabledAndWritesWithoutThrowing() async throws {
        let script = try makeScript("printf ' SleepDisabled\\t\\t1\\n'")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        let enabled = await runner.currentDisableSleep()
        XCTAssertEqual(enabled, true)

        try await runner.setDisableSleep(enabled: true)
    }

    func testClientWaitsLongerThanTheDaemonForOneCommand() {
        // Two bounded 1s pipe drains can follow the process wait, so the app's
        // XPC wait must clear that sum or it times out before the daemon's
        // precise code arrives (#383).
        XCTAssertGreaterThan(
            PowerHelperTiming.clientRequestTimeout,
            PowerHelperTiming.pmsetProcessTimeout + 2
        )
    }

    func testDiagnosticDecodeSplitsCodeAndDetail() {
        let coded = DisableSleepDiagnostic.decode("DS-R4: SleepDisabled not found")
        XCTAssertEqual(coded.code, .readKeyMissing)
        XCTAssertEqual(coded.detail, "SleepDisabled not found")
        XCTAssertEqual(DisableSleepDiagnostic.decode("DS-R2").code, .readPmsetTimedOut)

        let legacy = DisableSleepDiagnostic.decode("Disable sleep state is unavailable.")
        XCTAssertNil(legacy.code)
        XCTAssertEqual(legacy.detail, "Disable sleep state is unavailable.")
        XCTAssertNil(DisableSleepDiagnostic.decode(nil).code)
    }

    func testDiagnosticWireStringRoundTrips() {
        XCTAssertEqual(DisableSleepDiagnostic.readKeyMissing.wireString(detail: " x "), "DS-R4: x")
        XCTAssertEqual(DisableSleepDiagnostic.readPmsetTimedOut.wireString(), "DS-R2")
        let decoded = DisableSleepDiagnostic.decode(
            DisableSleepDiagnostic.writePmsetNonZeroExit.wireString(detail: "Unsupported mode 3")
        )
        XCTAssertEqual(decoded.code, .writePmsetNonZeroExit)
        XCTAssertEqual(decoded.detail, "Unsupported mode 3")
    }

    func testParseSleepDisabledDiagnosedDistinguishesMissingAndBadValue() {
        XCTAssertEqual(
            DisableSleepCommand.parseSleepDisabledDiagnosed(fromPmsetOutput: " SleepDisabled\t\t1"),
            .value(true)
        )
        XCTAssertEqual(
            DisableSleepCommand.parseSleepDisabledDiagnosed(
                fromPmsetOutput: "Battery Power:\n lowpowermode 0"
            ),
            .keyMissing
        )
        XCTAssertEqual(
            DisableSleepCommand.parseSleepDisabledDiagnosed(fromPmsetOutput: " SleepDisabled yes"),
            .unparseable("yes")
        )
    }

    func testRunnerReportsPreciseReadFailureCodes() async throws {
        let missing = try makeScript("printf 'Battery Power:\\n lowpowermode 0\\n'")
        defer { try? FileManager.default.removeItem(at: missing) }
        let missingRunner = SystemPmsetRunner(timeout: .seconds(15), executableURL: missing)
        // A `pmset -g` with no `SleepDisabled` line means the setting was never
        // used, which is off — not a read failure (#383 follow-up). Previously
        // this surfaced as DS-R4 on Macs that had never run `disablesleep`.
        let missingResult = await missingRunner.readDisableSleepDiagnosed()
        XCTAssertEqual(missingResult, .value(false))

        let badValue = try makeScript("printf ' SleepDisabled\\t\\tyes\\n'")
        defer { try? FileManager.default.removeItem(at: badValue) }
        let badRunner = SystemPmsetRunner(timeout: .seconds(15), executableURL: badValue)
        guard case let .failure(badCode, _) = await badRunner.readDisableSleepDiagnosed() else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(badCode, .readValueUnparseable)

        let nonZero = try makeScript("echo boom >&2\nexit 7")
        defer { try? FileManager.default.removeItem(at: nonZero) }
        let nonZeroRunner = SystemPmsetRunner(timeout: .seconds(15), executableURL: nonZero)
        guard case let .failure(exitCode, detail) = await nonZeroRunner.readDisableSleepDiagnosed() else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(exitCode, .readPmsetNonZeroExit)
        XCTAssertTrue(detail.contains("boom"))
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-runner-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
