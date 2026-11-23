import Foundation

extension SystemVolumeFeedbackPreference {
    /// Installs the real system "play feedback" key. Direct-only; Store never
    /// calls this, keeping the app-owned inert default.
    static func installDirectDefaults() {
        key = "com.apple.sound.beep.feedback"
    }
}
