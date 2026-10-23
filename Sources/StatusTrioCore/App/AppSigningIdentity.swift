import Foundation
import Security

/// The app's own code-signing identity, read from the running process rather
/// than from `Info.plist`.
///
/// The privileged helper authorizes callers by bundle identifier and team, so
/// the app can only offer its toggle when this process actually carries that
/// identity. `Info.plist` is not evidence: an Ad-hoc build or a worktree build
/// with a rewritten `BUNDLE_ID` has no team at all, yet still reads the same
/// bundle identifier from its plist.
enum AppSigningIdentity {
    struct Identity: Equatable {
        let bundleIdentifier: String
        let teamIdentifier: String
    }

    /// `nil` for an unsigned or Ad-hoc signed build, and whenever the signature
    /// cannot be read. Both mean the daemon's requirement cannot be met.
    static func current() -> Identity? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String
        else { return nil }
        return Identity(bundleIdentifier: identifier, teamIdentifier: teamIdentifier)
    }
}
