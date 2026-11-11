import Foundation
import PowerHelperProtocol

/// Runs `pmset` on behalf of the daemon. Injected so the daemon's decision
/// logic can be exercised without root.
protocol PmsetRunning: Sendable {
    func setLowPowerMode(enabled: Bool) async throws
    func currentLowPowerMode() async -> Bool?
    func highPowerModeSupported() async -> Bool?
    func setHighPowerMode(enabled: Bool) async throws
    func currentHighPowerMode() async -> Bool?
    func setDisableSleep(enabled: Bool) async throws
    func currentDisableSleep() async -> Bool?
}

/// Defaults keep a runner that only models Low Power Mode (the fixtures in the
/// tests) valid. The real runner overrides all of them.
extension PmsetRunning {
    func highPowerModeSupported() async -> Bool? { false }
    func setHighPowerMode(enabled: Bool) async throws {
        throw PmsetError.launchFailed("High Power Mode is not supported")
    }
    func currentHighPowerMode() async -> Bool? { nil }
    func setDisableSleep(enabled: Bool) async throws {
        throw PmsetError.launchFailed("Disable sleep is not supported")
    }
    func currentDisableSleep() async -> Bool? { nil }
}

enum PmsetError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, String?)
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .launchFailed(reason): "pmset could not be launched: \(reason)"
        case let .nonZeroExit(code, message):
            if let message, !message.isEmpty {
                "pmset exited with status \(code): \(message)"
            } else {
                "pmset exited with status \(code)"
            }
        case .timedOut: "pmset did not finish in time"
        }
    }
}

/// Reads a pipe until EOF or a deadline.
///
/// `readDataToEndOfFile()` has no bound: a descendant that inherits the write
/// end keeps the pipe open long after the child this daemon started has exited.
/// The drain runs on the cooperative executor, so an unbounded read parks a pool
/// worker for as long as that descendant lives.
enum BoundedPipeDrain {
    static let defaultTimeout: TimeInterval = 1

    static func readToEnd(_ handle: FileHandle, timeout: TimeInterval) -> Data {
        let descriptor = handle.fileDescriptor
        let originalFlags = fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0,
              fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) >= 0 else {
            return Data()
        }
        defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while data.count < 1_048_576 {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            var descriptorState = pollfd(
                fd: descriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let ready = poll(
                &descriptorState,
                1,
                Int32(max(1, min(remaining, 0.25) * 1_000))
            )
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return read(descriptor, base, raw.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                break
            } else if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                continue
            } else {
                break
            }
        }
        return data
    }
}

/// Production runner: spawns `/usr/bin/pmset` with the argument shape owned by
/// `LowPowerModeCommand`.
///
/// The daemon serves every request on its XPC queue, so it must never wait on a
/// child without a bound: a wedged `pmset` would otherwise stall reads and
/// writes alike, including the app's health probe, for as long as the child
/// stays alive. Each run is awaited asynchronously and killed once `timeout`
/// elapses.
struct SystemPmsetRunner: PmsetRunning {
    /// Long enough for `pmset` to persist a setting on a loaded machine, short
    /// enough that a stuck power-management call cannot be mistaken for a hang.
    static let defaultTimeout: Duration = .seconds(5)

    private let timeout: Duration
    private let executableURL: URL

    init(
        timeout: Duration = SystemPmsetRunner.defaultTimeout,
        executableURL: URL = URL(fileURLWithPath: LowPowerModeCommand.pmsetPath)
    ) {
        self.timeout = timeout
        self.executableURL = executableURL
    }

    func setLowPowerMode(enabled: Bool) async throws {
        // Low and High Power Mode are two states of the one system Power Mode
        // switch, so turning Low Power Mode on while High Power Mode is active
        // leaves the Mac in an undefined combination. Clear High Power Mode
        // first; the clear is best effort, because a Mac that does not support
        // it must never fail the Low Power Mode write. The capability probe is
        // deliberately not consulted here: it is a separate child process and
        // this path only needs the write itself.
        if enabled {
            // `powermode 0` is Automatic: it clears High Power Mode. The old
            // `highpowermode` argument is no longer accepted on macOS 26+.
            _ = try? await runWrite(arguments: HighPowerModeCommand.arguments(enabled: false))
        }
        try await runWrite(arguments: LowPowerModeCommand.arguments(enabled: enabled))
    }

