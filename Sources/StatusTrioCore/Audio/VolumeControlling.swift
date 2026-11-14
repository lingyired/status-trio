import CoreAudio

@MainActor
protocol VolumeControlling: AnyObject {
    func setVolume(_ scalar: Double)
    func toggleMute()
    func selectOutputDevice(_ deviceID: AudioDeviceID)
    func selectOutputAutomatically(_ deviceID: AudioDeviceID, request: AudioPriorityRequest,
                                   completion: @escaping AudioPriorityCompletion)
    func flushPendingVolume()
}

extension VolumeControlling {
    func selectOutputAutomatically(_ deviceID: AudioDeviceID, request: AudioPriorityRequest,
                                   completion: @escaping AudioPriorityCompletion) { completion(false) }
    func flushPendingVolume() {}
}
