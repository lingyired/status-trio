import Foundation

/// The charge limit macOS enforces on the internal battery, read from the
/// preference `powerd` rewrites whenever the limit changes.
///
/// No public API exposes it: `pmset -g`, `system_profiler SPPowerDataType`, and
/// IOKit's `AppleSmartBattery` all omit the value, so the plist is the only
/// source. It is world-readable (644, root-owned) and the app is not sandboxed,
/// so reading it needs no entitlement and no authorization prompt.
///
/// The layout is private and undocumented: a binary plist whose `policies` entry
/// is an `NSKeyedArchiver` array of `ChargeCtrlPolicy` objects. That class lives
/// inside `powerd`, so a plain unarchive fails in our process — the class has to
/// be registered under its archived name first. Every field is read
/// defensively, because a future macOS is free to rename or drop any of them,
/// and a reader that force-unwrapped would take the app down with it.
struct SystemChargeLimitReading: Equatable, Sendable {
    /// The percentage the system stops charging at.
    let limit: Int
    /// Why the limit exists — a user-picked limit, or one `powerd` derived.
    let reason: String?

    /// Whether the user picked this limit in System Settings, as opposed to a
    /// policy `powerd` maintains on its own.
    var isUserPicked: Bool {
        reason == SystemChargeLimitReader.userPickedReason
    }
}

enum SystemChargeLimitReader {
    /// The plist `powerd` rewrites when the charge limit changes.
    static let defaultURL = URL(
        fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist"
    )

    /// The reason that marks a limit the user picked, rather than one `powerd`
    /// derived on its own. `reason` is only advisory: a limit is honoured
    /// whatever it says, and the value is what the setting follows.
    static let userPickedReason = "manualChargeLimit"

    /// - Parameter url: The plist to read. Injectable so the parser can be
    ///   tested against recorded archives instead of the live file.
    /// - Returns: The charge limit, or `nil` when there is no limit or the
    ///   plist cannot be read or parsed.
    static func chargeLimit(from url: URL = defaultURL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return chargeLimit(in: data)
    }

    /// Parses the plist body. Exposed so tests can feed recorded archives,
    /// including ones that no longer match the current layout.
    static func chargeLimit(in data: Data) -> Int? {
        guard let policies = policiesData(in: data) else { return nil }

        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: policies)
            // `ChargeCtrlPolicy` is not a secure-coding class and is absent
            // from this process; both must be relaxed or the decode throws.
            unarchiver.requiresSecureCoding = false
            unarchiver.setClass(
                ChargeCtrlPolicyPlaceholder.self,
                forClassName: "ChargeCtrlPolicy"
            )
            let decoded = unarchiver.decodeObject(
                forKey: NSKeyedArchiveRootObjectKey
            ) as? [ChargeCtrlPolicyPlaceholder]
            return decoded?.compactMap(\.limit).first
        } catch {
            return nil
        }
    }

    /// The `policies` payload of the outer plist, or `nil` when the outer shape
    /// is not what this reader expects.
    private static func policiesData(in data: Data) -> Data? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else { return nil }

        guard let policies = plist["policies"] as? Data, !policies.isEmpty else {
            return nil
        }
        return policies
    }
}

/// A stand-in for `powerd`'s private `ChargeCtrlPolicy`.
///
/// `NSKeyedUnarchiver` instantiates this instead of the real class, so the
/// archived field names are the contract. Anything that stops decoding simply
/// leaves the default value in place, which the reader treats as "no limit".
///
/// Internal rather than private only because `NSCoding` refuses to archive a
/// class whose name it cannot emit; tests build recorded archives with it.
final class ChargeCtrlPolicyPlaceholder: NSObject, NSCoding {
    let limit: Int
    let reason: String?

    /// Lets a test build an archive to decode, which `init(coder:)` alone
    /// cannot do because `NSKeyedArchiver` is abstract.
    init(limit: Int, reason: String?) {
        self.limit = limit
        self.reason = reason
    }

    required init?(coder: NSCoder) {
        self.limit = coder.decodeInteger(forKey: "soclimit")
        self.reason = coder.decodeObject(forKey: "reason") as? String
    }

    func encode(with coder: NSCoder) {
        coder.encode(limit, forKey: "soclimit")
        coder.encode(reason, forKey: "reason")
    }
}
