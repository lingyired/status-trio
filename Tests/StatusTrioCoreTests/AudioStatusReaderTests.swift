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
}
