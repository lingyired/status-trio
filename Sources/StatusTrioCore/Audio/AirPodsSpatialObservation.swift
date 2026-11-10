import CoreAudio
import Foundation

/// Menu-owned HAL registrations. Retain the exact blocks for removal, including
/// when the owning model is released without an explicit dismissal callback.
final class AirPodsSpatialObservation {
    static let selectors: [AudioObjectPropertySelector] = [
        0x73706176, // spav: availability
        0x61637363, // acsc: active media client
        0x73706366, // spcf: saved configuration
        0x73706373, // spcs: multichannel spatialization
        0x73707373, // spss: stereo spatialization
        0x68747374, // htst: head tracking
        kAudioDevicePropertyDeviceIsRunningSomewhere
    ]
    private let backend: any BluetoothListeningModePropertyListening
    private let subscriptions: [BluetoothListeningModeSubscription]

    init(deviceID: AudioDeviceID, backend: any BluetoothListeningModePropertyListening,
         changed: @escaping @Sendable () -> Void) {
        self.backend = backend
        subscriptions = Self.selectors.compactMap { selector in
            let address = BluetoothListeningModeProperty.address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
            guard backend.addListener(deviceID: deviceID, address: address, queue: .main, block: block) == noErr else {
                return nil
            }
            return .init(deviceID: deviceID, address: address, queue: .main, block: block)
        }
    }

    deinit {
        for subscription in subscriptions {
            _ = backend.removeListener(deviceID: subscription.deviceID, address: subscription.address,
                                       queue: subscription.queue, block: subscription.block)
        }
    }
}
