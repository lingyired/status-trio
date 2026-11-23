import CoreAudio
import Foundation

@testable import StatusTrioCore

/// A discovery source that always finds nothing, so a view test that renders a
/// `BluetoothListeningModeController` never touches the machine's real CoreAudio
/// devices and its layout stays deterministic regardless of what is paired to the
/// test runner.
struct EmptyListeningModeEndpointProvider: CoreAudioBluetoothEndpointProviding {
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        []
    }
}

/// A listener seam that records add/remove pairs and lets a test fire the stored
/// block on demand, so the controller's external-change path can be exercised
/// without a real CoreAudio endpoint.
///
/// The registration is keyed by `AudioDeviceID`. A test flips the scripted
/// backend's stored mode, calls `trigger(deviceID:)` to simulate the OS notifying
/// us, and asserts the controller publishes the new `selectedMode`. Removals are
/// recorded by id so a test can also pin that a dropped endpoint or a panel close
/// unsubscribes rather than leaving CoreAudio firing into a controller that has
/// already forgotten the presentation.
final class FakeListeningModeListenerBackend: BluetoothListeningModePropertyListening, @unchecked Sendable {
    struct Registration {
        let address: AudioObjectPropertyAddress
        let queue: DispatchQueue?
        let block: AudioObjectPropertyListenerBlock
    }

    private let lock = NSLock()
    private var registrations: [AudioDeviceID: Registration] = [:]
    private(set) var addCount = 0
    private(set) var removeCount = 0

    func addListener(
        deviceID: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        addCount += 1
        registrations[deviceID] = Registration(address: address, queue: queue, block: block)
        return noErr
    }

    func removeListener(
        deviceID: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        removeCount += 1
        return registrations.removeValue(forKey: deviceID) == nil
            ? kAudioHardwareUnspecifiedError
            : noErr
    }

    /// Whether the seam currently holds a subscription for `deviceID`.
    func hasRegistration(for deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return registrations[deviceID] != nil
    }

    /// Simulates CoreAudio firing the block. A real signal runs on the listener
    /// queue and the controller hops back to MainActor; tests call this from any
    /// thread and await the resulting publication with `waitUntil`.
    func trigger(deviceID: AudioDeviceID) {
        lock.lock()
        let registration = registrations[deviceID]
        lock.unlock()
        guard let registration else { return }
        var address = registration.address
        withUnsafePointer(to: &address) { pointer in
            registration.block(1, pointer)
        }
    }
}

extension BluetoothListeningModeController {
    /// A controller for view/layout tests: no endpoints, an instant read-back, a
    /// failure that never lingers, and a fake listener seam that swallows the
    /// subscription calls so nothing here touches real CoreAudio. Publishing
    /// stays empty unless a test drives it.
    static func emptyForTesting() -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: CoreAudioBluetoothListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EmptyListeningModeEndpointProvider(),
            listenerBackend: FakeListeningModeListenerBackend()
        )
    }
}
