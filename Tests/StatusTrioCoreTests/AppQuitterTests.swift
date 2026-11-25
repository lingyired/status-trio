import XCTest
@testable import StatusTrioCore

@MainActor
final class AppQuitterTests: XCTestCase {
    private func row(path: String, name: String = "Foo") -> TopAppRow {
        TopAppRow(id: .application(path: path), name: name, applicationPath: path, value: 10, upload: nil)
    }

    private func processRow(pid: Int32, startedAt: UInt64?, name: String = "Helper") -> TopAppRow {
        TopAppRow(id: .process(ProcessIdentity(pid: pid, startedAt: startedAt)),
                  name: name, applicationPath: nil, value: 5, upload: nil)
    }

    func testApplicationPathTargetMatchesEveryInstanceButSkipsSelfAndOwnBundle() {
        let running = [
            RunningAppInfo(pid: 100, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: false),
            RunningAppInfo(pid: 101, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: false),
            RunningAppInfo(pid: 200, path: "/Applications/Bar.app", bundleIdentifier: "com.bar", terminated: false),
            // Terminated instance must not be targeted.
            RunningAppInfo(pid: 300, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: true),
        ]
        let target = AppQuitter.target(
            forApplicationPath: "/Applications/Foo.app", name: "Foo",
            running: running, startTime: { UInt64($0) },
            selfPID: 999, selfBundleID: "com.me"
        )
        XCTAssertEqual(target?.displayName, "Foo")
        XCTAssertEqual(target?.pids, [100, 101])
        XCTAssertEqual(target?.startedAt, [100: 100, 101: 101])
    }

    func testApplicationPathTargetIsNilWhenNoLiveInstanceMatches() {
        let running = [
            RunningAppInfo(pid: 300, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: true),
        ]
        XCTAssertNil(AppQuitter.target(forApplicationPath: "/Applications/Foo.app", name: "Foo",
                                       running: running, selfPID: 999, selfBundleID: "com.me"))
    }

    func testCurrentAppIsNeverTargeted() {
        let running = [
            RunningAppInfo(pid: 42, path: "/Applications/Foo.app", bundleIdentifier: "com.me.self", terminated: false),
        ]
        // Same pid as Status Trio.
        XCTAssertNil(AppQuitter.target(forApplicationPath: "/Applications/Foo.app", name: "Foo",
                                       running: running, selfPID: 42, selfBundleID: "com.me.self"))
        // Same bundle id under a different pid.
        XCTAssertNil(AppQuitter.target(forApplicationPath: "/Applications/Foo.app", name: "Foo",
                                       running: running, selfPID: 7, selfBundleID: "com.me.self"))
    }

    func testProcessRowTargetsAnyLivePIDLikeStats() {
        // Even a bare process (no NSWorkspace app) is closable by PID, matching
        // Stats' kill-from-popup behaviour; system/root ones simply fail later.
        let target = AppQuitter.target(for: processRow(pid: 500, startedAt: 111),
                                       running: [], startTime: { _ in 111 }, selfPID: 1, selfBundleID: nil)
        XCTAssertEqual(target?.pids, [500])
    }

    func testProcessRowSkipsSelfAndInvalidPIDs() {
        XCTAssertNil(AppQuitter.target(for: processRow(pid: 1, startedAt: 111),
                                       running: [], startTime: { _ in 111 }, selfPID: 1, selfBundleID: nil))
        XCTAssertNil(AppQuitter.target(for: processRow(pid: 0, startedAt: nil),
                                       running: [], startTime: { _ in nil }, selfPID: 9, selfBundleID: nil))
    }

    func testProcessRowRejectsPIDReuseWhenStartTimeDiffers() {
        let running = [
            RunningAppInfo(pid: 300, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: false),
        ]
        XCTAssertNil(AppQuitter.target(for: processRow(pid: 300, startedAt: 111),
                                       running: running, startTime: { _ in 222 }, selfPID: 1, selfBundleID: nil))
    }

