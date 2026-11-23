import Foundation
import XCTest
@testable import StatusTrioCore

final class SingleInstanceGuardTests: XCTestCase {
    func testLockFileNameIsScopedByBundleIdentifier() {
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: "com.example.StatusTrio"),
            "com.example.StatusTrio.lock"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: "com.example/Status Trio"),
            "com.example_Status_Trio.lock"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: nil),
            "com.lingsmbp.StatusTrio.lock"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: "  "),
            "com.lingsmbp.StatusTrio.lock"
        )
    }

    func testSecondGuardCannotAcquireUntilFirstIsReleased() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        var first: SingleInstanceGuard? = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockPath).instance
        )
        withExtendedLifetime(first) {}
        XCTAssertNil(SingleInstanceGuard.acquire(lockPath: lockPath).instance)

        first = nil
        let second = try XCTUnwrap(SingleInstanceGuard.acquire(lockPath: lockPath).instance)
        withExtendedLifetime(second) {}
    }

    /// M-5: a second instance is reported as such, not as a broken lock.
    func testAlreadyRunningIsReportedSeparatelyFromAnUnusableLock() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        var first: SingleInstanceGuard? = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockPath).instance
        )
        withExtendedLifetime(first) {}

        XCTAssertEqual(
            SingleInstanceGuard.acquire(lockPath: lockPath).rejection,
            .alreadyRunning
        )

        first = nil
    }

    /// M-5: an unusable lock directory stays diagnosable and does not read as
    /// "another instance is running".
    func testUnusableLockDirectoryIsReportedWithAReason() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A regular file where a directory is required makes
        // `createDirectory` fail with ENOTDIR.
        let blocker = directory.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let lockPath = blocker
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("StatusTrio.lock")
            .path

        let rejection = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockPath).rejection
        )
        guard case .lockUnavailable(let reason) = rejection else {
            return XCTFail("expected .lockUnavailable, got \(rejection)")
        }
        XCTAssertTrue(
            reason.contains(blocker.path),
            "the reason should name the unresolvable directory: \(reason)"
        )
        XCTAssertNotEqual(rejection, .alreadyRunning)
    }

    /// M-5: a lock file that exists but cannot be opened is also distinguishable
    /// from a second instance.
    func testUnopenableLockFileIsReportedWithAReason() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // The lock path is itself a directory, so `open(O_RDWR)` fails with
        // EISDIR after the parent directory was created successfully.
        let lockURL = directory.appendingPathComponent("StatusTrio.lock", isDirectory: true)
        try FileManager.default.createDirectory(
            at: lockURL,
            withIntermediateDirectories: true
        )

        let rejection = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockURL.path).rejection
        )
        guard case .lockUnavailable(let reason) = rejection else {
            return XCTFail("expected .lockUnavailable, got \(rejection)")
        }
        XCTAssertTrue(reason.contains("open("), "unexpected reason: \(reason)")
        XCTAssertNotEqual(rejection, .alreadyRunning)
    }

    func testSubprocessCannotAcquireLockUntilOwnerReleasesIt() throws {
        let pythonPath = "/usr/bin/python3"
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: pythonPath),
            "python3 is unavailable for the cross-process flock test"
        )

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        var first: SingleInstanceGuard? = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockPath).instance
        )
        withExtendedLifetime(first) {}
        XCTAssertEqual(
            try runFlockHelper(pythonPath: pythonPath, lockPath: lockPath),
            3
        )

        first = nil
        XCTAssertEqual(
            try runFlockHelper(pythonPath: pythonPath, lockPath: lockPath),
            0
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func runFlockHelper(pythonPath: String, lockPath: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-c",
            """
            import fcntl
            import os
            import sys

            fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                os.close(fd)
                sys.exit(3)
            os.close(fd)
            sys.exit(0)
            """,
            lockPath
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(decoding: outputData, as: UTF8.self)

        XCTAssertEqual(process.terminationReason, .exit, outputText)
        XCTAssertTrue([0, 3].contains(process.terminationStatus), outputText)
        return process.terminationStatus
    }
}
