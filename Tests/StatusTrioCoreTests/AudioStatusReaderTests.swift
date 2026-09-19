import XCTest
@testable import StatusTrioCore

/// Covers the enumeration policy of the production audio read. The volume and
/// device side of that read touch real CoreAudio, so the policy is exercised
/// through `CoreAudioStatusReader.assemble` instead of audio hardware.
@MainActor
final class AudioStatusReaderTests: XCTestCase {
    func testEnumerationIsSkippedAndNeverReadWhenNotRequested() {
        let deviceReads = ReadCounter()
        let device = AudioOutputDevice(id: 42, name: "Speakers", isCurrent: true)

        let result = CoreAudioStatusReader.assemble(
            includeOutputDevices: false,
            readVolume: { VolumeReading(scalar: 0.5, isMuted: false, deviceName: "Speakers") },
            readDevices: {
                deviceReads.increment()
                return [device]
            }
        )

        XCTAssertNil(result.outputDevices, "nil means enumeration was not requested")
        XCTAssertEqual(deviceReads.calls, 0, "An unrequested enumeration must not touch CoreAudio")
        XCTAssertEqual(result.volume?.scalar, 0.5)
    }

    func testEnumerationIsSkippedWhenThereIsNoDefaultOutputDevice() {
        let deviceReads = ReadCounter()
        let device = AudioOutputDevice(id: 42, name: "Speakers", isCurrent: true)

        let result = CoreAudioStatusReader.assemble(
            includeOutputDevices: true,
            readVolume: { nil },
            readDevices: {
                deviceReads.increment()
                return [device]
            }
        )

        XCTAssertNil(result.volume)
        XCTAssertNil(result.outputDevices, "Without a default device the list cannot be current")
        XCTAssertEqual(deviceReads.calls, 0, "A missing default device must short-circuit enumeration")
    }

    func testEnumerationRunsWhenRequestedWithADefaultOutputDevice() {
        let deviceReads = ReadCounter()
        let device = AudioOutputDevice(id: 42, name: "Speakers", isCurrent: true)

        let result = CoreAudioStatusReader.assemble(
            includeOutputDevices: true,
            readVolume: { VolumeReading(scalar: 0.25, isMuted: false, deviceName: "Speakers") },
            readDevices: {
                deviceReads.increment()
                return [device]
            }
        )

        XCTAssertEqual(result.outputDevices, [device])
        XCTAssertEqual(deviceReads.calls, 1)
        XCTAssertEqual(result.volume?.scalar, 0.25)
    }

    func testEmptyEnumerationIsDistinctFromNotRequested() {
        let result = CoreAudioStatusReader.assemble(
            includeOutputDevices: true,
            readVolume: { VolumeReading(scalar: 0.25, isMuted: false, deviceName: "Speakers") },
            readDevices: { [] }
        )

        XCTAssertEqual(result.outputDevices, [], "An empty array is a valid enumeration result")
    }

    func testReadAfterAStuckReadStillRuns() async {
        let firstReadStarted = expectation(description: "first read started")
        let secondReadFinished = expectation(description: "second read completed")
        let release = DispatchSemaphore(value: 0)
        let calls = ReadCounter()
        let reader = CoreAudioStatusReader { _ in
            if calls.increment() == 1 {
                firstReadStarted.fulfill()
                // Models a CoreAudio call that stays blocked; the test frees it
                // only after the follow-up read has already run.
                _ = release.wait(timeout: .now() + 10)
            }
            return AudioStatusReading(
                volume: VolumeReading(scalar: 0.5, isMuted: false, deviceName: "Speakers"),
                outputDevices: nil
            )
        }

        reader.read(includeOutputDevices: false) { _ in }
        await fulfillment(of: [firstReadStarted], timeout: 5)
        XCTAssertEqual(calls.calls, 1)

        // The first read never returned. This one must not queue behind it.
        reader.read(includeOutputDevices: false) { _ in secondReadFinished.fulfill() }
        await fulfillment(of: [secondReadFinished], timeout: 5)

        XCTAssertEqual(calls.calls, 2)
        release.signal()
    }

    func testALateCompletionFromARetiredQueueDoesNotStopTheNextRetirement() async {
        let firstReadStarted = expectation(description: "first read started")
        let firstReadReturned = expectation(description: "first read returned late")
        let secondReadFinished = expectation(description: "second read completed")
        let thirdReadStarted = expectation(description: "third read started")
        let fourthReadFinished = expectation(description: "fourth read completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let releaseThird = DispatchSemaphore(value: 0)
        let calls = ReadCounter()
        let reader = CoreAudioStatusReader { _ in
            switch calls.increment() {
            case 1:
                firstReadStarted.fulfill()
                _ = releaseFirst.wait(timeout: .now() + 10)
            case 3:
                thirdReadStarted.fulfill()
                _ = releaseThird.wait(timeout: .now() + 10)
            default:
                break
            }
            return AudioStatusReading(
                volume: VolumeReading(scalar: 0.5, isMuted: false, deviceName: "Speakers"),
                outputDevices: nil
            )
        }

        // Read 1 wedges the original queue.
        reader.read(includeOutputDevices: false) { _ in firstReadReturned.fulfill() }
        await fulfillment(of: [firstReadStarted], timeout: 5)

        // Read 2 retires that queue and completes on the replacement.
        reader.read(includeOutputDevices: false) { _ in secondReadFinished.fulfill() }
        await fulfillment(of: [secondReadFinished], timeout: 5)

        // Read 3 wedges the replacement queue.
        reader.read(includeOutputDevices: false) { _ in }
        await fulfillment(of: [thirdReadStarted], timeout: 5)

        // Read 1 finally returns. Its completion belongs to the retired queue, so
        // it must not clear the flag that now describes read 3 — otherwise read 4
        // would be queued behind the wedged read 3 instead of retiring again.
        releaseFirst.signal()
        await fulfillment(of: [firstReadReturned], timeout: 5)

        reader.read(includeOutputDevices: false) { _ in fourthReadFinished.fulfill() }
        await fulfillment(of: [fourthReadFinished], timeout: 5)

        XCTAssertEqual(calls.calls, 4)
        releaseThird.signal()
    }
}
