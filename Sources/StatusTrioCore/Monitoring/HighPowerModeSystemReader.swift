import Foundation
import PowerHelperProtocol

/// Read-only High Power Mode state from `pmset`. The details page only needs
/// the system's answer; the privileged helper stays responsible for writes.
struct HighPowerModeSystemStatus: Equatable, Sendable {
    let supported: Bool
    let enabled: Bool?
}

enum HighPowerModeSystemReader {
    static func read(timeout: TimeInterval = 3) -> HighPowerModeSystemStatus? {
        guard let capabilities = run(["-g", "cap"], timeout: timeout) else { return nil }
        let supported = HighPowerModeCommand.isSupported(fromCapabilitiesOutput: capabilities)
        let enabled = run(["-g"], timeout: timeout)
            .flatMap(HighPowerModeCommand.parseEnabled(fromPmsetOutput:))
        return HighPowerModeSystemStatus(supported: supported, enabled: enabled)
    }

    private static func run(_ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
