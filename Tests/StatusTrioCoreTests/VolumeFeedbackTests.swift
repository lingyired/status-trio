import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

/// Records the ticks a player asked for, so the gate and the coalescing can be
/// asserted without making a sound.
@MainActor
final class FakeVolumeFeedbackPlayer: VolumeFeedbackPlaying {
    private(set) var playCount = 0

    func playVolumeChangeFeedback() { playCount += 1 }
}

/// A clock the test moves by hand.
private final class MutableClock {
    var now: TimeInterval = 0
}

@MainActor
struct VolumeFeedbackTests {
    private func isolatedDefaults(
        _ testName: String
    ) throws -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.VolumeFeedback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    @Test func preferenceFollowsTheGlobalDomainKey() throws {
        let (defaults, name) = try isolatedDefaults(#function)
        defer { TestUserDefaults.removeSuite(named: name) }

        defaults.set(false, forKey: SystemVolumeFeedbackPreference.key)
        #expect(!SystemVolumeFeedbackPreference.isEnabled(in: defaults))

        defaults.set(true, forKey: SystemVolumeFeedbackPreference.key)
        #expect(SystemVolumeFeedbackPreference.isEnabled(in: defaults))
    }

    /// Covers the missing-key fallback through the pure entry point rather than
    /// a suite: a suite's search list still ends at `NSGlobalDomain`, so a suite
    /// with no value of its own reads this Mac's setting, and an assertion built
    /// on that passes or fails with the developer's own checkbox.
    @Test func preferenceTreatsAMissingKeyAsEnabled() {
        #expect(SystemVolumeFeedbackPreference.isEnabled(storedValue: nil))
        #expect(SystemVolumeFeedbackPreference.isEnabled(storedValue: true))
        #expect(!SystemVolumeFeedbackPreference.isEnabled(storedValue: false))
    }

    /// The app switch follows the system switch until the user stores a value,
    /// then that explicit value wins over the system switch either way (#194).
    @Test func appSwitchFollowsSystemUntilAnExplicitValueIsStored() {
        #expect(VolumeScrollFeedbackPreference.isEnabled(storedValue: nil, systemEnabled: true))
        #expect(!VolumeScrollFeedbackPreference.isEnabled(storedValue: nil, systemEnabled: false))
        #expect(VolumeScrollFeedbackPreference.isEnabled(storedValue: true, systemEnabled: false))
        #expect(!VolumeScrollFeedbackPreference.isEnabled(storedValue: false, systemEnabled: true))
        // A non-boolean stored value is treated as "not set" and follows the system.
        #expect(VolumeScrollFeedbackPreference.isEnabled(storedValue: "yes", systemEnabled: true))
    }

    @Test func throttleCoalescesABurstIntoOneTickPerInterval() {
        var throttle = VolumeFeedbackThrottle()

        // The calls are kept out of `#expect`: the macro captures its operands
        // immutably, so a `mutating` call cannot be written inline. The base is
        // zero because `10.1 - 10` rounds below the interval and would make the
        // boundary case read as "not yet".
        let first = throttle.shouldPlay(at: 0)
        let insideInterval = throttle.shouldPlay(at: 0.05)
        let justBeforeInterval = throttle.shouldPlay(at: 0.099)
        let atInterval = throttle.shouldPlay(at: 0.1)
        let afterInterval = throttle.shouldPlay(at: 0.4)

        #expect(first)
        #expect(!insideInterval)
        #expect(!justBeforeInterval)
        #expect(atInterval)
        #expect(afterInterval)
    }

    @Test func bundledTickIsPresentAndDecodable() throws {
        let url = try #require(VolumeFeedbackPlayer.bundledSoundURL())
        #expect(FileManager.default.fileExists(atPath: url.path))

        let sound = try #require(NSSound(contentsOf: url, byReference: true))
        #expect(sound.duration > 0.01)
        #expect(sound.duration < 0.2)
    }

    @Test func playerStaysSilentWhenTheSystemSwitchIsOff() throws {
        let (defaults, name) = try isolatedDefaults(#function)
        defer { TestUserDefaults.removeSuite(named: name) }
        defaults.set(false, forKey: SystemVolumeFeedbackPreference.key)

        let clock = MutableClock()
        var played = 0
        let player = VolumeFeedbackPlayer(
            defaults: defaults,
            now: { clock.now },
            soundURL: VolumeFeedbackPlayer.bundledSoundURL,
            playback: { _ in played += 1 }
        )

        player.playVolumeChangeFeedback()
        clock.now = 1
        player.playVolumeChangeFeedback()

        #expect(played == 0)
    }

    /// The app switch can turn the tick on even when the macOS switch is off,
    /// and off even when the macOS switch is on (#194).
    @Test func playerObeysTheAppSwitchRegardlessOfTheSystemSwitch() throws {
        let (defaults, name) = try isolatedDefaults(#function)
        defer { TestUserDefaults.removeSuite(named: name) }
        defaults.set(false, forKey: SystemVolumeFeedbackPreference.key)
        defaults.set(true, forKey: VolumeScrollFeedbackPreference.key)

        var played = 0
        let player = VolumeFeedbackPlayer(
            defaults: defaults,
            now: { 0 },
            soundURL: VolumeFeedbackPlayer.bundledSoundURL,
            playback: { _ in played += 1 }
        )

        player.playVolumeChangeFeedback()
        #expect(played == 1)

        defaults.set(true, forKey: SystemVolumeFeedbackPreference.key)
        defaults.set(false, forKey: VolumeScrollFeedbackPreference.key)

        let muted = VolumeFeedbackPlayer(
            defaults: defaults,
            now: { 0 },
            soundURL: VolumeFeedbackPlayer.bundledSoundURL,
            playback: { _ in played += 1 }
        )
        muted.playVolumeChangeFeedback()
        #expect(played == 1)
    }

    @Test func playerPlaysOneTickPerInterval() throws {
        let (defaults, name) = try isolatedDefaults(#function)
        defer { TestUserDefaults.removeSuite(named: name) }
        defaults.set(true, forKey: SystemVolumeFeedbackPreference.key)

        let clock = MutableClock()
        var played = 0
        let player = VolumeFeedbackPlayer(
            defaults: defaults,
            now: { clock.now },
            soundURL: VolumeFeedbackPlayer.bundledSoundURL,
            playback: { _ in played += 1 }
        )

        player.playVolumeChangeFeedback()
        #expect(played == 1)

        clock.now = 0.05
        player.playVolumeChangeFeedback()
        #expect(played == 1)

        clock.now = 0.15
        player.playVolumeChangeFeedback()
        #expect(played == 2)
    }

    @Test func playerStaysSilentWhenTheTickIsMissing() throws {
        let (defaults, name) = try isolatedDefaults(#function)
        defer { TestUserDefaults.removeSuite(named: name) }
        defaults.set(true, forKey: SystemVolumeFeedbackPreference.key)

        var played = 0
        let player = VolumeFeedbackPlayer(
            defaults: defaults,
            now: { 0 },
            soundURL: { nil },
            playback: { _ in played += 1 }
        )

        player.playVolumeChangeFeedback()

        #expect(played == 0)
    }
}
