import AppKit
import Foundation

/// macOS's "Play feedback when volume is changed" switch, the one next to
/// "Output volume" in System Settings › Sound.
///
/// The switch is a `Bool` stored under a *dotted key* inside the global domain:
/// `defaults read -g com.apple.sound.beep.feedback`, which lives in
/// `~/Library/Preferences/.GlobalPreferences.plist`. The dotted name is the key
/// itself and there is no `com.apple.sound` domain, so reading
/// `UserDefaults(suiteName: "com.apple.sound")` with `beep.feedback` returns
/// nothing — the value has to come through the standard search list, which
/// includes the global domain.
enum SystemVolumeFeedbackPreference {
    static let key = "com.apple.sound.beep.feedback"

    /// A Mac whose owner has never touched the checkbox keeps the value macOS
    /// ships, which is on, so a missing key counts as enabled. The two
    /// neighbouring keys behave the same way: `.GlobalPreferences.plist` spells
    /// out `com.apple.sound.beep.flash = 0` even though that switch is off by
    /// default.
    ///
    /// The decision is split out from the lookup so the missing-key case can be
    /// tested without this Mac's own setting getting involved: a
    /// `UserDefaults(suiteName:)` instance keeps the standard domains behind its
    /// own, `NSGlobalDomain` included, so a fresh suite still reads whatever the
    /// machine is set to. Only a Mac that has never written the key reads `nil`.
    static func isEnabled(storedValue: Any?) -> Bool {
        guard let storedValue else { return true }
        return (storedValue as? NSNumber)?.boolValue ?? true
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(storedValue: defaults.object(forKey: key))
    }
}

/// Coalesces a burst of volume changes into one tick per interval.
struct VolumeFeedbackThrottle {
    /// The tick is 40 ms long and a scroll gesture delivers events far faster
    /// than that. One tick per interval keeps a fast scroll sounding like the
    /// system's own repeated tick rather than a stutter.
    static let minimumInterval: TimeInterval = 0.1

    private var lastPlayedAt: TimeInterval?

    mutating func shouldPlay(at timestamp: TimeInterval) -> Bool {
        if let lastPlayedAt, timestamp - lastPlayedAt < Self.minimumInterval {
            return false
        }
        lastPlayedAt = timestamp
        return true
    }
}

/// Plays the tick bundled with the app, gated on the system switch.
@MainActor
final class VolumeFeedbackPlayer: VolumeFeedbackPlaying {
    /// The bundled tick is our own synthesis of the system sound's shape (see
    /// `scripts/generate-volume-feedback-sound.py`). macOS's own file sits at a
    /// private path that moves between releases and is Apple's to ship, so it
    /// cannot be bundled.
    ///
    /// `nonisolated` so the default argument of the initializer can name it:
    /// a `@MainActor` function value cannot convert to the plain closure type.
    nonisolated static func bundledSoundURL() -> URL? {
        Bundle.module.url(forResource: "VolumeFeedback", withExtension: "wav")
    }

    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let soundURL: () -> URL?
    /// The playback itself, injectable so a test can observe the tick without
    /// making a sound. It restarts the tick rather than layering a second voice
    /// over the one still ringing, the way the system cancels its own beep.
    private let playback: (NSSound) -> Void
    private var throttle = VolumeFeedbackThrottle()
    private var sound: NSSound?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        soundURL: @escaping () -> URL? = VolumeFeedbackPlayer.bundledSoundURL,
        playback: @escaping (NSSound) -> Void = { sound in
            sound.stop()
            sound.play()
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.soundURL = soundURL
        self.playback = playback
    }

    func playVolumeChangeFeedback() {
        guard SystemVolumeFeedbackPreference.isEnabled(in: defaults) else { return }
        guard throttle.shouldPlay(at: now()) else { return }
        guard let sound = loadedSound() else { return }
        playback(sound)
    }

    private func loadedSound() -> NSSound? {
        if let sound { return sound }
        guard let url = soundURL() else { return nil }
        let loaded = NSSound(contentsOf: url, byReference: true)
        sound = loaded
        return loaded
    }
}
