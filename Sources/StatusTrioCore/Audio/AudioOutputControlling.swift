import CoreAudio

@MainActor
protocol AudioOutputControlling: AnyObject {
    func enqueueManualSelection(_ deviceID: AudioDeviceID, completion: @escaping AudioPriorityCompletion)
    func selectAutomatically(_ deviceID: AudioDeviceID, request: AudioPriorityRequest,
                             completion: @escaping AudioPriorityCompletion)
    @discardableResult func setVolume(_ scalar: Double) -> Bool
    @discardableResult func toggleMute() -> Bool
    @discardableResult func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool
}

extension AudioOutputControlling {
    func enqueueManualSelection(_ deviceID: AudioDeviceID, completion: @escaping AudioPriorityCompletion) {
        completion(selectOutputDevice(deviceID))
    }
    func selectAutomatically(_ deviceID: AudioDeviceID, request: AudioPriorityRequest,
                             completion: @escaping AudioPriorityCompletion) {
        guard request.isValid else { completion(false); return }
        completion(selectOutputDevice(deviceID))
    }
}
