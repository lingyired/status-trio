import AudioToolbox
import CoreAudio
import XCTest

@testable import StatusTrioCore

final class AudioInputHardwareTests: XCTestCase {
  func testBackgroundInventoryDoesNotInspectActiveMicrophoneProcesses() throws {
    let client = makeClient()
    let hardware = CoreAudioInputHardware(client: client)
    let inventory = try hardware.readInventory()
    XCTAssertEqual(inventory.devices?.count, 2)
    XCTAssertNil(inventory.isDefaultInputInUse)
    XCTAssertEqual(client.usageReads, 0)
    _ = try hardware.read(includeDevices: true)
    XCTAssertEqual(client.usageReads, 1)
  }
  func testFiltersIneligibleDevicesAndPreservesDuplicateNamesAndMissingUID() throws {
    let hardware = CoreAudioInputHardware(client: makeClient())

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [11, 15])
    XCTAssertEqual(reading.defaultDeviceID, 11)
    XCTAssertEqual(reading.devices?.map(\.name), ["Shared microphone", "Shared microphone"])
    XCTAssertNotEqual(reading.devices?[0].id, reading.devices?[1].id)
    XCTAssertNil(reading.devices?[1].uid, "A missing UID must not be synthesized from the name")
  }

  func testDoesNotEnumerateWhenDeviceListIsNotRequested() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(devicesError: .unavailable)
    )

    let reading = try hardware.read(includeDevices: false)

    XCTAssertNil(reading.devices, "nil distinguishes skipped enumeration from an empty list")
    XCTAssertEqual(reading.defaultDeviceID, 11)
    XCTAssertEqual(reading.deviceName, "Shared microphone")
    XCTAssertEqual(reading.scalar ?? -1, 0.42, accuracy: 0.000_001)
    XCTAssertTrue(reading.canSetVolume)
    XCTAssertEqual(reading.muteState, .muted)
    XCTAssertTrue(reading.canSetMute)
  }

  func testNoDefaultInputStillReturnsEligibleDevices() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(defaultID: nil, deviceIDs: [15])
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [15])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
    XCTAssertNil(reading.muteState)
    XCTAssertFalse(reading.canSetMute)
  }

  func testEmptyHardwareReturnsAnEmptyEnumeratedList() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(defaultID: nil, deviceIDs: [])
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices, [])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
  }

  func testReportsOnlyAnActiveInputStreamOnTheCurrentDefaultDevice() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        activeInputUsage: AudioInputProcessDeviceUsage(
          activeInputDeviceIDs: [22],
          isComplete: true
        )
      )
    )

    XCTAssertFalse(try XCTUnwrap(hardware.read(includeDevices: true).isDefaultInputInUse))
  }

  func testActiveInputStreamOnTheCurrentDefaultDeviceIsReportedInUse() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        activeInputUsage: AudioInputProcessDeviceUsage(
          activeInputDeviceIDs: [11],
          isComplete: true
        )
      )
    )

    XCTAssertTrue(try XCTUnwrap(hardware.read(includeDevices: true).isDefaultInputInUse))
  }

  func testIncompleteProcessSnapshotDoesNotClaimTheDefaultInputIsIdle() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        activeInputUsage: AudioInputProcessDeviceUsage(
          activeInputDeviceIDs: [],
          isComplete: false
        )
      )
    )

    XCTAssertNil(try hardware.read(includeDevices: true).isDefaultInputInUse)
  }

  func testInvalidDefaultIsNotSelectedButEligibleDevicesRemainAvailable() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(defaultID: 99, deviceIDs: [11, 12])
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [11])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
  }

  func testBlankDeviceNamesBecomeNilWithoutRemovingDevices() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 15,
        deviceIDs: [15],
        overrides: [15: .eligible(name: "   ", uid: nil)]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [15])
    XCTAssertNil(reading.devices?.first?.name)
    XCTAssertNil(reading.deviceName)
  }

  func testUnreportedEligibilityPropertiesFailClosed() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [11: .eligible(name: "Microphone", uid: "mic", alive: nil)]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices, [])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
  }

  func testInvalidControlReadbackIsNotPresentedAsSupported() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [
          11: .eligible(
            name: "Microphone",
            uid: "mic",
            volume: AudioInputVolumeReadback(scalar: .infinity, canSet: true),
            mute: AudioInputMuteReadback(state: nil, canSet: true)
          )
        ]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
    XCTAssertNil(reading.muteState)
    XCTAssertFalse(reading.canSetMute)
  }

  func testReadOnlyControlReadbacksRemainVisibleButCannotBeSet() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [
          11: .eligible(
            name: "Read-only microphone",
            uid: "read-only-mic",
            volume: AudioInputVolumeReadback(scalar: 0.63, canSet: false),
            mute: AudioInputMuteReadback(state: .unmuted, canSet: false)
          )
        ]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.scalar ?? -1, 0.63, accuracy: 0.000_001)
    XCTAssertFalse(reading.canSetVolume)
    XCTAssertEqual(reading.muteState, .unmuted)
    XCTAssertFalse(reading.canSetMute)
  }

  func testReadOnlyMainControlValuesRemainVisibleButCannotBeSet() {
    let volume = CoreAudioInputControlReadback.volume(
      mainScalar: 0.63,
      mainCanSet: false,
      channelScalars: [],
      channelCanSet: []
    )
    let mute = CoreAudioInputControlReadback.mute(
      mainValue: false,
      mainCanSet: false,
      channelValues: [],
      channelCanSet: []
    )

    XCTAssertEqual(volume, AudioInputVolumeReadback(scalar: 0.63, canSet: false))
    XCTAssertEqual(mute, AudioInputMuteReadback(state: .unmuted, canSet: false))
  }

  func testReadOnlyChannelControlValuesRemainVisibleButCannotBeSet() {
    let volume = CoreAudioInputControlReadback.volume(
      mainScalar: nil,
      mainCanSet: false,
      channelScalars: [0.2, 0.8],
      channelCanSet: [true, false]
    )
    let mute = CoreAudioInputControlReadback.mute(
      mainValue: nil,
      mainCanSet: false,
      channelValues: [true, false],
      channelCanSet: [true, false]
    )

    XCTAssertEqual(volume, AudioInputVolumeReadback(scalar: 0.5, canSet: false))
    XCTAssertEqual(mute, AudioInputMuteReadback(state: .partial, canSet: false))
  }

  func testCoreAudioStringReadbackValidatesBeforeConsumingTheValue() {
    var consumeCount = 0

    let failedStatus = withValidatedCoreAudioPropertyData(
      status: OSStatus(-1),
      returnedSize: 8,
      expectedSize: 8
    ) {
      consumeCount += 1
      return "must not be consumed"
    }
    let invalidLength = withValidatedCoreAudioPropertyData(
      status: noErr,
      returnedSize: 4,
      expectedSize: 8
    ) {
      consumeCount += 1
      return "must not be consumed"
    }
    let validValue = withValidatedCoreAudioPropertyData(
      status: noErr,
      returnedSize: 8,
      expectedSize: 8
    ) {
      consumeCount += 1
      return "Microphone"
    }

    XCTAssertNil(failedStatus)
    XCTAssertNil(invalidLength)
    XCTAssertEqual(validValue, "Microphone")
    XCTAssertEqual(consumeCount, 1)
  }

  func testWritableMainElementIsPreferredOverChannels() throws {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Microphone",
          uid: "mic",
          channels: 2,
          controlProperties: [
            .init(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain): .init(scalar: 0.4, settable: true),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 1): .init(scalar: 0.2, settable: true),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 2): .init(scalar: 0.8, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain): .init(mute: false, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: 1): .init(mute: true, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: 2): .init(mute: true, settable: true),
          ]
        )
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)

    let reading = try hardware.read(includeDevices: false)
    try hardware.setScalar(0.7, on: 11)
    try hardware.setMuted(true, on: 11)

    XCTAssertEqual(reading.scalar ?? -1, 0.4, accuracy: 0.000_001)
    XCTAssertEqual(reading.muteState, .unmuted)
    XCTAssertEqual(client.writtenScalarElements, [kAudioObjectPropertyElementMain])
    XCTAssertEqual(client.writtenMuteElements, [kAudioObjectPropertyElementMain])
  }

  func testTwoWritableChannelsAverageGainAndReportPartialMute() throws {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Two-channel microphone",
          uid: "two-channel",
          channels: 2,
          controlProperties: [
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 1): .init(scalar: 0.2, settable: true),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 2): .init(scalar: 0.8, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: 1): .init(mute: true, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: 2): .init(mute: false, settable: true),
          ]
        )
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)

    let reading = try hardware.read(includeDevices: false)

    XCTAssertEqual(reading.scalar ?? -1, 0.5, accuracy: 0.000_001)
    XCTAssertTrue(reading.canSetVolume)
    XCTAssertEqual(reading.muteState, .partial)
    XCTAssertTrue(reading.canSetMute)
  }

  func testReadOnlyMainFallsBackToFullyWritableChannels() throws {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Microphone",
          uid: "mic",
          channels: 2,
          controlProperties: [
            .init(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain): .init(scalar: 0.9, settable: false),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 1): .init(scalar: 0.2, settable: true),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 2): .init(scalar: 0.8, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain): .init(mute: true, settable: false),
            .init(selector: kAudioDevicePropertyMute, element: 1): .init(mute: false, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: 2): .init(mute: true, settable: true),
          ]
        )
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)

    let reading = try hardware.read(includeDevices: false)
    try hardware.setScalar(0.6, on: 11)
    try hardware.setMuted(true, on: 11)

    XCTAssertEqual(reading.scalar ?? -1, 0.5, accuracy: 0.000_001)
    XCTAssertTrue(reading.canSetVolume)
    XCTAssertEqual(reading.muteState, .partial)
    XCTAssertTrue(reading.canSetMute)
    XCTAssertEqual(client.writtenScalarElements, [1, 2])
    XCTAssertEqual(client.writtenMuteElements, [1, 2])
  }

  func testMissingChannelDisablesGainControl() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [
          11: .eligible(
            name: "Microphone",
            uid: "mic",
            channels: 2,
            controlProperties: [
              .init(selector: kAudioDevicePropertyVolumeScalar, element: 1): .init(scalar: 0.2, settable: true),
            ]
          )
        ]
      )
    )

    let reading = try hardware.read(includeDevices: false)

    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
  }

  func testNaNAndOutOfRangeGainAreNotExposed() throws {
    for invalid in [Float32.nan, -0.1, 1.1] {
      let hardware = CoreAudioInputHardware(
        client: makeClient(
          defaultID: 11,
          deviceIDs: [11],
          overrides: [
            11: .eligible(
              name: "Microphone",
              uid: "mic",
              controlProperties: [
                .init(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain): .init(scalar: invalid, settable: true),
              ]
            )
          ]
        )
      )

      let reading = try hardware.read(includeDevices: false)

      XCTAssertNil(reading.scalar)
      XCTAssertFalse(reading.canSetVolume)
    }
  }

  func testReadOnlyMainReadbackRemainsVisibleWithoutWritableFallback() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [
          11: .eligible(
            name: "Read-only microphone",
            uid: "mic",
            channels: 2,
            controlProperties: [
              .init(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain): .init(scalar: 0.63, settable: false),
              .init(selector: kAudioDevicePropertyVolumeScalar, element: 1): .init(scalar: 0.2, settable: true),
            ]
          )
        ]
      )
    )

    let reading = try hardware.read(includeDevices: false)

    XCTAssertEqual(reading.scalar ?? -1, 0.63, accuracy: 0.000_001)
    XCTAssertFalse(reading.canSetVolume)
  }

  func testGainWriteDoesNotWriteMuteAndMuteWriteDoesNotWriteGain() throws {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Microphone",
          uid: "mic",
          volume: AudioInputVolumeReadback(scalar: 0.4, canSet: true),
          mute: AudioInputMuteReadback(state: .unmuted, canSet: true)
        )
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)

    try hardware.setScalar(0.7, on: 11)
    XCTAssertEqual(client.writtenScalarElements, [kAudioObjectPropertyElementMain])
    XCTAssertTrue(client.writtenMuteElements.isEmpty)

    try hardware.setMuted(true, on: 11)
    XCTAssertEqual(client.writtenScalarElements, [kAudioObjectPropertyElementMain])
    XCTAssertEqual(client.writtenMuteElements, [kAudioObjectPropertyElementMain])
  }

  func testGainWritesClampFiniteValuesAndRejectNaN() throws {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Microphone",
          uid: "mic",
          volume: AudioInputVolumeReadback(scalar: 0.4, canSet: true)
        )
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)

    try hardware.setScalar(-0.5, on: 11)
    XCTAssertEqual(client.readScalar(11, kAudioObjectPropertyElementMain), 0)
    try hardware.setScalar(1.5, on: 11)
    XCTAssertEqual(client.readScalar(11, kAudioObjectPropertyElementMain), 1)
    XCTAssertThrowsError(try hardware.setScalar(.nan, on: 11))
    XCTAssertEqual(client.writtenScalarElements, [
      kAudioObjectPropertyElementMain,
      kAudioObjectPropertyElementMain,
    ])
  }

  func testPartialMuteWriteThrowsAfterAttemptingSecondChannel() {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Two-channel microphone",
          uid: "two-channel",
          channels: 2,
          controlProperties: [
            .init(selector: kAudioDevicePropertyMute, element: 1): .init(mute: false, settable: true),
            .init(selector: kAudioDevicePropertyMute, element: 2): .init(mute: false, settable: true),
          ]
        )
      ]
    )
    client.failingMuteElement = 2
    let hardware = CoreAudioInputHardware(client: client)

    XCTAssertThrowsError(try hardware.setMuted(true, on: 11))
    XCTAssertEqual(client.writtenMuteElements, [1, 2])
  }

  func testVolumeWriteRechecksDefaultBeforeEachChannelWrite() {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11, 22],
      overrides: [
        11: .eligible(
          name: "Two-channel microphone",
          uid: "stereo",
          channels: 2,
          controlProperties: [
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 1): .init(scalar: 0.4, settable: true),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 2): .init(scalar: 0.4, settable: true),
          ]
        ),
        22: .eligible(name: "New default", uid: "new-default"),
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)
    client.switchDefaultAfterNextScalarWrite = 22

    XCTAssertThrowsError(try hardware.setScalar(0.9, on: 11))
    XCTAssertEqual(client.writtenScalarElements, [1])
    XCTAssertEqual(client.writtenScalarIDs, [11])
    XCTAssertEqual(client.defaultID, 22)
  }

  func testVolumeAndMuteWritesAreRejectedWhenTargetIsNoLongerDefault() {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11, 22],
      overrides: [
        11: .eligible(
          name: "Previous microphone",
          uid: "previous",
          volume: AudioInputVolumeReadback(scalar: 0.4, canSet: true),
          mute: AudioInputMuteReadback(state: .unmuted, canSet: true)
        ),
        22: .eligible(
          name: "Current microphone",
          uid: "current",
          volume: AudioInputVolumeReadback(scalar: 0.6, canSet: true),
          mute: AudioInputMuteReadback(state: .unmuted, canSet: true)
        ),
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)
    client.setDefaultInput(22)

    XCTAssertThrowsError(try hardware.setScalar(0.9, on: 11))
    XCTAssertThrowsError(try hardware.setMuted(true, on: 11))
    XCTAssertTrue(client.writtenScalarElements.isEmpty)
    XCTAssertTrue(client.writtenMuteElements.isEmpty)
    XCTAssertEqual(client.defaultID, 22)
  }

  func testCommandsRevalidateDeviceAndPropertyCapabilities() {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [11],
      overrides: [
        11: .eligible(
          name: "Microphone",
          uid: "mic",
          volume: AudioInputVolumeReadback(scalar: 0.4, canSet: true),
          mute: AudioInputMuteReadback(state: .unmuted, canSet: true)
        )
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)
    client.setDeviceAlive(false, id: 11)

    XCTAssertThrowsError(try hardware.setMuted(true, on: 11))
    XCTAssertTrue(client.writtenMuteElements.isEmpty)

    client.setDeviceAlive(true, id: 11)
    client.setSettable(false, selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain, id: 11)
    XCTAssertThrowsError(try hardware.setMuted(true, on: 11))
    XCTAssertTrue(client.writtenMuteElements.isEmpty)
  }

  func testCommandsRejectHiddenAndStreamlessInputsBeforeWriting() {
    let client = makeClient(
      defaultID: 11,
      deviceIDs: [12, 13],
      overrides: [
        12: .eligible(
          name: "Hidden microphone",
          uid: "hidden",
          hidden: true,
          volume: AudioInputVolumeReadback(scalar: 0.4, canSet: true),
          mute: AudioInputMuteReadback(state: .unmuted, canSet: true)
        ),
        13: .eligible(
          name: "Streamless microphone",
          uid: "streamless",
          channels: 0,
          volume: AudioInputVolumeReadback(scalar: 0.4, canSet: true),
          mute: AudioInputMuteReadback(state: .unmuted, canSet: true)
        ),
      ]
    )
    let hardware = CoreAudioInputHardware(client: client)

    for id: AudioDeviceID in [12, 13] {
      XCTAssertThrowsError(try hardware.selectDefault(id), "device \(id) is not an eligible input")
      XCTAssertThrowsError(try hardware.setScalar(0.7, on: id), "device \(id) is not an eligible input")
      XCTAssertThrowsError(try hardware.setMuted(true, on: id), "device \(id) is not an eligible input")
    }

    XCTAssertTrue(client.writtenDefaultInputs.isEmpty)
    XCTAssertTrue(client.writtenScalarElements.isEmpty)
    XCTAssertTrue(client.writtenMuteElements.isEmpty)
  }

  func testDefaultInputWriteFailureDoesNotChangeFakeSystemDefault() {
    let client = makeClient(defaultID: 11, deviceIDs: [11, 15])
    client.failDefaultInputWrite = true
    let hardware = CoreAudioInputHardware(client: client)

    XCTAssertThrowsError(try hardware.selectDefault(15))
    XCTAssertEqual(client.defaultID, 11)
  }

  func testDefaultInputSelectionUsesSystemWrite() throws {
    let client = makeClient(defaultID: 11, deviceIDs: [11, 15])
    let hardware = CoreAudioInputHardware(client: client)

    try hardware.selectDefault(15)

    XCTAssertEqual(client.defaultID, 15)
    XCTAssertEqual(client.writtenDefaultInputs, [15])
  }

  private func makeClient(
    defaultID: AudioDeviceID? = 11,
    deviceIDs: [AudioDeviceID] = [11, 12, 13, 14, 15, AudioDeviceID(kAudioObjectUnknown)],
    devicesError: AudioInputHardwareError? = nil,
    activeInputUsage: AudioInputProcessDeviceUsage? = AudioInputProcessDeviceUsage(
      activeInputDeviceIDs: [],
      isComplete: true
    ),
    overrides: [AudioDeviceID: FakeDevice] = [:]
  ) -> FakeAudioInputPropertyClient {
    var devices: [AudioDeviceID: FakeDevice] = [
      11: FakeDevice.eligible(
        name: "Shared microphone",
        uid: "com.example.mic.internal",
        volume: AudioInputVolumeReadback(scalar: 0.42, canSet: true),
        mute: AudioInputMuteReadback(state: .muted, canSet: true)
      ),
      12: FakeDevice.eligible(name: "Hidden microphone", uid: "hidden", hidden: true),
      13: FakeDevice.eligible(name: "No input channels", uid: "no-input", channels: 0),
      14: FakeDevice.eligible(name: "Cannot be default", uid: "not-default", canBeDefault: false),
      15: FakeDevice.eligible(name: "Shared microphone", uid: nil),
    ]
    devices.merge(overrides) { _, replacement in replacement }
    return FakeAudioInputPropertyClient(
      deviceIDs: deviceIDs,
      defaultID: defaultID,
      devicesError: devicesError,
      activeInputUsage: activeInputUsage,
      devices: devices
    )
  }
}

