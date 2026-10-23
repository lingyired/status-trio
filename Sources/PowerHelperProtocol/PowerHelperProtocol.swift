import Foundation

/// The Mach service the privileged power helper listens on. Kept in a
/// dependency-free target so both the app and the daemon can name it without
/// pulling AppKit, SwiftUI, or Sparkle into the root daemon.
public enum PowerHelperConstants {
    /// Must match `MachServices` in the LaunchDaemon property list and the
    /// `SMAppService.daemon(plistName:)` registration in the app.
    public static let machServiceName = "com.lingsmbp.StatusTrio.PowerHelper"
    /// The LaunchDaemon property list's file name, relative to
    /// `Contents/Library/LaunchDaemons/`.
    public static let launchDaemonPlistName = "com.lingsmbp.StatusTrio.PowerHelper.plist"
    /// The app bundle identifier and signing team the daemon authorizes.
    ///
    /// Defined once here rather than in the requirement string and again in the
    /// daemon's authorization code: the requirement the daemon enforces and the
    /// identity the app checks itself against must never drift apart.
    public static let clientBundleIdentifier = "com.lingsmbp.StatusTrio"
    public static let clientTeamIdentifier = "HCB7JKMQ2F"

    /// The daemon's signing requirement, used by the daemon to authorize a
    /// connecting client and by the app to describe the helper it expects.
    public static let clientRequirement = clientRequirementString()

    /// Builds the same requirement for an injected identity.
    ///
    /// `build-app.sh`/`build-worktree.sh` can change the bundle identifier, so
    /// the pieces are named values a caller can compare against instead of
    /// parsing them back out of the requirement string.
    public static func clientRequirementString(
        bundleIdentifier: String = clientBundleIdentifier,
        teamIdentifier: String = clientTeamIdentifier
    ) -> String {
        "anchor apple generic and identifier \"\(bundleIdentifier)\" "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

/// The XPC surface the privileged helper exposes.
///
/// Deliberately tiny: one boolean read and one boolean write for Low Power
/// Mode. Every operation is a separate call so a failed write cannot be
/// mistaken for a successful read, and the reply carries the state the daemon
/// observed *after* the change rather than echoing the request.
@objc public protocol PowerHelperXPCProtocol {
    /// Reads the current Low Power Mode state.
    ///
    /// `enabled` is the observed value; `errorDescription` is non-nil only when
    /// the state could not be read, in which case `enabled` is meaningless.
    func readLowPowerMode(withReply reply: @escaping (Bool, String?) -> Void)

    /// Sets Low Power Mode and replies with the state the daemon observed
    /// afterwards, so the caller never has to guess whether the write took.
    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
}
