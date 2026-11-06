import Foundation
import PowerHelperProtocol

/// Read-only High Power Mode state from `pmset`. The details page only needs
/// the system's answer; the privileged helper stays responsible for writes.
struct HighPowerModeSystemStatus: Equatable, Sendable {
    let supported: Bool
    let enabled: Bool?
}

enum HighPowerModeSystemReader {
    static func read(timeout: Duration = .seconds(3)) -> HighPowerModeSystemStatus? {
        guard let capabilities = run(["-g", "cap"], timeout: timeout) else { return nil }
        guard !capabilities.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let supported = HighPowerModeCommand.isSupported(fromCapabilitiesOutput: capabilities)
        guard supported else { return HighPowerModeSystemStatus(supported: false, enabled: nil) }
        // A failed `-g` read is reported as unknown, not as Off.
        let enabled = run(["-g"], timeout: timeout)
            .flatMap(HighPowerModeCommand.parseEnabled(fromPmsetOutput:))
        return HighPowerModeSystemStatus(supported: supported, enabled: enabled)
    }

    private static func run(_ arguments: [String], timeout: Duration) -> String? {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/usr/bin/pmset"),
            arguments: arguments,
            timeout: timeout
        )
        guard case let .exited(data) = outcome else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
