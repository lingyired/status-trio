import Foundation

/// The `pmset` arguments, capability probe and read-side parser for the
/// system's High Power Mode, kept as a pure value so the argument shape and
/// parsing are unit-testable without root or a live daemon.
///
/// High Power Mode is one state of the system's single Power Mode switch: a Mac
/// is in Low Power Mode, Automatic, or High Power Mode. It is therefore mutually
/// exclusive with Low Power Mode, which is why the write path clears the other
/// mode before switching (see `SystemPmsetRunner`).
public enum HighPowerModeCommand {
    /// `pmset -g cap` lists the settings this Mac reports support for. A Mac
    /// that can switch to High Power Mode lists `highpowermode`. Probing the
    /// capabilities list follows whatever the running macOS reports instead of
    /// hard-coding a model list that a new machine would fall outside of.
    public static let capabilitiesArguments = ["-g", "cap"]

    /// Arguments that turn High Power Mode on or off.
    ///
    /// macOS 26 unified the Power Mode switch: `powermode` is now the only
    /// accepted write key and takes `0` (Automatic), `1` (Low Power) or `2`
    /// (High Power). The old `highpowermode` argument is rejected by `pmset`
    /// (it prints its usage text), while `lowpowermode` remains accepted as a
    /// compatibility alias. Off means "back to Automatic", not "Low Power".
    ///
    /// `-a` applies the value to every power profile, matching the system's own
    /// Power Mode switch rather than only the active profile.
    public static func arguments(enabled: Bool) -> [String] {
        ["-a", "powermode", enabled ? "2" : "0"]
    }

    /// Whether `pmset -g cap` output advertises High Power Mode support.
    ///
    /// The capability list is one key per line (no values), so the key is the
    /// first field. Output without the key means the Mac cannot enter High Power
    /// Mode; the caller hides the control instead of exposing a switch that can
    /// only fail.
    public static func isSupported(fromCapabilitiesOutput output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .first == "highpowermode"
        }
    }

    /// Parses High Power Mode out of `pmset -g` / `pmset -g custom` output.
    ///
    /// macOS 26+ reports the unified `powermode` key, where `1` is Low Power and
    /// `2` is High Power (`0` is Automatic). The per-setting `highpowermode` key
    /// is also accepted for outputs that still print it. Returns `nil` when
    /// neither key is present, so "unknown" is never mistaken for "off". A single
    /// high value on any profile is enough: the switch is system-wide.
    public static func parseEnabled(fromPmsetOutput output: String) -> Bool? {
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
                // 0 = Automatic, 1 = Low Power, 2 = High Power.
                if fields[1] == "2" { return true }
            default:
                continue
            }
        }
        return sawPowerModeKey ? false : nil
    }
}
