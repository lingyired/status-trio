import Foundation
import PowerHelperProtocol

/// Runs `pmset` on behalf of the daemon. Injected so the daemon's decision
/// logic can be exercised without root.
protocol PmsetRunning: Sendable {
    func setLowPowerMode(enabled: Bool) async throws
    func currentLowPowerMode() async -> Bool?
}

enum PmsetError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32)
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .launchFailed(reason): "pmset could not be launched: \(reason)"
        case let .nonZeroExit(code): "pmset exited with status \(code)"
        case .timedOut: "pmset did not finish in time"
        }
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
        let outcome = try await run(
            arguments: LowPowerModeCommand.arguments(enabled: enabled),
            capturesOutput: false
        )
        guard let status = outcome.status else { throw PmsetError.timedOut }
        guard status == 0 else { throw PmsetError.nonZeroExit(status) }
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

    private struct Outcome {
        /// `nil` when the timeout fired before the child exited.
        let status: Int32?
        let output: String
    }

    private func run(arguments: [String], capturesOutput: Bool) async throws -> Outcome {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        // Nothing reads these pipes, so a child that writes must never be able
        // to fill one and block forever: both go to the null device, and stdout
        // is only piped when the caller actually parses it.
        process.standardError = FileHandle.nullDevice
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
        let output = stdoutPipe.map {
            String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } ?? ""
        return Outcome(status: status, output: output)
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
}

/// The XPC reply block is an Objective-C closure, which the importer cannot
/// prove `Sendable`. The connection calls it exactly once, so handing it to the
/// detached task is safe.
private final class PowerHelperReply: @unchecked Sendable {
    private let reply: (Bool, String?) -> Void

    init(_ reply: @escaping (Bool, String?) -> Void) {
        self.reply = reply
    }

    func send(_ enabled: Bool, _ errorDescription: String?) {
        reply(enabled, errorDescription)
    }
}
