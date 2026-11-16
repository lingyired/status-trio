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

    private func makeScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-runner-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
