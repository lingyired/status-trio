import Foundation

/// The exact `pmset` invocation the daemon runs to change Low Power Mode, plus
/// a defensive parser for the read side.
///
/// Kept as a pure value so the argument shape is unit-testable without root or
/// a live daemon.
public enum LowPowerModeCommand {
    public static let pmsetPath = "/usr/bin/pmset"

    /// Arguments for `pmset` that turn Low Power Mode on or off.
    ///
    /// `-a` applies the setting to every power profile (battery and charger),
    /// matching the system's own Low Power Mode switch. `lowpowermode` is still
    /// the documented write argument on macOS 26/27 even though `pmset -g` now
    /// reports the unified `powermode` key; `strings /usr/bin/pmset` confirms
    /// both argument names remain accepted.
    public static func arguments(enabled: Bool) -> [String] {
        ["-a", "lowpowermode", enabled ? "1" : "0"]
    }

    /// Parses Low Power Mode out of `pmset -g` output.
    ///
    /// Handles both the classic `lowpowermode 0|1` key and the unified
    /// `powermode` key macOS 26+ prints, where `1` is Low Power Mode. Returns
    /// nil when neither key is present or readable, so a caller never mistakes
    /// "unknown" for "off". This is a cross-check only: the daemon and app read
    /// the authoritative value from `ProcessInfo.isLowPowerModeEnabled`.
    public static func parseEnabled(fromPmsetOutput output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            switch fields[0] {
            case "lowpowermode", "powermode":
                return fields[1] == "1"
            default:
                continue
            }
        }
        return nil
    }
}