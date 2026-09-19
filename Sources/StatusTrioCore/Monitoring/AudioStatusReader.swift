import Foundation

private let audioStatusReaderQueueLabel = "StatusTrio.AudioStatusReader"

struct AudioStatusReading: Sendable {
    let volume: VolumeReading?
    /// `nil` means enumeration was not requested; an empty array is a valid result.
    let outputDevices: [AudioOutputDevice]?
}

@MainActor
protocol AudioStatusReadingProviding: AnyObject {
    func read(
        includeOutputDevices: Bool,
        completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void
    )
}

/// CoreAudio property reads may wait for an audio service or device driver.
/// Use one serial queue, outside both MainActor and the cooperative executor.
@MainActor
final class CoreAudioStatusReader: AudioStatusReadingProviding {
    private var queue = DispatchQueue(label: audioStatusReaderQueueLabel, qos: .utility)
    private var queueGeneration: UInt64 = 0
    private var hasOutstandingRead = false
    private let readSystem: @Sendable (Bool) -> AudioStatusReading

    /// The device-enumeration policy of the production read, split out so it can
    /// be exercised without audio hardware: the device list is read only when it
    /// was requested and only when a default output device exists, and `nil`
    /// keeps meaning "not requested".
    nonisolated static func assemble(
        includeOutputDevices: Bool,
        readVolume: @Sendable () -> VolumeReading?,
        readDevices: @Sendable () -> [AudioOutputDevice]
    ) -> AudioStatusReading {
        let volume = readVolume()
        let devices = includeOutputDevices && volume != nil ? readDevices() : nil
        return AudioStatusReading(volume: volume, outputDevices: devices)
    }

    init(readSystem: @escaping @Sendable (Bool) -> AudioStatusReading = { includeOutputDevices in
        CoreAudioStatusReader.assemble(
            includeOutputDevices: includeOutputDevices,
            readVolume: { CoreAudioVolumeReader().read() },
            readDevices: { CoreAudioOutputController().outputDevices() }
        )
    }) {
        self.readSystem = readSystem
    }

    func read(
        includeOutputDevices: Bool,
        completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void
    ) {
        // A read that never returned would block this one behind it on the same
        // serial queue for the lifetime of the process, so retire that queue and
        // give this read a fresh one. The abandoned block keeps the old queue
        // alive until it eventually returns.
        if hasOutstandingRead {
            queueGeneration &+= 1
            queue = DispatchQueue(label: audioStatusReaderQueueLabel, qos: .utility)
        }
        hasOutstandingRead = true
        let generation = queueGeneration
        let currentQueue = queue
        let readSystem = readSystem
        currentQueue.async { [weak self] in
            let reading = readSystem(includeOutputDevices)
            Task { @MainActor in
                // Only the read on the current queue may clear the flag; a late
                // completion from a retired queue must not.
                if let self, generation == self.queueGeneration {
                    self.hasOutstandingRead = false
                }
                completion(reading)
            }
        }
    }
}
