import CoreAudio

@MainActor
protocol AudioOutputControlling: AnyObject {
    @discardableResult func setVolume(_ scalar: Double) -> Bool
    @discardableResult func toggleMute() -> Bool
    @discardableResult func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool
    /// Whether this app currently owns an automatic mute on the given device.
    func isAutoMuted(for deviceID: AudioDeviceID) -> Bool
    /// Drops any automatic-mute ownership after a topology/device transition.
    func invalidateAutoMuteState()
}

extension AudioOutputControlling {
    func isAutoMuted(for deviceID: AudioDeviceID) -> Bool { false }
    func invalidateAutoMuteState() {}
}
