import Darwin
import Foundation
import Testing
@testable import StatusTrioCore

/// The shared runner reads both pipes again after the child is gone, then drains
/// them to EOF. `main` gained that in #131 because a helper report arrived
/// truncated: the tail of a JSON payload is not a status code, so losing it
/// surfaces as a decode failure three layers away from the cause, and nothing
/// about it looks like a timing bug.
///
/// The fixture that provokes it is the one a real helper produces by accident: a
/// child that writes its report and exits while a descendant still holds the
/// inherited write ends. The payload is larger than a pipe buffer, so it cannot
/// be sitting in the pipe by luck when the child exits - it has to be read, and
/// the descendant only releases the pipe when this test says so. No fixed sleeps:
/// the test waits on the child's exit (via `kill(pid, 0)`) and then signals the
/// descendant through a FIFO.
struct BoundedProcessDrainTests {
    /// Roughly 150 KB: well past the 64 KB pipe buffer, with a sentinel at the
    /// very end so a truncated tail is unmissable rather than a shorter string.
    static let payload: String = {
        let filler = Array(
            repeating: #"{"id":"AA:BB:CC:DD:EE:FF","battery":{"single":97}},"#,
            count: 3_000
        ).joined()
        return #"{"schema":"status-trio.helper.v1","devices":["# + filler + #"],"end":"SENTINEL-TAIL"}"#
    }()

    @Test func keepsTheWholeReportWhenADescendantOutlivesTheChild() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        async let outcome = BoundedProcessInvocation.run(
            executableURL: fixture.script,
            arguments: fixture.arguments,
            timeout: .seconds(20)
        )

        try await fixture.waitForChildExit()
        fixture.releaseHeldStreams()
        let result = await outcome

