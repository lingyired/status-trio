import CoreAudio
import Foundation

/// The shared volume monitor only depends on this boundary. Hardware discovery
/// and I2C access are supplied by the distribution-specific coordinator.
@MainActor
protocol DDCVolumeCoordinating: AnyObject {
    var generation: UInt64 { get }

    func select(outputID: AudioDeviceID, uid: String?)
    func topologyChanged()
    func setDetailsVisible(_ visible: Bool)
    func setDisplayAsleep(_ asleep: Bool)
    @discardableResult func setVolume(_ scalar: Double) -> UInt64?
    func flushPendingVolume()
    func stop()
}

@MainActor
final class DDCVolumeCoordinatorConfiguration {
    let debounce: Duration
    let readWatchdog: Duration
    let beforeReadValidation: @Sendable () -> Void
    let onReadCompletion: @MainActor (AudioDeviceID, String, UInt64) -> Void
    let onDebounceSettled: @MainActor () -> Void
    let sleep: DDCVolumeCoordinatorSleep

    init(
        debounce: Duration = .milliseconds(150),
        readWatchdog: Duration = .seconds(2),
        beforeReadValidation: @escaping @Sendable () -> Void = {},
        onReadCompletion: @escaping @MainActor (AudioDeviceID, String, UInt64) -> Void = { _, _, _ in },
        onDebounceSettled: @escaping @MainActor () -> Void = {},
        sleep: @escaping DDCVolumeCoordinatorSleep = { try await Task.sleep(for: $0) }
    ) {
        self.debounce = debounce
        self.readWatchdog = readWatchdog
        self.beforeReadValidation = beforeReadValidation
        self.onReadCompletion = onReadCompletion
        self.onDebounceSettled = onDebounceSettled
        self.sleep = sleep
    }
}

typealias DDCVolumeCoordinatorSleep = @Sendable (Duration) async throws -> Void

typealias DDCVolumeCoordinatorFactory = @MainActor (
    @escaping @MainActor (DDCVolumeUpdate) -> Void,
    DDCVolumeCoordinatorConfiguration
) -> any DDCVolumeCoordinating

@MainActor
enum UnavailableDDCFactory {
    static func makeCoordinator(
        onUpdate _: @escaping @MainActor (DDCVolumeUpdate) -> Void,
        configuration _: DDCVolumeCoordinatorConfiguration
    ) -> any DDCVolumeCoordinating {
        UnavailableDDCVolumeCoordinator()
    }
}

struct DDCVolumeUpdate: Sendable {
    let outputID: AudioDeviceID
    let uid: String
    let generation: UInt64
    let capability: DDCVolumeCapability
    let commandID: UInt64?

    /// The display's current value, or nil while the capability is unknown.
    var scalar: Double? { capability.scalar }
}

/// Safe fallback for a target that does not compile the Direct DDC backend.
///
/// It intentionally never fabricates a volume, command ID, or update. A
/// distribution that cannot provide DDC support therefore leaves the shared
/// monitor in its unavailable state instead of falling through to private code.
@MainActor
final class UnavailableDDCVolumeCoordinator: DDCVolumeCoordinating {
    private(set) var generation: UInt64 = 0

    func select(outputID: AudioDeviceID, uid: String?) {
        generation &+= 1
    }

    func topologyChanged() {
        generation &+= 1
    }

    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}

    @discardableResult
    func setVolume(_ scalar: Double) -> UInt64? {
        nil
    }

    func flushPendingVolume() {}
    func stop() {}
}