private final class FakeAudioInputPropertyClient: AudioInputPropertyClient, @unchecked Sendable {
  private(set) var usageReads = 0
  let deviceIDs: [AudioDeviceID]
  let devicesError: AudioInputHardwareError?
  let activeInputUsage: AudioInputProcessDeviceUsage?
  private(set) var defaultID: AudioDeviceID?
  private var devicesByID: [AudioDeviceID: FakeDevice]
  private(set) var writtenScalarElements: [AudioObjectPropertyElement] = []
  private(set) var writtenMuteElements: [AudioObjectPropertyElement] = []
  private(set) var writtenScalarIDs: [AudioDeviceID] = []
  private(set) var writtenMuteIDs: [AudioDeviceID] = []
  private(set) var writtenDefaultInputs: [AudioDeviceID] = []
  var failingMuteElement: AudioObjectPropertyElement?
  var failDefaultInputWrite = false
  var switchDefaultAfterNextScalarWrite: AudioDeviceID?

  init(
    deviceIDs: [AudioDeviceID],
    defaultID: AudioDeviceID?,
    devicesError: AudioInputHardwareError?,
    activeInputUsage: AudioInputProcessDeviceUsage?,
    devices: [AudioDeviceID: FakeDevice]
  ) {
    self.deviceIDs = deviceIDs
    self.defaultID = defaultID
    self.devicesError = devicesError
    self.activeInputUsage = activeInputUsage
    self.devicesByID = devices
  }

