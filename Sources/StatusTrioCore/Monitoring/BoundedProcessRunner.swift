import Darwin
import Foundation

/// How a bounded child-process invocation finished.
enum BoundedProcessOutcome: Equatable, Sendable {
    /// The child exited 0; `stdout` is what it wrote (capped at the limit).
    case exited(Data)
    /// The deadline passed. The child was terminated and, failing that, killed.
    case timedOut
    /// The caller cancelled the invocation.
    case cancelled
    /// Launch failed, the child exited non-zero, or a signal killed it.
    case failed
    /// The child wrote more than the limit; it was terminated.
    case outputTooLarge
}

/// Runs one child process with a hard deadline, draining both pipes.
///
/// Exists because `Process.waitUntilExit()` plus `readDataToEndOfFile()` has no
/// bound: a child that never exits, or a grandchild that inherits the pipe and
/// keeps it open, blocks the calling thread for good. On the CoreWLAN and
/// Bluetooth serial queues that is not recoverable - the whole read chain stalls
/// behind it.
///
/// The same state machine serves both callers that can await and callers that
/// cannot: `run` bridges into a checked continuation, `runSync` waits on a
/// semaphore for at most the same deadline. Neither leaves a thread behind.
///
/// One serial queue owns the process, both read sources, the deadline, signal
/// escalation, and completion. Each stream is read by a `DispatchSourceRead`
/// targeting that queue; the descriptor itself is non-blocking and one event
/// reads at most a fixed number of chunks, so a writer that never pauses cannot
/// starve the deadline or cancellation blocks queued behind it. The source's
/// cancel handler closes the read end, and the caller is not resumed until both
/// cancel handlers have run: an outcome therefore means the pipes are actually
/// closed, not merely that their readability handlers were cleared.
///
/// Ordering that matters: the deadline is armed *after* `run()` succeeds, an
/// already-exited child with still-open pipes finishes its drain at the deadline
/// instead of waiting out the descendant's lifetime, cancellation remains valid
/// after the child exited while a descendant holds the write end, and every exit
/// path resumes exactly once after cleanup.
final class BoundedProcessInvocation: @unchecked Sendable {
    static let defaultOutputLimit = 1_048_576

    /// How long the child gets between `terminate()` and `SIGKILL`.
    private static let killGrace: DispatchTimeInterval = .milliseconds(250)
    /// How long a failed/terminated invocation gets for its pipes to reach EOF
    /// before they are force-closed, and the extra settling time after SIGKILL.
    private static let streamGrace: DispatchTimeInterval = .milliseconds(500)

    /// One event reads at most this many chunks. A continuously readable pipe
    /// otherwise keeps this queue busy reading and delays the deadline timer,
    /// a cancel, or the SIGKILL escalation indefinitely.
    private static let readChunkSize = 65_536
    private static let maxReadsPerEvent = 8

    /// The single owner of all mutable state. Reads, timers, and completion all
    /// run here; there is no second IO queue to coordinate with.
    private let queue = DispatchQueue(label: "StatusTrio.BoundedProcess")

    private let executableURL: URL
    private let arguments: [String]
    /// Extra environment entries layered over the inherited process environment.
    private let environment: [String: String]?
    private let outputLimit: Int
    private let onProcessStarted: (@Sendable (Int32) -> Void)?

    private var process: Process?
    private var deadline: DispatchTime?
    private var deadlineTimer: DispatchSourceTimer?
    /// Read endpoints are owned by their dispatch sources once installed; the
    /// source cancel handler closes the descriptor. Until then they are closed
    /// directly on the launch-failure path.
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private var stdout = Data()
    private var stderrCount = 0
    private var stdoutEnded = false
    private var stderrEnded = false
    private var processEnded = false
    private var hasStarted = false
    private var cancellationRequested = false
    private var terminationRequested = false
    private var errorGraceScheduled = false
    /// The first explicit termination reason. A late child exit, a repeated
    /// cancel, or a deadline that lands during cleanup must not rewrite it.
    private var failure: BoundedProcessOutcome?
    /// Fixed once cleanup starts. The sources are cancelled at this point; the
    /// callback fires only after both descriptors are closed.
    private var pendingOutcome: BoundedProcessOutcome?
    private var delivered = false
    private var onFinish: (@Sendable (BoundedProcessOutcome) -> Void)?

