import Foundation
import XCTest
@testable import StatusTrioCore

final class SingleInstanceGuardTests: XCTestCase {
    private let directBundleIdentifier = "com.lingsmbp.StatusTrio"
    private let storeBundleIdentifier = "com.lingsmbp.StatusTrio.AppStore"

    func testDefaultLockPathKeepsTheDirectHomeLocation() {
        let home = URL(fileURLWithPath: "/tmp/direct-home", isDirectory: true)
        let path = SingleInstanceGuard.defaultLockPath(
            for: .direct,
            bundleIdentifier: "com.lingsmbp.StatusTrio.dev.branch",
            homeDirectory: home,
            applicationSupportDirectory: { _ in
                XCTFail("Direct must not resolve the container-aware root")
                return URL(fileURLWithPath: "/tmp/unused", isDirectory: true)
            }
        )

        XCTAssertEqual(
            path,
            home
                .appendingPathComponent("Library/Application Support/StatusTrio", isDirectory: true)
                .appendingPathComponent("com.lingsmbp.StatusTrio.dev.branch.lock")
                .path
        )
    }

    func testDefaultLockPathUsesTheContainerRootOnlyForTheStoreChannel() {
        let containerRoot = URL(
            fileURLWithPath: "/tmp/container/Data/Library/Application Support",
            isDirectory: true
        )
        let path = SingleInstanceGuard.defaultLockPath(
            for: .appStore,
            bundleIdentifier: "com.lingsmbp.StatusTrio.AppStore",
            homeDirectory: URL(fileURLWithPath: "/tmp/ignored-home", isDirectory: true),
            applicationSupportDirectory: { directory in
                XCTAssertEqual(directory, .applicationSupportDirectory)
                return containerRoot
            }
        )

        XCTAssertEqual(
            path,
            containerRoot
                .appendingPathComponent("StatusTrio", isDirectory: true)
                .appendingPathComponent("com.lingsmbp.StatusTrio.AppStore.lock")
                .path
        )
    }

    func testStoreChannelWithoutContainerRootFailsClosedInsteadOfUsingHome() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let path = SingleInstanceGuard.defaultLockPath(
            for: .appStore,
            bundleIdentifier: "com.example.Store.Build",
            homeDirectory: home,
            applicationSupportDirectory: { _ in nil }
        )