  func devices() throws -> [AudioDeviceID] {
    if let devicesError { throw devicesError }
    return deviceIDs
  }

  func defaultInput() throws -> AudioDeviceID? { defaultID }
  func activeInputProcessUsage() -> AudioInputProcessDeviceUsage? { usageReads += 1; return activeInputUsage }
  func isDevice(_ id: AudioDeviceID) -> Bool { devicesByID[id]?.isDevice ?? false }
  func isAlive(_ id: AudioDeviceID) -> Bool? { devicesByID[id]?.isAlive }
  func isHidden(_ id: AudioDeviceID) -> Bool? { devicesByID[id]?.isHidden }
  func canBeDefaultInput(_ id: AudioDeviceID) -> Bool? { devicesByID[id]?.canBeDefault }
  func inputChannels(_ id: AudioDeviceID) -> Int { devicesByID[id]?.channels ?? 0 }
  func name(_ id: AudioDeviceID) -> String? { devicesByID[id]?.name }
  func uid(_ id: AudioDeviceID) -> String? { devicesByID[id]?.uid }
  func volume(_ id: AudioDeviceID) -> AudioInputVolumeReadback { devicesByID[id]?.volume ?? .unsupported }
  func mute(_ id: AudioDeviceID) -> AudioInputMuteReadback { devicesByID[id]?.mute ?? .unsupported }