    /// FD accounting for synchronous test diagnostics. Mutated on `queue`, read
    /// from test threads, so it lives behind its own lock.
    private let diagnosticsLock = NSLock()
    private var openReadDescriptors = 0
    private var readCloseFailures = 0

    /// Whether either read end is still open. Test-facing invariant: a finished
    /// invocation has no read source and no open pipe descriptor left, because
    /// a pipe at EOF stays readable forever and a held pipe would keep firing.
    var isMonitoringPipes: Bool {
        openReadDescriptorCount > 0
    }

    /// Number of pipe read ends this invocation still owns. The callback is not
    /// invoked until this reaches zero.
    var openReadDescriptorCount: Int {
        diagnosticsLock.withLock { openReadDescriptors }
    }

    /// Number of read ends whose `close()` failed. Should stay zero.
    var readCloseFailureCount: Int {
        diagnosticsLock.withLock { readCloseFailures }
    }

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        outputLimit: Int = BoundedProcessInvocation.defaultOutputLimit,
        onProcessStarted: (@Sendable (Int32) -> Void)? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.outputLimit = outputLimit
        self.onProcessStarted = onProcessStarted
    }

    // MARK: - Entry points

    /// Awaits the child, honouring task cancellation.
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration,
        environment: [String: String]? = nil,
        outputLimit: Int = BoundedProcessInvocation.defaultOutputLimit,
        onProcessStarted: (@Sendable (Int32) -> Void)? = nil
    ) async -> BoundedProcessOutcome {
        let invocation = BoundedProcessInvocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            outputLimit: outputLimit,
            onProcessStarted: onProcessStarted
        )
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                invocation.start(timeout: timeout) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            invocation.cancel()
        }
    }

    /// Blocks the calling thread for at most `timeout`, plus the short grace
    /// periods used to reap the child. For callers on a serial queue that cannot
    /// be made async without reworking their protocol.
    static func runSync(
        executableURL: URL,
        arguments: [String],
        timeout: Duration,
        environment: [String: String]? = nil,
        outputLimit: Int = BoundedProcessInvocation.defaultOutputLimit
    ) -> BoundedProcessOutcome {
        let invocation = BoundedProcessInvocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            outputLimit: outputLimit
        )
        let box = SyncOutcomeBox()
        invocation.start(timeout: timeout) { box.store($0) }

        // The state machine always finishes within the deadline plus its own
        // grace periods, so waiting a little past the deadline is enough; the
        // extra second only covers scheduling slack, and the wait is still
        // bounded.
        return box.wait(.now() + Self.seconds(timeout) + 1.5) ?? .timedOut
    }

    /// Carries one outcome back to a caller that cannot await. The callback
    /// crosses the invocation's queue, so it owns its own lock instead of
    /// capturing the caller's mutable state.
    private final class SyncOutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private let finished = DispatchSemaphore(value: 0)
        private var outcome: BoundedProcessOutcome?

        func store(_ outcome: BoundedProcessOutcome) {
            lock.withLock { self.outcome = outcome }
            finished.signal()
        }

        func wait(_ deadline: DispatchTime) -> BoundedProcessOutcome? {
            _ = finished.wait(timeout: deadline)
            return lock.withLock { outcome }
        }
    }

    // MARK: - State machine

    // Internal (not private) so tests can drive one invocation directly and
    // assert the pipe cleanup after it finishes.
    func start(
        timeout: Duration,
        onFinish: @escaping @Sendable (BoundedProcessOutcome) -> Void
    ) {
        queue.async { [self] in
            guard !self.delivered, !self.hasStarted, self.process == nil else { return }
            self.onFinish = onFinish
            self.hasStarted = true

            // Cancellation can be enqueued before start (or fire on an already
            // cancelled task). There is nothing to launch in that case.
            if self.cancellationRequested {
                self.pendingOutcome = self.pendingOutcome ?? .cancelled
                self.deliverIfReady()
                return
            }

            let child = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            child.executableURL = self.executableURL
            child.arguments = self.arguments
            if let environment = self.environment {
                child.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
            }
            child.standardOutput = stdoutPipe
            child.standardError = stderrPipe
            self.process = child
            self.stdoutHandle = stdoutPipe.fileHandleForReading
            self.stderrHandle = stderrPipe.fileHandleForReading

            // A dispatch source reports readiness for a read, not for a full
            // batch. Never put a blocking descriptor on the state queue.
            guard Self.makeNonblocking(stdoutPipe.fileHandleForReading),
                  Self.makeNonblocking(stderrPipe.fileHandleForReading) else {
                self.closeReadEndsWithoutSource()
                self.process = nil
                self.beginFinish(.failed)
                return
            }

            // Install the exit handler before launching: a child that exits
            // immediately must not lose its notification, and later callbacks
            // hop onto the same owner queue as every other transition.
            child.terminationHandler = { [weak self] terminated in
                guard let self else { return }
                self.queue.async { [self] in
                    self.processDidExit(terminated)
                }
            }

            do {
                try child.run()
            } catch {
                child.terminationHandler = nil
                self.closeReadEndsWithoutSource()
                self.process = nil
                self.beginFinish(.failed)
                return
            }

            let deadline = DispatchTime.now() + Self.seconds(timeout)
            self.deadline = deadline
            self.onProcessStarted?(child.processIdentifier)
            self.stdoutSource = self.installReadSource(stdoutPipe.fileHandleForReading, stream: .stdout)
            self.stderrSource = self.installReadSource(stderrPipe.fileHandleForReading, stream: .stderr)
            // The one-shot deadline owns the invocation until delivery. A
            // direct start caller need not keep the invocation alive itself.
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: deadline)
            timer.setEventHandler { [self] in self.deadlineReached() }
            self.deadlineTimer = timer
            timer.activate()
        }
    }

    func cancel() {
        let requestedAt = DispatchTime.now()
        queue.async {
            guard !self.delivered, self.pendingOutcome == nil else { return }
            if let deadline = self.deadline, requestedAt >= deadline {
                self.deadlineReached()
                return
            }
            self.cancellationRequested = true
            self.failure = self.failure ?? .cancelled
            if self.hasStarted || self.process != nil {
                // The direct child may already be gone while a descendant keeps
                // the inherited write ends open. Cancellation still owns the
                // cleanup: stop reading, close both read ends, and report
                // cancelled without waiting for the original deadline.
                self.beginFinish(self.failure ?? .cancelled)
            } else {
                // start() has not run yet; it will deliver this outcome.
                self.pendingOutcome = .cancelled
            }
        }
    }

    private enum Stream { case stdout, stderr }

    // MARK: - Reading

    private static func makeNonblocking(_ handle: FileHandle) -> Bool {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1
    }

    /// Creates the read source for a non-blocking stream. Its event and cancel
    /// handlers run on the owner queue and share the descriptor's lifetime.
    private func installReadSource(_ handle: FileHandle, stream: Stream) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable(stream)
        }
        source.setCancelHandler { [weak self, handle] in
            do {
                try handle.close()
            } catch {
                self?.recordReadCloseFailure()
            }
            self?.readEndClosed()
        }
        diagnosticsLock.withLock { openReadDescriptors += 1 }
        source.resume()
        return source
    }

    /// One readability event. The syscall budget bounds how long a stream that
    /// never stops writing can hold the owner queue; EINTR also consumes one
    /// unit so a signal storm cannot turn this into an unbounded loop.
    private func readAvailable(_ stream: Stream) {
        guard !delivered, pendingOutcome == nil else { return }
        guard let handle = readHandle(for: stream) else { return }
        let descriptor = handle.fileDescriptor
        guard descriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        var syscalls = 0
        while syscalls < Self.maxReadsPerEvent {
            syscalls += 1
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(descriptor, bytes.baseAddress, bytes.count)
            }

            if count > 0 {
                received(Data(buffer[0..<count]), stream: stream)
                // A rejected chunk cancels that stream's source, and a fixed
                // outcome stops all reading. Do not touch a closed descriptor.
                if delivered || pendingOutcome != nil || source(for: stream) == nil {
                    return
                }
                continue
            }

            if count == 0 {
                endOfStream(stream)
                return
            }

            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK { return }

            // A real read error leaves the stream unusable. The invocation
            // fails, and the normal failure cleanup closes both read ends.
            failure = failure ?? .failed
            cancelSource(stream)
            requestTerminationIfRunning()
            scheduleErrorCleanup()
            return
        }
    }

    private func received(_ data: Data, stream: Stream) {
        guard !delivered, pendingOutcome == nil, failure == nil else { return }

        switch stream {
        case .stdout:
            guard stdout.count + data.count <= outputLimit else {
                rejectStream(stream, reason: .outputTooLarge)
                return
            }
            stdout.append(data)
        case .stderr:
            guard stderrCount + data.count <= outputLimit else {
                rejectStream(stream, reason: .outputTooLarge)
                return
            }
            stderrCount += data.count
        }
    }

    private func rejectStream(_ stream: Stream, reason: BoundedProcessOutcome) {
        failure = failure ?? reason
        // That read end can only keep producing data we would drop; closing it
        // stops the reader and delivers SIGPIPE to the writer.
        cancelSource(stream)
        requestTerminationIfRunning()
        scheduleErrorCleanup()
    }

    private func endOfStream(_ stream: Stream) {
        switch stream {
        case .stdout:
            stdoutEnded = true
        case .stderr:
            stderrEnded = true
        }
        // The cancel handler owns the descriptor and closes it; completion is
        // re-checked from `readEndClosed` after that happens.
        cancelSource(stream)
        completeIfReady()
    }

    private func readEndClosed() {
        diagnosticsLock.withLock { openReadDescriptors -= 1 }
        completeIfReady()
    }

    private func recordReadCloseFailure() {
        diagnosticsLock.withLock { readCloseFailures += 1 }
        failure = failure ?? .failed
    }

    private func readHandle(for stream: Stream) -> FileHandle? {
        switch stream {
        case .stdout: return stdoutHandle
        case .stderr: return stderrHandle
        }
    }

    private func source(for stream: Stream) -> DispatchSourceRead? {
        switch stream {
        case .stdout: return stdoutSource
        case .stderr: return stderrSource
        }
    }

    private func cancelSource(_ stream: Stream) {
        switch stream {
        case .stdout:
            guard let source = stdoutSource else { return }
            stdoutSource = nil
            source.cancel()
        case .stderr:
            guard let source = stderrSource else { return }
            stderrSource = nil
            source.cancel()
        }
    }

    private func cancelReadSources() {
        cancelSource(.stdout)
        cancelSource(.stderr)
    }

    // MARK: - Termination and completion

    private func processDidExit(_ terminated: Process) {
        guard !delivered else { return }
        processEnded = true
        if terminated.terminationReason != .exit || terminated.terminationStatus != 0 {
            failure = failure ?? .failed
        }
        // A failed child's descendants may still hold the inherited write ends.
        // Keep draining for at most the error grace, then close them.
        if pendingOutcome == nil, failure != nil {
            scheduleErrorCleanup()
        }
        completeIfReady()
    }

    /// The original deadline. It is never extended to wait for an EOF: the
    /// direct child and both read ends are cleaned up now, and the first
    /// failure reason (if any) is preserved.
    private func deadlineReached() {
        guard !delivered, pendingOutcome == nil else { return }
        let reason = failure ?? .timedOut
        if failure == nil {
            failure = .timedOut
        }
        beginFinish(reason)
    }

    /// Closes the read ends after a failure and gives the child's pipes one
    /// bounded grace period to finish naturally first.
    private func scheduleErrorCleanup() {
        guard !errorGraceScheduled, !delivered, pendingOutcome == nil else { return }
        errorGraceScheduled = true
        queue.asyncAfter(deadline: .now() + Self.streamGrace) { [weak self] in
            guard let self, !self.delivered, self.pendingOutcome == nil else { return }
            self.beginFinish(self.failure ?? .failed)
        }
    }

    private func completeIfReady() {
        guard !delivered else { return }
        if pendingOutcome != nil {
            deliverIfReady()
            return
        }
        if let failure {
            if processEnded && openReadDescriptorCount == 0 {
                beginFinish(failure)
            } else {
                scheduleErrorCleanup()
            }
            return
        }
        if processEnded, stdoutEnded, stderrEnded, openReadDescriptorCount == 0 {
            // Success needs the child's zero status, both EOFs, and both
            // descriptors actually closed.
            if let deadline, DispatchTime.now() >= deadline {
                deadlineReached()
            } else {
                beginFinish(.exited(stdout))
            }
        }
    }

    /// Fixes the outcome once, stops all reading, and makes sure the direct
    /// child is not left running. Delivery waits for descriptor closure and for
    /// the child to be gone.
    private func beginFinish(_ outcome: BoundedProcessOutcome) {
        guard !delivered else { return }
        if pendingOutcome == nil {
            pendingOutcome = outcome
        }
        cancelReadSources()
        requestTerminationIfRunning()
        if process == nil {
            processEnded = true
        }
        deliverIfReady()
    }

    /// Signals only the direct child this invocation launched, and only while it
    /// is still running. Repeated cancels, a timeout during failure cleanup, and
    /// a late exit notification all converge on this one escalation path.
    private func requestTerminationIfRunning() {
        guard !terminationRequested, !delivered else { return }
        guard let child = process else {
            processEnded = true
            return
        }
        guard child.isRunning else {
            processEnded = true
            return
        }

        terminationRequested = true
        let pid = child.processIdentifier
        child.terminate()
        queue.asyncAfter(deadline: .now() + Self.killGrace) { [weak self] in
            guard let self, !self.delivered else { return }
            if child.isRunning {
                _ = kill(pid, SIGKILL)
                // Process normally reports the exit before this fallback. If
                // its callback is late or never arrives, SIGKILL has still
                // removed the direct child; finish after one settling grace.
                self.queue.asyncAfter(deadline: .now() + Self.killGrace) { [weak self] in
                    guard let self, !self.delivered else { return }
                    self.processEnded = true
                    self.deliverIfReady()
                }
            } else {
                self.processEnded = true
                self.deliverIfReady()
            }
        }
    }

    /// The only place the caller is resumed. Every condition that makes the
    /// outcome honest - fixed reason, closed descriptors, gone child - is
    /// checked here, and `delivered` guarantees exactly one callback.
    private func deliverIfReady() {
        guard !delivered, let outcome = pendingOutcome, let callback = onFinish else { return }
        guard openReadDescriptorCount == 0 else { return }
        guard processEnded || process == nil else { return }

        delivered = true
        deadlineTimer?.cancel()
        deadlineTimer = nil
        onFinish = nil
        stdoutSource = nil
        stderrSource = nil
        stdoutHandle = nil
        stderrHandle = nil
        process?.terminationHandler = nil
        process = nil
        callback(outcome)
    }

    /// Launch failed before any read source owned the descriptors.
    private func closeReadEndsWithoutSource() {
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
