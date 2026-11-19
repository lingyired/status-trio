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
        private var outcomes: [BoundedProcessOutcome] = []

        func store(_ outcome: BoundedProcessOutcome) {
            lock.withLock { outcomes.append(outcome) }
            finished.signal()
        }

        var count: Int { lock.withLock { outcomes.count } }

        func wait(seconds: Double) -> BoundedProcessOutcome? {
            _ = finished.wait(timeout: .now() + seconds)
            return lock.withLock { outcomes.first }
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
    @Test func directStartDeliversWhenTheCallerDoesNotRetainTheInvocation() {
        let box = OutcomeBox()
        BoundedProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.05; printf ready"]
        ).start(timeout: .seconds(2)) { box.store($0) }

        #expect(box.wait(seconds: 4) == .exited(Data("ready".utf8)))
        #expect(box.count == 1)
    }

    @Test func aDelayedStateQueueCannotTurnAnExpiredReadIntoSuccess() {
        let box = OutcomeBox()
        let invocation = BoundedProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf ready"],
            onProcessStarted: { _ in Thread.sleep(forTimeInterval: 0.12) }
        )
        invocation.start(timeout: .milliseconds(30)) { box.store($0) }

        #expect(box.wait(seconds: 4) == .timedOut)
        #expect(box.count == 1)
        #expect(!invocation.isMonitoringPipes)
    }

    @Test func launchFailureClearsReadabilityHandlers() {
        let (outcome, invocation) = runAndWait(
            executableURL: URL(fileURLWithPath: "/nonexistent-status-trio/definitely-not-here"),
            arguments: [],
            timeout: .seconds(2),
            waitSeconds: 5
        )

        #expect(outcome == .failed)
        #expect(invocation.isMonitoringPipes == false)
        #expect(invocation.openReadDescriptorCount == 0)
        #expect(invocation.readCloseFailureCount == 0)
    }

    /// Repeated ordinary runs must leave no handler behind; an accumulation here
    /// is what a spinning fd-monitoring source would show up as.
    @Test func ordinaryRunsLeaveNoHandlersBehind() {
        // Enough repetitions for a descriptor leak to survive the fixture's
        // short-lived children; the count assertions below fail on the first
        // invocation that keeps a read end.
        for _ in 0..<100 {
            let (outcome, invocation) = runAndWait(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf hello"],
                timeout: .seconds(5),
                waitSeconds: 8
            )

            #expect(outcome == .exited(Data("hello".utf8)))
            #expect(invocation.isMonitoringPipes == false)
            #expect(invocation.openReadDescriptorCount == 0)
            #expect(invocation.readCloseFailureCount == 0)
        }
    }

    /// Cancellation can be queued before `start`. Nothing may be launched, and
    /// there must be no descriptor to close because none was opened.
    @Test func cancelBeforeStartLeavesNoProcessOrDescriptor() {
        let invocation = BoundedProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf should-not-run"]
        )
        let box = OutcomeBox()
        invocation.cancel()
        invocation.start(timeout: .seconds(2)) { box.store($0) }

        #expect(box.wait(seconds: 3) == .cancelled)
        #expect(box.count == 1)
        #expect(invocation.isMonitoringPipes == false)
        #expect(invocation.openReadDescriptorCount == 0)
    }

    /// Repeated cancellation while the child is running converges on the same
    /// termination path: one signal escalation, one callback, no descriptors.
    @Test func repeatedCancelWhileRunningFinishesOnce() {
        let processStarted = DispatchSemaphore(value: 0)
        let invocation = BoundedProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exec sleep 30"],
            onProcessStarted: { _ in processStarted.signal() }
        )
        let box = OutcomeBox()
        invocation.start(timeout: .seconds(10)) { box.store($0) }

        #expect(processStarted.wait(timeout: .now() + 5) == .success)
        invocation.cancel()
        invocation.cancel()

        #expect(box.wait(seconds: 5) == .cancelled)
        #expect(box.count == 1)
        #expect(invocation.isMonitoringPipes == false)
        #expect(invocation.openReadDescriptorCount == 0)
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
        #expect(invocation.openReadDescriptorCount == 0)
        #expect(invocation.readCloseFailureCount == 0)
    }
}
