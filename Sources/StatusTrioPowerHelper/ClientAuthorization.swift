import Foundation
import Security

/// The code-signing requirement the daemon demands of every connecting client.
///
/// `anchor apple generic` proves the peer is signed by an Apple-issued
/// certificate, `identifier` pins the app's bundle identifier, and the team OU
/// pins the signing team. All three are required: an Ad-hoc or differently
/// signed process fails this, which is the point — a root daemon that accepted
/// any client could be driven by any local process.
enum ClientRequirement {
    static let teamIdentifier = "HCB7JKMQ2F"
    static let bundleIdentifier = "com.lingsmbp.StatusTrio"

    static let string =
        "anchor apple generic and identifier \"\(bundleIdentifier)\" "
        + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
}

/// Second-opinion authorization check run inside the listener delegate.
///
/// The authoritative gate is `NSXPCListener.setConnectionCodeSigningRequirement`
/// (audit-token based, evaluated by Foundation before the delegate runs). This
/// check re-validates the peer by PID and only logs/denies on mismatch, so a
/// regression in the listener requirement cannot silently open the daemon.
enum ClientAuthorization {
    static func isCallerAllowed(_ connection: NSXPCConnection) -> Bool {
        var code: SecCode?
        let attributes: [CFString: Any] = [kSecGuestAttributePid: connection.processIdentifier]
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess,
              let guest = code else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(ClientRequirement.string as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(guest, [], requirement) == errSecSuccess
    }
}