        #expect(result == .exited(Data(Self.payload.utf8)))
    }

    /// The direct child exits while a descendant still holds the inherited write
    /// end, so the invocation is inside its post-exit drain with no EOF in
    /// sight. Cancelling here used to be dropped (`processEnded`), leaving the
    /// caller to wait for the original deadline and the descendant to keep the
    /// read ends open. Cancelling must stop the drain, close both read ends, and
    /// report cancelled exactly once before the deadline.
    @Test func cancellingAfterTheChildExitedReturnsBeforeTheDeadline() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        let invocation = BoundedProcessInvocation(
            executableURL: fixture.script,
            arguments: fixture.arguments
        )
        let recorder = FinishRecorder()
        let started = ContinuousClock.now
        // The 30 s deadline is far beyond the bound below, so finishing in
        // time proves cancel stopped the drain instead of waiting it out; the
        // bound only absorbs scheduler load on the full-suite runner.
        invocation.start(timeout: .seconds(30)) { recorder.record($0) }

        try await fixture.waitForChildExit()
        invocation.cancel()
        invocation.cancel()

        let outcome = recorder.wait(seconds: 10)
        let elapsed = ContinuousClock.now - started

        #expect(outcome == .cancelled)
        #expect(elapsed < .seconds(10), "cancel waited for the original 30 s deadline: \(elapsed)")
        #expect(recorder.count == 1)
        #expect(invocation.isMonitoringPipes == false)
        #expect(invocation.openReadDescriptorCount == 0)
        #expect(invocation.readCloseFailureCount == 0)

        // A late EOF from the descendant must not produce a second callback.
        fixture.releaseHeldStreams()
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.count == 1)
    }

    @Test func cancellingWithOnlyTheStderrHeldOpenReturnsCancelled() async throws {
        let fixture = try HeldStreamFixture(stream: .stderr)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .seconds(8))
        try await fixture.waitForChildExit()
        invocation.cancel()

        #expect(recorder.wait(seconds: 10) == .cancelled)
        #expect(invocation.openReadDescriptorCount == 0)
    }

    @Test func timingOutWithOnlyStdoutHeldClosesTheReadEnd() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .seconds(1))

        #expect(recorder.wait(seconds: 10) == .timedOut)
        #expect(invocation.isMonitoringPipes == false)
        #expect(invocation.openReadDescriptorCount == 0)
    }

    @Test func timingOutWithOnlyStderrHeldClosesTheReadEnd() async throws {
        let fixture = try HeldStreamFixture(stream: .stderr)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .seconds(1))

        #expect(recorder.wait(seconds: 10) == .timedOut)
        #expect(invocation.openReadDescriptorCount == 0)
    }

    /// A failed child keeps the 500 ms error cleanup grace: the inherited write
    /// end never closes, so the invocation must force the cleanup well before
    /// the original deadline.
    @Test func aFailedChildWithHeldStreamsUsesTheErrorGrace() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout, exitStatus: 1)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .seconds(30))
        try await fixture.waitForChildExit()
        let exitObserved = ContinuousClock.now

        #expect(recorder.wait(seconds: 10) == .failed)
        #expect(ContinuousClock.now - exitObserved < .seconds(10))
        #expect(invocation.openReadDescriptorCount == 0)
    }

    @Test func aLateEOFAfterATimeoutDoesNotDeliverAgain() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .milliseconds(300))
        #expect(recorder.wait(seconds: 10) == .timedOut)
        #expect(invocation.openReadDescriptorCount == 0)

        fixture.releaseHeldStreams()
        try await Task.sleep(for: .milliseconds(200))
        #expect(recorder.count == 1)
    }

    /// Releasing the held write ends and cancelling are adjacent on the owner
    /// queue. Whichever wins, the caller sees one outcome and no descriptor is
    /// left behind.
    @Test func releaseAndCancelAtTheSameTimeReportExactlyOnce() async throws {
        let fixture = try HeldStreamFixture(stream: .both)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .seconds(10))
        try await fixture.waitForChildExit()
        fixture.releaseHeldStreams()
        invocation.cancel()

        let outcome = recorder.wait(seconds: 5)
        switch outcome {
        case .exited(let data)?:
            #expect(data == Data(Self.payload.utf8))
        case .cancelled?:
            break
        default:
            Issue.record("unexpected outcome \(String(describing: outcome))")
        }
        #expect(recorder.count == 1)
        #expect(invocation.openReadDescriptorCount == 0)
    }

    /// The same adjacency at the original deadline: a completed report may win,
    /// or the deadline may win, but not both.
    @Test func releaseAtTheDeadlineReportsExactlyOnce() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        let started = ContinuousClock.now
        let deadline = started + .seconds(1)
        let (invocation, recorder) = start(fixture, timeout: .seconds(1))
        try await fixture.waitForChildExit()

        // Release right at the deadline rather than at a fixed offset from
        // start: the child-exit poll above takes a variable amount of time.
        let remaining = deadline - ContinuousClock.now - .milliseconds(10)
        if remaining > .zero {
            try await Task.sleep(for: remaining)
        }
        fixture.releaseHeldStreams()

        let outcome = recorder.wait(seconds: 10)
        guard let outcome else {
            Issue.record("no outcome")
            return
        }
        #expect(outcome == .exited(Data(Self.payload.utf8)) || outcome == .timedOut)
        #expect(recorder.count == 1)
        #expect(invocation.openReadDescriptorCount == 0)
    }

    /// Both inherited write ends stay open after the child exits, and the whole
    /// 150 KB report on each stream is still drained once the descendant lets go.
    @Test func drainsBothHeldStreamsWithoutLosingTheTail() async throws {
        let fixture = try HeldStreamFixture(stream: .both)
        defer { fixture.cleanUp() }

        let (invocation, recorder) = start(fixture, timeout: .seconds(10))
        try await fixture.waitForChildExit()
        fixture.releaseHeldStreams()

        #expect(recorder.wait(seconds: 5) == .exited(Data(Self.payload.utf8)))
        #expect(invocation.openReadDescriptorCount == 0)
    }

    /// Starts a manually driven invocation so cancellation and diagnostics are
    /// observable alongside the finish callback.
    private func start(
        _ fixture: HeldStreamFixture,
        timeout: Duration
    ) -> (BoundedProcessInvocation, FinishRecorder) {
        let invocation = BoundedProcessInvocation(
            executableURL: fixture.script,
            arguments: fixture.arguments
        )
        let recorder = FinishRecorder()
        invocation.start(timeout: timeout) { recorder.record($0) }
        return (invocation, recorder)
    }

    /// The path T-9 and T-10 take: `runSync` blocks the caller, so the release
    /// has to come from another thread. Same fixture, same expectation.
    @Test func keepsTheWholeReportOnTheBlockingPathToo() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        let release = Task.detached {
            try await fixture.waitForChildExit()
            fixture.releaseHeldStreams()
        }

        let result = BoundedProcessInvocation.runSync(
            executableURL: fixture.script,
            arguments: fixture.arguments,
            timeout: .seconds(20)
        )
        try? await release.value

        #expect(result == .exited(Data(Self.payload.utf8)))
    }

}