    func testForceQuitSignalsEveryVerifiedPIDAndReportsSuccess() {
        var signalled: [pid_t] = []
        let target = ForceQuitTarget(
            displayName: "Foo", pids: [10, 20], startedAt: [10: 1, 20: 2]
        )
        let ok = AppQuitter.forceQuit(
            target,
            terminate: { pid in signalled.append(pid); return true },
            startTime: { $0 == 10 ? 1 : 2 },
            selfPID: 99
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(signalled, [10, 20])
    }

    func testForceQuitReportsFailureWhenASignalFails() {
        let target = ForceQuitTarget(
            displayName: "Root Proc", pids: [10, 20], startedAt: [10: 1, 20: 2]
        )
        let ok = AppQuitter.forceQuit(
            target,
            terminate: { $0 != 20 },
            startTime: { $0 == 10 ? 1 : 2 },
            selfPID: 99
        )
        XCTAssertFalse(ok)
    }

    func testForceQuitNeverSignalsItself() {
        var signalled: [pid_t] = []
        let target = ForceQuitTarget(
            displayName: "Status Trio", pids: [5, 10], startedAt: [5: 1, 10: 2]
        )
        _ = AppQuitter.forceQuit(
            target,
            terminate: { pid in signalled.append(pid); return true },
            startTime: { $0 == 5 ? 1 : 2 },
            selfPID: 5
        )
        XCTAssertEqual(signalled, [10])
    }

    /// The row was resolved minutes before the confirmation: if the PID now
    /// belongs to another incarnation, skip that signal and report the batch.
    func testForceQuitSkipsAReusedPIDAndReportsFailure() {
        var signalled: [pid_t] = []
        let target = ForceQuitTarget(
            displayName: "Foo", pids: [10, 20], startedAt: [10: 1, 20: 2]
        )
        let ok = AppQuitter.forceQuit(
            target,
            terminate: { pid in signalled.append(pid); return true },
            startTime: { $0 == 10 ? 1 : 999 },
            selfPID: 99
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(signalled, [10], "the reused PID must never receive a signal")
    }

    /// An unreadable start time at signal time is unverifiable, not a match.
    func testForceQuitSkipsAPIDWhoseStartTimeCannotBeRead() {
        var signalled: [pid_t] = []
        let target = ForceQuitTarget(
            displayName: "Foo", pids: [10, 20], startedAt: [10: 1, 20: 2]
        )
        let ok = AppQuitter.forceQuit(
            target,
            terminate: { pid in signalled.append(pid); return true },
            startTime: { $0 == 10 ? 1 : nil },
            selfPID: 99
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(signalled, [10])
    }

    /// A target resolved without recorded identities cannot be verified at all.
    func testForceQuitRefusesAnUnverifiedTarget() {
        var signalled: [pid_t] = []
        let target = ForceQuitTarget(displayName: "Foo", pids: [10])
        let ok = AppQuitter.forceQuit(
            target,
            terminate: { pid in signalled.append(pid); return true },
            startTime: { _ in 1 },
            selfPID: 99
        )
        XCTAssertFalse(ok)
        XCTAssertTrue(signalled.isEmpty)
    }

    /// An app instance whose start time cannot be read is not targetable.
    func testApplicationPathDropsAnInstanceWithAnUnreadableStartTime() {
        let running = [
            RunningAppInfo(pid: 100, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: false),
            RunningAppInfo(pid: 101, path: "/Applications/Foo.app", bundleIdentifier: "com.foo", terminated: false),
        ]
        let target = AppQuitter.target(
            forApplicationPath: "/Applications/Foo.app", name: "Foo",
            running: running, startTime: { $0 == 101 ? nil : 5 },
            selfPID: 999, selfBundleID: "com.me"
        )
        XCTAssertEqual(target?.pids, [100])
        XCTAssertEqual(target?.startedAt, [100: 5])
    }
}

extension AppQuitterTests {
    /// A row can name an installed bundle whose *running* copy lives at a
    /// different path (CrossOver.app vs "CrossOver Preview.app"). The lookup
    /// must still resolve by bundle identifier so the row is selectable.
    func testApplicationPathFallsBackToBundleIdentifierWhenRunningCopyIsElsewhere() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foo-\(UUID().uuidString).app", isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.foo",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Foo",
            "CFBundleName": "Foo",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let running = [
            RunningAppInfo(pid: 700, path: "/Applications/Foo Preview.app",
                           bundleIdentifier: "com.example.foo", terminated: false),
        ]
        let target = AppQuitter.target(
            forApplicationPath: bundleURL.path, name: "Foo",
            running: running, startTime: { _ in 7000 },
            selfPID: 5, selfBundleID: "com.me"
        )
        XCTAssertEqual(target?.pids, [700])
        XCTAssertEqual(target?.startedAt, [700: 7000])
    }
}
