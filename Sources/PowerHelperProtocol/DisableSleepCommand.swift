import Foundation

/// The exact `pmset` invocation the daemon runs to toggle lid-close sleep
/// (`disablesleep`), plus a defensive parser for the read side.
///
/// Kept as a pure value so the argument shape and parsing are unit-testable
/// without root or a live daemon. `disablesleep` is issue #295's "keep awake
/// with the lid closed" switch.
public enum DisableSleepCommand {
    /// Arguments that turn `disablesleep` on or off.
    ///
    /// `-a` applies the setting to every power profile, matching the system's own
    /// switch rather than only the active profile.
    public static func arguments(enabled: Bool) -> [String] {
        ["-a", "disablesleep", enabled ? "1" : "0"]
    }

    /// Parses `SleepDisabled` out of `pmset -g` output.
    ///
    /// A real line looks like ` SleepDisabled\t\t1` (leading space, tab
    /// separator). Returns nil when the key is absent so a caller never mistakes
    /// "unknown" for "off".
    public static func parseSleepDisabled(fromPmsetOutput output: String) -> Bool? {
        switch parseSleepDisabledDiagnosed(fromPmsetOutput: output) {
        case .value(let value): return value
        case .keyMissing, .unparseable: return nil
        }
    }

    /// Parser outcome that keeps "key absent" separate from "value unparseable",
    /// so the daemon can report a precise diagnostic code (#383).
    public enum ParseOutcome: Equatable, Sendable {
        case value(Bool)
        case keyMissing
        case unparseable(String)
    }

    public static func parseSleepDisabledDiagnosed(fromPmsetOutput output: String) -> ParseOutcome {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            guard fields[0] == "SleepDisabled" else { continue }
            switch fields[1] {
            case "1": return .value(true)
            case "0": return .value(false)
            default: return .unparseable(String(fields[1]))
            }
        }
        return .keyMissing
    }
}
