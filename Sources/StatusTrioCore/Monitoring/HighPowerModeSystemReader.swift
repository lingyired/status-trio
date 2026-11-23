import Foundation

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
        let supported = Self.isSupported(fromCapabilitiesOutput: capabilities)
        guard supported else { return HighPowerModeSystemStatus(supported: false, enabled: nil) }
        // A failed `-g` read is reported as unknown, not as Off.
        let enabled = run(["-g"], timeout: timeout)
            .flatMap(Self.parseEnabled(fromPmsetOutput:))
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

    // MARK: - Pure `pmset` parsing
    //
    // Kept inline so this shared reader does not import the Direct-only
    // `PowerHelperProtocol` module. The helper daemon keeps its own copy
    // (`HighPowerModeCommand`) for the same argument shape; both are pure.

    /// Whether `pmset -g cap` output advertises High Power Mode support.
    static func isSupported(fromCapabilitiesOutput output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .first == "highpowermode"
        }
    }

    /// Parses High Power Mode out of `pmset -g` / `pmset -g custom` output.
    /// Returns `nil` when neither key is present (unknown, never "off").
    static func parseEnabled(fromPmsetOutput output: String) -> Bool? {
        var sawPowerModeKey = false
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            switch fields[0] {
            case "highpowermode":
                sawPowerModeKey = true
                if fields[1] == "1" { return true }
            case "powermode":
                sawPowerModeKey = true
                if fields[1] == "2" { return true }
            default:
                continue
            }
        }
        return sawPowerModeKey ? false : nil
    }
}
