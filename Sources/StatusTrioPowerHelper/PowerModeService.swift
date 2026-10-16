import Foundation
import PowerHelperProtocol

/// Runs `pmset` on behalf of the daemon. Injected so the daemon's decision
/// logic can be exercised without root.
protocol PmsetRunning: Sendable {
    func setLowPowerMode(enabled: Bool) throws
    func currentLowPowerMode() -> Bool?
}

enum PmsetError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(reason): "pmset could not be launched: \(reason)"
        case let .nonZeroExit(code): "pmset exited with status \(code)"
        }
    }
}

/// Production runner: spawns `/usr/bin/pmset` with the argument shape owned by
/// `LowPowerModeCommand`.
struct SystemPmsetRunner: PmsetRunning {
    func setLowPowerMode(enabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: LowPowerModeCommand.pmsetPath)
        process.arguments = LowPowerModeCommand.arguments(enabled: enabled)
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw PmsetError.launchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PmsetError.nonZeroExit(process.terminationStatus)
        }
    }

    func currentLowPowerMode() -> Bool? {
        // Read the system state from `pmset -g` rather than
        // `ProcessInfo.isLowPowerModeEnabled`: that value is cached per process
        // and only refreshes when the process receives a power-state-change
        // notification, so a freshly started daemon reports `false` even when the
        // system is in Low Power Mode.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: LowPowerModeCommand.pmsetPath)
        process.arguments = ["-g"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return LowPowerModeCommand.parseEnabled(fromPmsetOutput: output)
    }
}

/// The object the daemon exports over XPC.
final class PowerModeService: NSObject, PowerHelperXPCProtocol {
    private let runner: any PmsetRunning

    init(runner: any PmsetRunning = SystemPmsetRunner()) {
        self.runner = runner
    }

    func readLowPowerMode(withReply reply: @escaping (Bool, String?) -> Void) {
        guard let enabled = runner.currentLowPowerMode() else {
            reply(false, "Low Power Mode state is unavailable.")
            return
        }
        reply(enabled, nil)
    }

    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try runner.setLowPowerMode(enabled: enabled)
        } catch {
            reply(false, error.localizedDescription)
            return
        }
        // Reply with the state the daemon observes after the change so the app
        // never has to assume the write took.
        reply(runner.currentLowPowerMode() ?? enabled, nil)
    }
}