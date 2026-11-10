import CoreAudio
import XCTest
@testable import StatusTrioCore

final class AirPodsSpatialObservationTests: XCTestCase {
    @MainActor
    func testPlaybackUpdatesWhileAdaptiveReadIsPendingAndLateResultCannotOverwriteIt() async throws {
        let backend = SpatialListenerFixture()
        let playing = [AirPodsSystemOption(title: "Fixed", selected: true)]
        var spatialReads = 0
        let model = AirPodsSystemControlsModel(deviceID: .init(id: 42, uid: "fixture"), deviceName: "AirPods",
            listenerBackend: backend, spatialReader: { spatialReads += 1; return playing })
        var finish: CheckedContinuation<Void, Never>?
        model.start { publish in
            publish(.init(spatialLoaded: true))
            await withCheckedContinuation { finish = $0 }
            return .init(loaded: true)
        }
        for _ in 0..<100 where finish == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(finish)
        XCTAssertEqual(backend.added.count, AirPodsSpatialObservation.selectors.count)
        let late = backend.callbacks
        // Opening the menu reads spatial state without waiting for a notification.
        for _ in 0..<100 where model.snapshot.spatial.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.snapshot.spatial, playing)
        XCTAssertTrue(model.busy, "Spatial availability must not wait for the supplementary read")
        XCTAssertFalse(model.spatialDisabled)
        let selected = [AirPodsSystemOption(title: "Head Tracked", selected: true)]
        model.writeSpatial { selected }
        for _ in 0..<100 where model.spatialWriting { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.snapshot.spatial, selected)
        XCTAssertTrue(model.busy, "The independent supplementary read is still pending")
        finish?.resume()
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.snapshot.spatial, selected, "Old full snapshots must not overwrite a playback notification")
        model.stop()
        XCTAssertEqual(backend.removed.sorted(), backend.added.sorted())
        let count = spatialReads
        SpatialListenerFixture.emit(late)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(spatialReads, count, "Queued callbacks after dismissal must be ignored")

        model.start { _ in .init(loaded: true) }
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        backend.emit()
        for _ in 0..<100 where spatialReads == count { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(spatialReads, count, "Reopening must establish fresh observation")
        var finishWrite: CheckedContinuation<Void, Never>?
        model.writeSpatial {
            await withCheckedContinuation { finishWrite = $0 }
            return selected
        }
        for _ in 0..<100 where finishWrite == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(finishWrite)
        model.stop()
        finishWrite?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(model.spatialWriting)
        XCTAssertEqual(model.snapshot.spatial, playing, "A dismissed write cannot publish a late result")
    }

    @MainActor
    func testPlaybackUpdateWaitsForSpatialWriteAndPreservesOtherControls() async throws {
        let backend = SpatialListenerFixture()
        let conversation = [AirPodsSystemOption(title: "On", selected: true)]
        var reads = 0
        let model = AirPodsSystemControlsModel(deviceID: .init(id: 42, uid: "fixture"), deviceName: "AirPods",
            listenerBackend: backend, spatialReader: { reads += 1; return [] })
        model.start { _ in .init(conversation: conversation, adaptive: 50, loaded: true) }
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        let initialReads = reads
        var finish: CheckedContinuation<Void, Never>?
        model.run(.option(.spatial)) { await withCheckedContinuation { finish = $0 } }
        for _ in 0..<100 where finish == nil { try await Task.sleep(for: .milliseconds(5)) }
        backend.emit()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reads, initialReads)
        finish?.resume()
        for _ in 0..<100 where reads == initialReads { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(reads, initialReads)
        XCTAssertTrue(model.snapshot.spatial.isEmpty, "Stopping playback may make Spatial Audio unavailable")
        XCTAssertEqual(model.snapshot.conversation, conversation)
        XCTAssertEqual(model.snapshot.adaptive, 50)
        model.stop()
    }

    func testFailedRegistrationsAreNotRemovedAndSuccessfulOnesAreRemovedOnDeinit() {
        let backend = SpatialListenerFixture()
        backend.failSelector = 0x73706366
        var observation: AirPodsSpatialObservation? = .init(deviceID: 42, backend: backend, changed: {})
        XCTAssertNotNil(observation)
        observation = nil
        XCTAssertEqual(backend.removed.sorted(), backend.added.filter { $0 != backend.failSelector }.sorted())
    }
}

private final class SpatialListenerFixture: BluetoothListeningModePropertyListening, @unchecked Sendable {
    private let lock = NSLock()
    private var blocks: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]
    private(set) var added: [AudioObjectPropertySelector] = []
    private(set) var removed: [AudioObjectPropertySelector] = []
    var failSelector: AudioObjectPropertySelector?
    var callbacks: [AudioObjectPropertyListenerBlock] {
        lock.lock(); defer { lock.unlock() }
        return Array(blocks.values)
    }
    func emit() { Self.emit(callbacks) }
    static func emit(_ callbacks: [AudioObjectPropertyListenerBlock]) {
        var address = BluetoothListeningModeProperty.address(0x73706176)
        withUnsafePointer(to: &address) { pointer in
            callbacks.forEach { $0(1, pointer) }
        }
    }
    func addListener(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress, queue: DispatchQueue?,
                     block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        added.append(address.mSelector)
        if address.mSelector == failSelector { return kAudioHardwareUnknownPropertyError }
        blocks[address.mSelector] = block
        return noErr
    }
    func removeListener(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress, queue: DispatchQueue?,
                        block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        removed.append(address.mSelector)
        blocks.removeValue(forKey: address.mSelector)
        return noErr
    }
}
