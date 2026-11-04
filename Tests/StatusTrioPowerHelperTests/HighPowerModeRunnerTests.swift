import Foundation
import XCTest
@testable import PowerHelperProtocol
@testable import StatusTrioPowerHelper

/// The daemon side of the #235 contract: version handshake, capability probe,
/// and mutual exclusion between the two power modes.
final class HighPowerModeRunnerTests: XCTestCase {
    func testCapabilityProbeReadsPmsetCapabilities() async throws {
        let script = try makeScript(
            """
            printf 'Capabilities for AC Power:\\n displaysleep\\n highpowermode\\n'
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        let supported = await runner.highPowerModeSupported()
        XCTAssertEqual(supported, true)
    }

    func testCapabilityProbeIsFalseWhenPmsetDoesNotListHighPowerMode() async throws {
        let script = try makeScript(
            """
            printf 'Capabilities for AC Power:\\n displaysleep\\n lowpowermode\\n'
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        let supported = await runner.highPowerModeSupported()
        XCTAssertEqual(supported, false)
    }

    func testCurrentHighPowerModeParsesTheUnifiedValue() async throws {
        let script = try makeScript(
            """
            printf 'Battery Power:\\n powermode            2\\n'
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        let enabled = await runner.currentHighPowerMode()
        XCTAssertEqual(enabled, true)
    }

    func testEnablingHighPowerModeClearsLowPowerModeFirst() async throws {
        // The two modes are mutually exclusive states of one system switch, so
        // the write order matters. The script records its arguments so the test
        // asserts the order instead of only the final state.
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-args-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let script = try makeScript(
            """
            printf '%s\\n' "$*" >> '\(log.path)'
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        try await runner.setHighPowerMode(enabled: true)

        let lines = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines, ["-a lowpowermode 0", "-a powermode 2"])
    }

    func testDisablingHighPowerModeWritesOnlyTheHighModeOff() async throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-args-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let script = try makeScript(
            """
            printf '%s\\n' "$*" >> '\(log.path)'
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        try await runner.setHighPowerMode(enabled: false)

        let lines = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines, ["-a powermode 0"])
    }

    func testEnablingLowPowerModeClearsHighPowerModeFirst() async throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-args-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let script = try makeScript("printf '%s\\n' \"$*\" >> '\(log.path)'")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)
        try await runner.setLowPowerMode(enabled: true)
        let lines = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["-a powermode 0", "-a lowpowermode 1"])
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-runner-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

/// The XPC reply surface, exercised without root by injecting a runner.
final class PowerModeServiceHighPowerReplyTests: XCTestCase {
    func testReadProtocolVersionReportsTheCurrentVersion() {
        let service = PowerModeService(runner: StaticHighPowerRunner())
        let replied = expectation(description: "reply arrives")

        service.readProtocolVersion { version, errorDescription in
            XCTAssertEqual(version, PowerHelperProtocolVersion.current)
            XCTAssertNil(errorDescription)
            replied.fulfill()
        }

        wait(for: [replied], timeout: 2)
    }

    func testReadHighPowerModeSupportRepliesWithTheCapability() {
        let service = PowerModeService(runner: StaticHighPowerRunner(supported: true))
        let replied = expectation(description: "reply arrives")

        service.readHighPowerModeSupport { supported, errorDescription in
            XCTAssertTrue(supported)
            XCTAssertNil(errorDescription)
            replied.fulfill()
        }

        wait(for: [replied], timeout: 2)
    }

    func testReadHighPowerModeRepliesWithTheObservedState() {
        let runner = StaticHighPowerRunner()
        runner.highEnabled = true
        let service = PowerModeService(runner: runner)
        let replied = expectation(description: "reply arrives")

        service.readHighPowerMode { enabled, errorDescription in
            XCTAssertTrue(enabled)
            XCTAssertNil(errorDescription)
            replied.fulfill()
        }

        wait(for: [replied], timeout: 2)
    }

    func testSetHighPowerModeRepliesWithTheStateAfterTheChange() {
        let runner = StaticHighPowerRunner()
        let service = PowerModeService(runner: runner)
        let replied = expectation(description: "reply arrives")

        service.setHighPowerMode(true) { enabled, errorDescription in
            XCTAssertTrue(enabled)
            XCTAssertNil(errorDescription)
            replied.fulfill()
        }

        wait(for: [replied], timeout: 2)
        XCTAssertTrue(runner.highEnabled)
    }
}

private final class StaticHighPowerRunner: PmsetRunning, @unchecked Sendable {
    var supported: Bool?
    private let lock = NSLock()
    private var _highEnabled = false

    var highEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _highEnabled }
        set { lock.lock(); defer { lock.unlock() }; _highEnabled = newValue }
    }

    init(supported: Bool? = true) {
        self.supported = supported
    }

    func setLowPowerMode(enabled: Bool) async throws {}

    func currentLowPowerMode() async -> Bool? { false }

    func highPowerModeSupported() async -> Bool? { supported }

    func setHighPowerMode(enabled: Bool) async throws {
        highEnabled = enabled
    }

    func currentHighPowerMode() async -> Bool? {
        highEnabled
    }
}
