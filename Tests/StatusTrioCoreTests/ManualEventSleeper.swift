import Foundation

@MainActor
final class ManualEventSleeper {
    private(set) var callCount = 0
    private(set) var completionCount = 0
    private(set) var durations: [Duration] = []

    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var completionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(_ duration: Duration) async {
        callCount += 1
        durations.append(duration)
        resumeCallWaiters()

        await withCheckedContinuation { continuation in
            sleepContinuations.append(continuation)
        }

        completionCount += 1
        resumeCompletionWaiters()
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    /// Bounded variant of `waitForCallCount(_:)`. Returns `false` when the call
    /// never arrives, so a regression fails the test instead of parking it until
    /// the whole-run timeout and turning a failure into a CI hang.
    func waitForCallCount(_ count: Int, timeout: Duration) async -> Bool {
        guard callCount < count else { return true }
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            // Wake only the waiters this call is responsible for; other pending
            // waits keep waiting for their own call.
            let pending = callWaiters.filter { $0.count == count }.map { $0.continuation }
            callWaiters.removeAll { $0.count == count }
            pending.forEach { $0.resume() }
        }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
        timeoutTask.cancel()
        return callCount >= count
    }

    func waitForCompletionCount(_ count: Int) async {
        guard completionCount < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append((count, continuation))
        }
    }

    func releaseAll() {
        let continuations = sleepContinuations
        sleepContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func releaseOldest() {
        guard !sleepContinuations.isEmpty else { return }
        sleepContinuations.removeFirst().resume()
    }

    private func resumeCallWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in callWaiters {
            if callCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callWaiters = remaining
    }

    private func resumeCompletionWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in completionWaiters {
            if completionCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        completionWaiters = remaining
    }
}
