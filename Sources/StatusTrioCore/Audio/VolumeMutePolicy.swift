import Foundation

/// Runtime-only ownership of Status Trio's own automatic mute.
///
/// When the user drives the output volume to exactly zero, the app mutes the
/// device itself so a 0% slider is genuinely silent (some 3.5 mm outputs still
/// leak audio at scalar 0). That mute is different from a mute the user set on
/// purpose: raising the volume must restore sound only for the former, and a
/// manual mute must survive ordinary level changes.
///
/// The ownership is bound to the current output device's UID and lives only for
/// the process lifetime; it is never persisted. A device change drops it.
struct VolumeMutePolicy: Equatable, Sendable {
    private(set) var autoMutedDeviceUID: String?

    /// Drops any ownership that belongs to a different output device.
    mutating func reconcileDevice(_ deviceUID: String?) {
        if autoMutedDeviceUID != deviceUID {
            autoMutedDeviceUID = nil
        }
    }

    /// Drops ownership, e.g. on topology changes or when the user takes over mute.
    mutating func invalidate() {
        autoMutedDeviceUID = nil
    }

    func ownsAutoMute(deviceUID: String?) -> Bool {
        guard let autoMutedDeviceUID else { return false }
        return autoMutedDeviceUID == deviceUID
    }

    /// Decides the mute write that should follow a successful scalar write.
    ///
    /// Returns true/false to write the device Mute property, or nil to leave the
    /// mute state untouched. The check is driven by the real target scalar,
    /// never by the rounded percentage the UI shows.
    mutating func muteActionAfterWritingVolume(
        target: Double,
        deviceUID: String?,
        currentlyMuted: Bool,
        canMute: Bool
    ) -> Bool? {
        reconcileDevice(deviceUID)

        let clamped = min(1, max(0, target))
        guard clamped == 0 else {
            // Raising the level restores sound only when this app muted the
            // device automatically. A user's manual mute is left alone.
            guard ownsAutoMute(deviceUID: deviceUID) else { return nil }
            autoMutedDeviceUID = nil
            return currentlyMuted ? false : nil
        }

        guard canMute else {
            // No mute capability: volume 0 still applies; nothing to own.
            autoMutedDeviceUID = nil
            return nil
        }

        if currentlyMuted {
            // Already muted. Keep ownership only when this app set it; a user's
            // manual mute must not be claimed or cleared.
            return nil
        }

        autoMutedDeviceUID = deviceUID
        return true
    }
}

/// Pure read-back check for a precise-zero write. A readable element still above
/// a small epsilon means the device did not fully reach zero, so a partial
/// multichannel write is not reported as full success.
enum ZeroVolumeVerification {
    static let epsilon: Float32 = 0.001

    static func allZero(_ values: [Float32?]) -> Bool {
        for value in values {
            guard let value, value.isFinite else { continue }
            if value > epsilon { return false }
        }
        return true
    }
}
