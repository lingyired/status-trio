import Foundation

/// Stable, language-neutral diagnostic codes for the lid-close sleep helper
/// (#383).
///
/// The daemon prefixes its XPC error payload with one of these codes so a user
/// report ("我点合盖不睡眠提示错误码 DS-R4") can be triaged quickly instead of
/// collapsing every failure into one vague message.
///
/// The code travels inside the existing `String?` error channel, so neither the
/// XPC signature nor the protocol version changes: an older helper simply sends
/// human text with no code, and the app falls back to `readUnavailable`.
public enum DisableSleepDiagnostic: String, CaseIterable, Sendable {
    /// Read failures from `readDisableSleep`.
    case readPmsetLaunchFailed = "DS-R1"
    case readPmsetTimedOut = "DS-R2"
    case readPmsetNonZeroExit = "DS-R3"
    case readKeyMissing = "DS-R4"
    case readValueUnparseable = "DS-R5"
    /// Unclassified read failure, and the fallback code an older helper's
    /// codeless message decodes to.
    case readUnavailable = "DS-R0"

    /// Write failures from `setDisableSleep`.
    case writePmsetLaunchFailed = "DS-W1"
    case writePmsetTimedOut = "DS-W2"
    case writePmsetNonZeroExit = "DS-W3"
    case writeObservedMismatch = "DS-W4"

    /// Formats the wire payload: `"DS-R4"` or `"DS-R4: <detail>"`.
    public func wireString(detail: String = "") -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? rawValue : "\(rawValue): \(trimmed)"
    }

    /// Splits a daemon error payload back into its code and human detail.
    ///
    /// A payload without a recognizable prefix belongs to an older helper; the
    /// whole string is returned as detail with `code == nil`.
    public static func decode(_ raw: String?) -> (code: DisableSleepDiagnostic?, detail: String) {
        guard let raw, !raw.isEmpty else { return (nil, "") }
        for diagnostic in allCases {
            if raw == diagnostic.rawValue { return (diagnostic, "") }
            let prefix = diagnostic.rawValue + ": "
            if raw.hasPrefix(prefix) {
                return (diagnostic, String(raw.dropFirst(prefix.count)))
            }
        }
        return (nil, raw)
    }
}