        XCTAssertNil(path)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: home
                    .appendingPathComponent("Library/Application Support/StatusTrio")
                    .path
            ),
            "a missing Store support root must not create a home-relative lock"
        )

        let rejection = try XCTUnwrap(
            SingleInstanceGuard.acquireDefault(
                for: .appStore,
                bundleIdentifier: "com.example.Store.Build",
                homeDirectory: home,
                applicationSupportDirectory: { _ in nil }
            ).rejection
        )
        guard case .lockUnavailable(let reason) = rejection else {
            return XCTFail("expected .lockUnavailable, got \(rejection)")
        }
        XCTAssertTrue(reason.contains("Application Support"), reason)
        XCTAssertTrue(reason.contains("appStore"), reason)
    }

    func testDefaultLockPathUsesTheActualBundleIdentifierForEachChannel() throws {
        let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let support = URL(fileURLWithPath: "/tmp/support", isDirectory: true)

        let direct = try XCTUnwrap(SingleInstanceGuard.defaultLockPath(
            for: .direct,
            bundleIdentifier: "com.example.Dev.Build",
            homeDirectory: root,
            applicationSupportDirectory: { _ in support }
        ))
        let store = try XCTUnwrap(SingleInstanceGuard.defaultLockPath(
            for: .appStore,
            bundleIdentifier: "com.example.Store.Build",
            homeDirectory: root,
            applicationSupportDirectory: { _ in support }
        ))

        XCTAssertTrue(direct.hasSuffix("/com.example.Dev.Build.lock"))
        XCTAssertTrue(store.hasSuffix("/com.example.Store.Build.lock"))
        XCTAssertFalse(direct.contains("com.lingsmbp.StatusTrio.AppStore"))
        XCTAssertFalse(store.contains("com.lingsmbp.StatusTrio.dev"))
    }

    func testCurrentLockPathConsumesTheCompiledChannelAndActualBundleIdentifier() throws {
        let expected = SingleInstanceGuard.defaultLockPath(
            for: DistributionChannel.current,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

        XCTAssertEqual(SingleInstanceGuard.defaultLockPath, expected)
        XCTAssertTrue(
            try XCTUnwrap(expected).hasSuffix(
                "/" + SingleInstanceGuard.lockFileName(
                    for: Bundle.main.bundleIdentifier
                )
            )
        )
    }

    func testDifferentIdentitiesInTheSameTemporaryRootCanBothHoldTheLock() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let supportRoot = directory.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let directPath = try XCTUnwrap(SingleInstanceGuard.defaultLockPath(
            for: .direct,
            bundleIdentifier: directBundleIdentifier,
            homeDirectory: directory,
            applicationSupportDirectory: { _ in
                XCTFail("Direct path must not use the Store root")
                return supportRoot
            }
        ))
        let storePath = try XCTUnwrap(SingleInstanceGuard.defaultLockPath(
            for: .appStore,
            bundleIdentifier: storeBundleIdentifier,
            homeDirectory: directory,
            applicationSupportDirectory: { _ in supportRoot }
        ))

        let direct = try XCTUnwrap(SingleInstanceGuard.acquire(lockPath: directPath).instance)
        let store = try XCTUnwrap(SingleInstanceGuard.acquire(lockPath: storePath).instance)
        withExtendedLifetime((direct, store)) {
            XCTAssertNotEqual(directPath, storePath)
            XCTAssertEqual(
                URL(fileURLWithPath: directPath).deletingLastPathComponent(),
                URL(fileURLWithPath: storePath).deletingLastPathComponent()
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: directPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: storePath))
        }
    }

    func testSameIdentityRejectsSecondGuardAndReleasesForReacquisition() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = try XCTUnwrap(SingleInstanceGuard.defaultLockPath(
            for: .direct,
            bundleIdentifier: directBundleIdentifier,
            homeDirectory: directory,
            applicationSupportDirectory: { _ in directory }
        ))

        var first: SingleInstanceGuard? = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockPath).instance
        )
        withExtendedLifetime(first) {
            XCTAssertEqual(
                SingleInstanceGuard.acquire(lockPath: lockPath).rejection,
                .alreadyRunning
            )
        }

        first = nil
        let reacquired = try XCTUnwrap(
            SingleInstanceGuard.acquire(lockPath: lockPath).instance
        )
        withExtendedLifetime(reacquired) {}
    }

    func testDifferentDefaultsSuitesAreIsolatedAndTestDataIsRemoved() throws {
        let directSuite = "StatusTrio.Direct.\(UUID().uuidString)"
        let storeSuite = "StatusTrio.Store.\(UUID().uuidString)"
        let directDefaults = try XCTUnwrap(UserDefaults(suiteName: directSuite))
        let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeSuite))
        let removeTestData = {
            directDefaults.removePersistentDomain(forName: directSuite)
            storeDefaults.removePersistentDomain(forName: storeSuite)
        }
        defer { removeTestData() }
        let key = "dual-distribution.coexistence.probe"

        directDefaults.set("direct", forKey: key)
        storeDefaults.set("store", forKey: key)

        XCTAssertEqual(directDefaults.string(forKey: key), "direct")
        XCTAssertEqual(storeDefaults.string(forKey: key), "store")
        XCTAssertNotEqual(directDefaults.string(forKey: key), storeDefaults.string(forKey: key))

        removeTestData()
        XCTAssertNil(directDefaults.string(forKey: key))
        XCTAssertNil(storeDefaults.string(forKey: key))
    }

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
