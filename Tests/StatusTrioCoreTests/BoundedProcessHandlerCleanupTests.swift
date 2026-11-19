import Dispatch
import Foundation
import Testing
@testable import StatusTrioCore

/// Issue #356 regression: an invocation that has finished must never leave a
/// pipe read end with a readability handler installed.
///
/// A pipe at EOF stays *readable* forever, and a timeout/cancel can finish while
/// a descendant still holds the inherited write end. Either way a leftover
/// handler keeps dispatching on the fd-monitoring queue after the caller has been
/// resumed — which is exactly the "many `NSFileHandle.fd_monitoring` queues /
/// several cores busy" fingerprint reported for the top-apps sampler.
struct BoundedProcessHandlerCleanupTests {
    /// Carries one outcome back to the test thread without blocking the
    /// invocation's own queue.
    private final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private let finished = DispatchSemaphore(value: 0)
        private var outcome: BoundedProcessOutcome?

        func store(_ outcome: BoundedProcessOutcome) {
            lock.withLock { self.outcome = outcome }
            finished.signal()
        }

        func wait(seconds: Double) -> BoundedProcessOutcome? {
            _ = finished.wait(timeout: .now() + seconds)
            return lock.withLock { outcome }
        }
    }

    /// Drives one invocation directly so the test can inspect its pipe state
    /// after it finishes.
    private func runAndWait(
        executableURL: URL,
        arguments: [String],
        timeout: Duration,
        waitSeconds: Double
    ) -> (outcome: BoundedProcessOutcome?, invocation: BoundedProcessInvocation) {
        let invocation = BoundedProcessInvocation(executableURL: executableURL, arguments: arguments)
        let box = OutcomeBox()
        invocation.start(timeout: timeout) { box.store($0) }
        return (box.wait(seconds: waitSeconds), invocation)
    }

    /// The launch-failure path never runs a termination handler, so before the
    /// fix its readability handlers stayed installed on live pipes. This is the
    /// deterministic form of "a finished invocation must clear its handlers".
    @Test func launchFailureClearsReadabilityHandlers() {
        let (outcome, invocation) = runAndWait(
            executableURL: URL(fileURLWithPath: "/nonexistent-status-trio/definitely-not-here"),
            arguments: [],
            timeout: .seconds(2),
            waitSeconds: 5
        )

        #expect(outcome == .failed)
        #expect(invocation.isMonitoringPipes == false)
    }

    /// Repeated ordinary runs must leave no handler behind; an accumulation here
    /// is what a spinning fd-monitoring source would show up as.
    @Test func ordinaryRunsLeaveNoHandlersBehind() {
        for _ in 0..<25 {
            let (outcome, invocation) = runAndWait(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf hello"],
                timeout: .seconds(5),
                waitSeconds: 8
            )

            #expect(outcome == .exited(Data("hello".utf8)))
            #expect(invocation.isMonitoringPipes == false)
        }
    }

    /// A run that ends by timeout must also clear the handlers it installed.
    @Test func timedOutRunClearsReadabilityHandlers() {
        let (outcome, invocation) = runAndWait(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exec sleep 30"],
            timeout: .seconds(1),
            waitSeconds: 8
        )

        #expect(outcome == .timedOut)
        #expect(invocation.isMonitoringPipes == false)
    }
}