    func currentLowPowerMode() async -> Bool? {
        // Read the system state from `pmset -g` rather than
        // `ProcessInfo.isLowPowerModeEnabled`: that value is cached per process
        // and only refreshes when the process receives a power-state-change
        // notification, so a freshly started daemon reports `false` even when the
        // system is in Low Power Mode.
        guard let outcome = try? await run(arguments: ["-g"], capturesOutput: true),
              outcome.status == 0 else { return nil }
        return LowPowerModeCommand.parseEnabled(fromPmsetOutput: outcome.output)
    }

    func highPowerModeSupported() async -> Bool? {
        // `pmset -g cap` is the capability probe recommended by the issue: it
        // follows whatever the running macOS reports instead of hard-coding a
        // model list a future Mac would fall outside of.
        guard let outcome = try? await run(
            arguments: HighPowerModeCommand.capabilitiesArguments,
            capturesOutput: true
        ), outcome.status == 0 else {
            return nil
        }
        return HighPowerModeCommand.isSupported(fromCapabilitiesOutput: outcome.output)
    }

    func currentHighPowerMode() async -> Bool? {
        guard let outcome = try? await run(arguments: ["-g"], capturesOutput: true),
              outcome.status == 0 else { return nil }
        return HighPowerModeCommand.parseEnabled(fromPmsetOutput: outcome.output)
    }

    func setHighPowerMode(enabled: Bool) async throws {
        // Clear the mutually exclusive Low Power Mode first. Best effort: a
        // write that the Mac ignores must not fail the High Power Mode write.
        if enabled {
            _ = try? await runWrite(arguments: LowPowerModeCommand.arguments(enabled: false))
        }
        try await runWrite(arguments: HighPowerModeCommand.arguments(enabled: enabled))
    }

    func currentDisableSleep() async -> Bool? {
        guard let outcome = try? await run(arguments: ["-g"], capturesOutput: true),
              outcome.status == 0 else { return nil }
        return DisableSleepCommand.parseSleepDisabled(fromPmsetOutput: outcome.output)
    }

    func setDisableSleep(enabled: Bool) async throws {
        try await runWrite(arguments: DisableSleepCommand.arguments(enabled: enabled))
    }

    private func runWrite(arguments: [String]) async throws {
        // Capture both streams so a rejected write reports `pmset`'s own reason
        // (`Unsupported mode 3`, usage text) instead of only an exit status.
        let outcome = try await run(
            arguments: arguments,
            capturesOutput: true,
            capturesError: true
        )
        guard let status = outcome.status else { throw PmsetError.timedOut }
        guard status == 0 else {
            throw PmsetError.nonZeroExit(status, outcome.errorOutput)
        }
    }

    private struct Outcome {
        /// `nil` when the timeout fired before the child exited.
        let status: Int32?
        let output: String
        let errorOutput: String
    }

    private func run(
        arguments: [String],
        capturesOutput: Bool,
        capturesError: Bool = false
    ) async throws -> Outcome {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        // Unread pipes can fill and block the child, so a stream is only piped
        // when the caller actually parses it. `pmset` writes a single short line,
        // well under the pipe buffer, so draining both after exit is safe.
        let stderrPipe: Pipe?
        if capturesError {
            let pipe = Pipe()
            process.standardError = pipe
            stderrPipe = pipe
        } else {
            process.standardError = FileHandle.nullDevice
            stderrPipe = nil
        }
        let stdoutPipe: Pipe?
        if capturesOutput {
            let pipe = Pipe()
            process.standardOutput = pipe
            stdoutPipe = pipe
        } else {
            process.standardOutput = FileHandle.nullDevice
            stdoutPipe = nil
        }

        do {
            try process.run()
        } catch {
            throw PmsetError.launchFailed(error.localizedDescription)
        }

        let status = await waitForExit(of: process)
        // A timed-out child was killed, so its output is incomplete by
        // definition. Draining the pipes here can block forever when the child
        // left a descendant holding the write end; skip it and report the
        // timeout instead of waiting for that descendant.
        if status == nil {
            return Outcome(status: nil, output: "", errorOutput: "")
        }
        let output = stdoutPipe.map {
            String(
                data: BoundedPipeDrain.readToEnd(
                    $0.fileHandleForReading,
                    timeout: BoundedPipeDrain.defaultTimeout
                ),
                encoding: .utf8
            ) ?? ""
        } ?? ""
        let errorOutput = stderrPipe.map {
            String(
                data: BoundedPipeDrain.readToEnd(
                    $0.fileHandleForReading,
                    timeout: BoundedPipeDrain.defaultTimeout
                ),
                encoding: .utf8
            ) ?? ""
        } ?? ""
        return Outcome(status: status, output: output, errorOutput: errorOutput)
    }

