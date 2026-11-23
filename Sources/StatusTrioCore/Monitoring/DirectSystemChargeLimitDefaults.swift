import Foundation

extension SystemChargeLimitReader {
    /// Installs the Direct-only, private `powerd` charge-limit plist path. Called
    /// once at Direct launch; Store never calls this so `defaultURL` stays nil.
    static func installDirectDefaults() {
        defaultURL = URL(
            fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist"
        )
    }
}
