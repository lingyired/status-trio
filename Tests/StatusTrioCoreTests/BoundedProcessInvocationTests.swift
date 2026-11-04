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

    /// Issue #268 regression: `finish` used to nil its `stdoutPipe`/`stderrPipe`
    /// properties while `drainPipesAfterProcessExit` on the stream queues was
    /// still reading them, releasing the NSPipe mid-drain - a use-after-free
    /// (SIGSEGV/EXC_BAD_ACCESS in `objc_retain` on
    /// `-[NSConcretePipe fileHandleForReading]`). The race is timing-dependent, so
    /// beat on it from every direction at once: normal exit, timeout with a held
    /// descendant pipe, timeout on a plain sleeper, and an over-limit writer.
    /// Under TSan this fails on the old code; the fix leaves the pipes to ARC and
    /// the version-stable here.
    @Test func noUseAfterFreeUnderConcurrentFinishAndDrain() async {
        let base = URL(fileURLWithPath: "/bin/sh")

        // ~40 invocations: enough overlap for the stream-queue drains to land
        // between the deadline handling and finish while staying quick on a busy
        // runner.
        for _ in 0..<10 {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = BoundedProcessInvocation.runSync(executableURL: base, arguments: ["-c", "printf 'ok'"], timeout: .seconds(2))
                }
                group.addTask {
                    _ = BoundedProcessInvocation.runSync(executableURL: base, arguments: ["-c", "sleep 30 & printf 'ready'; exit 0"], timeout: .milliseconds(200))
                }
                group.addTask {
                    _ = BoundedProcessInvocation.runSync(executableURL: base, arguments: ["-c", "sleep 30"], timeout: .milliseconds(200))
                }
                group.addTask {
                    _ = BoundedProcessInvocation.runSync(executableURL: base, arguments: ["-c", "yes 0123456789"], timeout: .seconds(2), outputLimit: 4_096)
                }
                for await _ in group {}
            }
        }
    }
}
