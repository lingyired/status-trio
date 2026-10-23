import Foundation
import XCTest
@testable import StatusTrioPowerHelper

final class SystemPmsetRunnerTests: XCTestCase {
    func testRunKillsAChildThatOutlivesTheTimeout() async throws {
        // `pmset` can wedge on a power-management call. The daemon serves every
        // request on one XPC queue, so the run has to fail at its deadline
        // instead of waiting for the child.
        let script = try makeScript("sleep 30")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .milliseconds(300), executableURL: script)
        let clock = ContinuousClock()
        let started = clock.now

        do {
            try await runner.setLowPowerMode(enabled: true)
            XCTFail("a child that never exits must be reported as a timeout")
        } catch {
            guard case .timedOut = error as? PmsetError else {
                return XCTFail("expected a timeout, got \(error)")
            }
            // The 300ms deadline is what matters; this ceiling only has to
            // separate it from the 30-second sleep the child asked for, so it
            // stays loose enough for a loaded test machine.
            XCTAssertLessThan(clock.now - started, .seconds(10))
        }
    }

    func testCurrentLowPowerModeReadsStdoutAfterTheChildExits() async throws {
        let script = try makeScript("printf ' lowpowermode         1\\n'")
        defer { try? FileManager.default.removeItem(at: script) }
        // The deadline is not what this test asserts, and a shell start under a
        // fully parallel test run has been seen to exceed two seconds, so the
        // budget is deliberately generous.
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        let enabled = await runner.currentLowPowerMode()

        XCTAssertEqual(enabled, true)
    }

    func testNonZeroExitIsReportedAsAFailure() async throws {
        let script = try makeScript("echo nope >&2\nexit 17")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemPmsetRunner(timeout: .seconds(15), executableURL: script)

        do {
            try await runner.setLowPowerMode(enabled: false)
            XCTFail("a non-zero exit must fail")
        } catch {
            guard case .nonZeroExit(let code) = error as? PmsetError else {
                return XCTFail("expected a non-zero exit, got \(error)")
            }
            XCTAssertEqual(code, 17)
        }
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pmset-runner-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

final class PowerModeServiceReplyTests: XCTestCase {
    func testReadRepliesWithoutHoldingTheCaller() {
        let runner = DelayedPmsetRunner(enabled: true, delay: .milliseconds(50))
        let service = PowerModeService(runner: runner)
        let replied = expectation(description: "reply arrives")

        service.readLowPowerMode { enabled, errorDescription in
            XCTAssertTrue(enabled)
            XCTAssertNil(errorDescription)
            replied.fulfill()
        }

        // The exported method returned before the runner finished, so the
        // daemon's XPC queue is free while `pmset` runs.
        wait(for: [replied], timeout: 2)
    }

    func testWriteRepliesWithTheObservedStateAfterTheChange() {
        let runner = DelayedPmsetRunner(enabled: true, delay: .milliseconds(20))
        let service = PowerModeService(runner: runner)
        let replied = expectation(description: "reply arrives")

        service.setLowPowerMode(false) { enabled, errorDescription in
            XCTAssertFalse(enabled, "the reply carries the state pmset reports, not the request")
            XCTAssertNil(errorDescription)
            replied.fulfill()
        }

        wait(for: [replied], timeout: 2)
    }
}

private struct DelayedPmsetRunner: PmsetRunning {
    let enabled: Bool
    let delay: Duration
    /// Set once the "write" has been applied, so a read after a write reports
    /// the new state the way `pmset -g` would.
    private let applied = AppliedFlag()

    func setLowPowerMode(enabled: Bool) async throws {
        try? await Task.sleep(for: delay)
        applied.set(enabled)
    }

    func currentLowPowerMode() async -> Bool? {
        try? await Task.sleep(for: delay)
        return applied.value ?? enabled
    }
}

private final class AppliedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?

    var value: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Bool) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}