    /// Awaits the child without blocking the caller's queue, and reports `nil`
    /// instead of waiting forever when the timeout fires and the child is
    /// killed.
    private func waitForExit(of process: Process) async -> Int32? {
        let pid = process.processIdentifier
        let completion = PmsetCompletion()
        let timeout = self.timeout

        return await withCheckedContinuation { continuation in
            completion.attach(continuation)

            process.terminationHandler = { finished in
                completion.finish(finished.terminationStatus)
            }
            // A child that exits between `run()` and the handler assignment
            // never calls it, so check the state once synchronously.
            if !process.isRunning {
                completion.finish(process.terminationStatus)
            }

            Task.detached {
                do { try await Task.sleep(for: timeout) } catch { return }
                // Only the timeout that still owns the wait kills; a child that
                // already exited must not see a stray signal.
                guard completion.finish(nil) else { return }
                _ = kill(pid, SIGKILL)
            }
        }
    }
}

/// One-shot completion shared by the termination handler and the timeout task.
private final class PmsetCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32?, Never>?
    private var hasFinished = false

    func attach(_ continuation: CheckedContinuation<Int32?, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    /// Returns true only for the caller that completed the wait, so the timeout
    /// path can tell whether it still owns the kill.
    @discardableResult
    func finish(_ status: Int32?) -> Bool {
        lock.lock()
        guard !hasFinished, let continuation else {
            lock.unlock()
            return false
        }
        hasFinished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: status)
        return true
    }
}

/// The object the daemon exports over XPC.
final class PowerModeService: NSObject, PowerHelperXPCProtocol {
    private let runner: any PmsetRunning

    init(runner: any PmsetRunning = SystemPmsetRunner()) {
        self.runner = runner
    }

    func readLowPowerMode(withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            guard let enabled = await runner.currentLowPowerMode() else {
                reply.send(false, "Low Power Mode state is unavailable.")
                return
            }
            reply.send(enabled, nil)
        }
    }

    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            do {
                try await runner.setLowPowerMode(enabled: enabled)
            } catch {
                reply.send(false, error.localizedDescription)
                return
            }
            // Reply with the state the daemon observes after the change so the app
            // never has to assume the write took.
            reply.send(await runner.currentLowPowerMode() ?? enabled, nil)
        }
    }

    func readProtocolVersion(withReply reply: @escaping (Int, String?) -> Void) {
        // Answered from the daemon's own binary: an outdated daemon does not
        // implement this selector at all, and the app turns that connection
        // failure into a "helper needs updating" notice.
        PowerHelperReply(reply).send(PowerHelperProtocolVersion.current, nil)
    }

    func readHighPowerModeSupport(withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            guard let supported = await runner.highPowerModeSupported() else {
                reply.send(false, "High Power Mode support is unavailable.")
                return
            }
            reply.send(supported, nil)
        }
    }

    func readHighPowerMode(withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            guard let enabled = await runner.currentHighPowerMode() else {
                reply.send(false, "High Power Mode state is unavailable.")
                return
            }
            reply.send(enabled, nil)
        }
    }

    func setHighPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            do {
                try await runner.setHighPowerMode(enabled: enabled)
            } catch {
                reply.send(false, error.localizedDescription)
                return
            }
            guard let observed = await runner.currentHighPowerMode() else {
                reply.send(false, "High Power Mode could not be verified after the write.")
                return
            }
            guard observed == enabled else {
                reply.send(observed, "High Power Mode did not match the requested state.")
                return
            }
            reply.send(observed, nil)
        }
    }

    func readDisableSleep(withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            guard let enabled = await runner.currentDisableSleep() else {
                reply.send(false, "Disable sleep state is unavailable.")
                return
            }
            reply.send(enabled, nil)
        }
    }

    func setDisableSleep(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let reply = PowerHelperReply(reply)
        let runner = self.runner
        Task {
            do {
                try await runner.setDisableSleep(enabled: enabled)
            } catch {
                reply.send(false, error.localizedDescription)
                return
            }
            // Reply with the state the daemon observes after the change so the app
            // never has to assume the write took.
            reply.send(await runner.currentDisableSleep() ?? enabled, nil)
        }
    }
}

/// The XPC reply block is an Objective-C closure, which the importer cannot
/// prove `Sendable`. The connection calls it exactly once, so handing it to the
/// detached task is safe.
private final class PowerHelperReply<Value>: @unchecked Sendable {
    private let reply: (Value, String?) -> Void

    init(_ reply: @escaping (Value, String?) -> Void) {
        self.reply = reply
    }

    func send(_ value: Value, _ errorDescription: String?) {
        reply(value, errorDescription)
    }
}