  func hasProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool {
    devicesByID[id]?.controlProperties[FakePropertyKey(selector: selector, element: element)] != nil
  }

  func isSettable(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool {
    devicesByID[id]?.controlProperties[FakePropertyKey(selector: selector, element: element)]?.settable == true
  }

  func readScalar(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Float32? {
    devicesByID[id]?.controlProperties[FakePropertyKey(selector: kAudioDevicePropertyVolumeScalar, element: element)]?.scalar
  }

  func readMute(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool? {
    devicesByID[id]?.controlProperties[FakePropertyKey(selector: kAudioDevicePropertyMute, element: element)]?.mute
  }

  func writeScalar(
    _ value: Float32,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws {
    writtenScalarElements.append(element)
    writtenScalarIDs.append(id)
    let key = FakePropertyKey(selector: kAudioDevicePropertyVolumeScalar, element: element)
    guard var device = devicesByID[id], var property = device.controlProperties[key], property.settable else {
      throw AudioInputHardwareError.unsupported
    }
    property.scalar = value
    device.controlProperties[key] = property
    devicesByID[id] = device
    if let nextDefault = switchDefaultAfterNextScalarWrite {
      defaultID = nextDefault
      switchDefaultAfterNextScalarWrite = nil
    }
  }

  func writeMute(
    _ value: Bool,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws {
    writtenMuteElements.append(element)
    writtenMuteIDs.append(id)
    if failingMuteElement == element { throw AudioInputHardwareError.osStatus(OSStatus(-1)) }
    let key = FakePropertyKey(selector: kAudioDevicePropertyMute, element: element)
    guard var device = devicesByID[id], var property = device.controlProperties[key], property.settable else {
      throw AudioInputHardwareError.unsupported
    }
    property.mute = value
    device.controlProperties[key] = property
    devicesByID[id] = device
  }

  func writeDefaultInput(_ id: AudioDeviceID) throws {
    writtenDefaultInputs.append(id)
    if failDefaultInputWrite { throw AudioInputHardwareError.osStatus(OSStatus(-1)) }
    defaultID = id
  }

  func setDefaultInput(_ id: AudioDeviceID?) {
    defaultID = id
  }

  func setDeviceAlive(_ isAlive: Bool, id: AudioDeviceID) {
    devicesByID[id]?.isAlive = isAlive
  }

  func setSettable(
    _ isSettable: Bool,
    selector: AudioObjectPropertySelector,
    element: AudioObjectPropertyElement,
    id: AudioDeviceID
  ) {
    let key = FakePropertyKey(selector: selector, element: element)
    devicesByID[id]?.controlProperties[key]?.settable = isSettable
  }
}
private struct FakePropertyKey: Hashable {
  let selector: AudioObjectPropertySelector
  let element: AudioObjectPropertyElement
}

private struct FakeControlProperty {
  var scalar: Float32?
  var mute: Bool?
  var settable: Bool

  init(scalar: Float32? = nil, mute: Bool? = nil, settable: Bool) {
    self.scalar = scalar
    self.mute = mute
    self.settable = settable
  }
}

private struct FakeDevice {
  var isDevice: Bool
  var isAlive: Bool?
  var isHidden: Bool?
  var canBeDefault: Bool?
  var channels: Int
  var name: String?
  var uid: String?
  var volume: AudioInputVolumeReadback
  var mute: AudioInputMuteReadback
  var controlProperties: [FakePropertyKey: FakeControlProperty]

  static func eligible(
    name: String?,
    uid: String?,
    hidden: Bool? = false,
    canBeDefault: Bool? = true,
    channels: Int = 1,
    alive: Bool? = true,
    volume: AudioInputVolumeReadback = .unsupported,
    mute: AudioInputMuteReadback = .unsupported,
    controlProperties: [FakePropertyKey: FakeControlProperty]? = nil
  ) -> FakeDevice {
    var properties = controlProperties ?? [:]
    if controlProperties == nil {
      if let scalar = volume.scalar {
        properties[FakePropertyKey(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain)] =
          FakeControlProperty(scalar: Float32(scalar), settable: volume.canSet)
      }
      if let state = mute.state, state != .partial {
        properties[FakePropertyKey(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)] =
          FakeControlProperty(mute: state == .muted, settable: mute.canSet)
      }
    }
    return FakeDevice(
      isDevice: true,
      isAlive: alive,
      isHidden: hidden,
      canBeDefault: canBeDefault,
      channels: channels,
      name: name,
      uid: uid,
      volume: volume,
      mute: mute,
      controlProperties: properties
    )
  }
}
