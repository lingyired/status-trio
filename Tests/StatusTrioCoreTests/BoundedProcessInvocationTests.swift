import Foundation
import Testing
@testable import StatusTrioCore

/// T-9 and T-10 call `runSync` from a serial queue, so the bound and the child
/// reaping are what keep those queues from being occupied for good. These cover
/// the two ways a synchronous `waitUntilExit()` used to hang.
struct BoundedProcessInvocationTests {
    @Test func runSyncReturnsStdoutOfAShortLivedChild() {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'alpha\\nbeta\\n'"],
            timeout: .seconds(2)
        )
        #expect(outcome == .exited(Data("alpha\nbeta\n".utf8)))
    }

    @Test func runSyncReportsAFailedChildWithoutWaitingForTheDeadline() {
        let started = ContinuousClock.now
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 3"],
            timeout: .seconds(5)
        )
        #expect(outcome == .failed)
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func runSyncGivesUpAtTheDeadlineInsteadOfBlockingForever() {
        let started = ContinuousClock.now
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 30"],
            timeout: .milliseconds(300)
        )
        #expect(outcome == .timedOut)
        // 300ms deadline + 250ms kill grace + 500ms stream grace, plus slack for
        // a loaded machine. The point is "not the 30-second sleep", not a budget.
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    /// The M-3 shape: the child exits, but a descendant inherits its stdout and
    /// keeps the pipe open, so EOF never arrives. A `readDataToEndOfFile()` based
    /// reader hangs here forever.
    @Test func runSyncFinishesWhenADescendantKeepsThePipesOpen() {
        let started = ContinuousClock.now
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 30 & printf 'ready\\n'; exit 0"],
            timeout: .milliseconds(300)
        )
        #expect(outcome == .timedOut)
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func runSyncRejectsAChildThatWritesMoreThanTheLimit() {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes 0123456789"],
            timeout: .seconds(5),
            outputLimit: 4_096
        )
        #expect(outcome == .outputTooLarge)
    }
}