/// Collects finish callbacks without blocking the invocation's state queue, so a
/// test can assert both the outcome and that it arrived exactly once.
private final class FinishRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var outcomes: [BoundedProcessOutcome] = []

    func record(_ outcome: BoundedProcessOutcome) {
        lock.withLock { outcomes.append(outcome) }
        finished.signal()
    }

    var outcome: BoundedProcessOutcome? { lock.withLock { outcomes.first } }
    var count: Int { lock.withLock { outcomes.count } }

    func wait(seconds: Double) -> BoundedProcessOutcome? {
        _ = finished.wait(timeout: .now() + seconds)
        return outcome
    }
}

/// Runs a child that writes `BoundedProcessDrainTests.payload`, records its own
/// pid, and exits while a descendant keeps the inherited write ends open.
private struct HeldStreamFixture {
    enum Stream {
        /// The report goes to stdout, which the outcome carries.
        case stdout
        /// The report goes to stderr, so only the stderr drain is held open.
        case stderr
        /// The report goes to both streams so both drains run.
        case both
    }

    let script: URL
    let arguments: [String]

    private let pidFile: URL
    private let descendantPIDFile: URL
    private let gate: URL
    private let payloadFile: URL
    private let directory: URL

    init(stream: Stream, exitStatus: Int32 = 0) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("drain-eos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        payloadFile = directory.appendingPathComponent("payload.json")
        pidFile = directory.appendingPathComponent("child.pid")
        descendantPIDFile = directory.appendingPathComponent("descendant.pid")
        gate = directory.appendingPathComponent("gate.fifo")
        script = directory.appendingPathComponent("child.sh")

        try Data(BoundedProcessDrainTests.payload.utf8).write(to: payloadFile)
        guard mkfifo(gate.path, 0o600) == 0 else {
            throw FixtureError.couldNotCreateFIFO(errno)
        }

        // The descendant inherits only the write end under test and blocks on
        // the FIFO, so the child can exit while that pipe is still open. `set -e`
        // keeps a failed write from looking like a clean exit.
        let descendant: String
        switch stream {
        case .stdout:
            descendant = #"( read _held < "\#(gate.path)"; exit 0 ) 2>/dev/null &"#
        case .stderr:
            descendant = #"( read _held < "\#(gate.path)"; exit 0 ) >/dev/null &"#
        case .both:
            descendant = #"( read _held < "\#(gate.path)"; exit 0 ) &"#
        }
        let stdoutLine = stream == .stderr ? "" : #"cat "\#(payloadFile.path)""#
        let stderrLine = stream == .stdout ? "" : #"cat "\#(payloadFile.path)" >&2"#
        let body = """
        #!/bin/sh
        set -e
        \(descendant)
        echo $! > "\(descendantPIDFile.path)"
        # Publish the pid before the large write: a deadline that kills the
        # writer must still leave the test a way to observe the exit.
        echo $$ > "\(pidFile.path)"
        \(stdoutLine)
        \(stderrLine)
        exit \(exitStatus)
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        arguments = []
    }

    enum FixtureError: Error {
        case couldNotCreateFIFO(Int32)
    }

    func cleanUp() {
        releaseHeldStreams()
        waitForDescendantExit()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Waits until the child process is gone, without a fixed sleep: poll the pid
    /// it published, and treat `ESRCH` as the exit.
    func waitForChildExit() async throws {
        for _ in 0..<500 {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                errno = 0
                if kill(pid, 0) == -1, errno == ESRCH { return }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("child process never exited")
    }

    /// Closes the descendant's blocking read, which closes the inherited write
    /// ends and lets the runner reach EOF.
    func releaseHeldStreams() {
        // O_RDWR so opening the FIFO cannot block on the reader or the writer.
        let descriptor = open(gate.path, O_RDWR)
        guard descriptor >= 0 else {
            Issue.record("could not open the release FIFO: errno \(errno)")
            return
        }
        defer { close(descriptor) }
        var newline = UInt8(ascii: "\n")
        _ = write(descriptor, &newline, 1)
    }

    /// Keeps the fixture from leaving an orphan behind: the released descendant
    /// has to be reaped before the directory that names its FIFO disappears.
    private func waitForDescendantExit() {
        guard let text = try? String(contentsOf: descendantPIDFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        for _ in 0..<200 {
            errno = 0
            if kill(pid, 0) == -1, errno == ESRCH { return }
            usleep(10_000)
        }
        Issue.record("held-stream descendant never exited")
    }
}
