import AudioToolbox
import CoreAudio
import XCTest

@testable import StatusTrioCore

@MainActor
final class AudioInputMonitorTests: XCTestCase {
  private let firstDevice = AudioInputDevice(id: 11, uid: "first", name: "Built-in Mic")
  private let secondDevice = AudioInputDevice(id: 22, uid: "second", name: "USB Mic")

  func testDefaultOffAndVisibleDoesNotEnumerateUntilEnabled() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    monitor.setVisible(true)
    XCTAssertEqual(hardware.observationCount, 0)
    XCTAssertEqual(hardware.fullReadCount, 0)
    XCTAssertEqual(hardware.usageReadCount, 0)

    let firstRead = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    await fulfillment(of: [firstRead], timeout: 5)

    XCTAssertEqual(hardware.observationCount, 1)
    XCTAssertEqual(hardware.readRequests, [true])
  }

  func testReenabledRefreshFailureCannotApplyVolumeOrMuteUsingPreviousDefault() async throws {
    let readGate = ManualAudioGate()
    let readStarted = expectation(description: "reenabled full read started")
    readGate.onEnter = { readStarted.fulfill() }
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      readGate.release()
    }

    let initial = log.expectStatus("initial default input is read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)

    monitor.setEnabled(false)
    hardware.setReading(reading(defaultID: 22, scalar: 0.73))
    hardware.blockNextRead(with: readGate)
    hardware.failNextRead(with: .unavailable)

    let refreshing = log.expectStatus("new session refresh is in progress") { $0.isRefreshing }
    monitor.setEnabled(true)
    await fulfillment(of: [readStarted, refreshing], timeout: 5)
    readGate.release()

    let failed = log.expectStatus("failed refresh leaves no usable old readback") {
      $0.error == .refreshFailed && !$0.isRefreshing && !$0.isBusy
    }
    await fulfillment(of: [failed], timeout: 5)
    let failedStatus = try XCTUnwrap(log.values.last)
    XCTAssertNil(failedStatus.defaultDeviceID)
    XCTAssertNil(failedStatus.scalar)
    XCTAssertNil(failedStatus.muteState)

    // Wait for each attempted operation's own terminal failure. An idle-status waiter
    // can match a status that predates the asynchronous command and mask a false positive.
    let volumeRejected = log.expectStatus("racing volume action is processed and rejected") {
      $0.error == .volumeFailed && !$0.isBusy && !$0.isRefreshing
    }
    monitor.setScalar(0.9)
    await fulfillment(of: [volumeRejected], timeout: 5)

    let muteRejected = log.expectStatus("racing mute action is processed and rejected") {
      $0.error == .muteFailed && !$0.isBusy && !$0.isRefreshing
    }
    monitor.toggleMute()
    await fulfillment(of: [muteRejected], timeout: 5)

    XCTAssertTrue(hardware.scalarWriteTargets.isEmpty, "volume must not be sent to the previous device")
    XCTAssertTrue(hardware.muteWriteTargets.isEmpty, "mute must not be sent to the previous device")
  }

  func testCommandsQueuedDuringRefreshAreDiscardedWhenReadFails() async throws {
    let readGate = ManualAudioGate()
    let readStarted = expectation(description: "refresh read started")
    readGate.onEnter = { readStarted.fulfill() }
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      readGate.release()
    }

    let initial = log.expectStatus("initial default input is read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)

    hardware.setReading(reading(defaultID: 22, scalar: 0.73))
    hardware.blockNextRead(with: readGate)
    hardware.failNextRead(with: .unavailable)
    let refreshing = log.expectStatus("read is in progress") { $0.isRefreshing }
    monitor.recover()
    await fulfillment(of: [readStarted, refreshing], timeout: 5)

    let queued = log.expectStatus("control command is queued behind refresh") {
      $0.isBusy && $0.isRefreshing
    }
    monitor.setScalar(0.9)
    monitor.toggleMute()
    await fulfillment(of: [queued], timeout: 5)

    let failed = log.expectStatus("failed refresh discards queued controls") {
      $0.error == .refreshFailed && !$0.isRefreshing && !$0.isBusy
    }
    readGate.release()
    await fulfillment(of: [failed], timeout: 5)

    XCTAssertTrue(hardware.scalarWriteTargets.isEmpty, "queued volume must be dropped after refresh failure")
    XCTAssertTrue(hardware.muteWriteTargets.isEmpty, "queued mute must be dropped after refresh failure")
  }

  func testEnableIsIdempotentAndHiddenEventsOnlyMarkStatusDirty() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    monitor.setEnabled(true)
    monitor.setEnabled(true)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))
    XCTAssertEqual(hardware.observationCount, 1)
    XCTAssertEqual(hardware.fullReadCount, 0)

    observation.emit(.controlsChanged)
    XCTAssertEqual(hardware.fullReadCount, 0)

    let opened = log.expectStatus("opening panel reads all devices") { $0.defaultDeviceID == 11 }
    monitor.setVisible(true)
    await fulfillment(of: [opened], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true])

    monitor.setVisible(false)
    observation.emit(.devicesChanged)
    XCTAssertEqual(hardware.fullReadCount, 1)

    let reopened = log.expectStatus("reopening panel refreshes dirty devices") {
      $0.defaultDeviceID == 11 && !$0.isRefreshing
    }
    monitor.setVisible(true)
    await fulfillment(of: [reopened], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true, true])
  }

  func testExternalDefaultChangeRefreshesAndRebindsCurrentDevice() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, isDefaultInputInUse: true))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let firstRead = log.expectStatus("first default device is in use") {
      $0.defaultDeviceID == 11 && $0.isDefaultInputInUse == true
    }
    monitor.setVisible(true)
    monitor.setEnabled(true)
    await fulfillment(of: [firstRead], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))
    XCTAssertTrue(observation.waitForCurrentDevice(11, timeout: 5))

    hardware.setReading(reading(defaultID: 22, isDefaultInputInUse: false))
    let switched = log.expectStatus("external default-device change clears the previous use state") {
      $0.defaultDeviceID == 22 && $0.isDefaultInputInUse == false
    }
    observation.emit(.defaultChanged)
    await fulfillment(of: [switched], timeout: 5)

    XCTAssertTrue(observation.waitForCurrentDevice(22, timeout: 5))
    XCTAssertEqual(hardware.readRequests, [true, true])
  }

  func testVisibleControlChangeRefreshesScalarAndMuteState() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    hardware.setReading(reading(defaultID: 11, scalar: 0.81, muteState: .muted))
    let changed = log.expectStatus("external input-control change is read back") {
      $0.defaultDeviceID == 11 && $0.scalar == 0.81 && $0.muteState == .muted
    }
    observation.emit(.controlsChanged)
    await fulfillment(of: [changed], timeout: 5)

    XCTAssertEqual(hardware.readRequests, [true, true])
  }

  func testVisiblePanelPollsOnlyDefaultInputUsageAndStopsWhenHidden() async throws {
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(
      reading: reading(defaultID: 11, isDefaultInputInUse: false)
    )
    let monitor = AudioInputMonitor(
      hardware: hardware,
      usageSleep: { try await sleeper.sleep(for: $0) },
      sleep: { try await sleeper.sleep(for: $0) }
    )
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let initial = log.expectStatus("initial default input is idle") {
      $0.defaultDeviceID == 11 && $0.isDefaultInputInUse == false
    }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)

    let pollScheduled = sleeper.expectCall(.seconds(1), count: 1)
    await fulfillment(of: [pollScheduled], timeout: 5)
    hardware.setUsageReading(AudioInputUsageReading(defaultDeviceID: 11, isDefaultInputInUse: true))
    let becameActive = log.expectStatus("active input stream updates the visible status") {
      $0.isDefaultInputInUse == true
    }
    XCTAssertTrue(sleeper.releaseNext(.seconds(1)))
    await fulfillment(of: [becameActive], timeout: 5)

    XCTAssertEqual(hardware.usageReadCount, 1)
    XCTAssertEqual(hardware.readRequests, [true], "usage polling must not enumerate the device list")
    monitor.setVisible(false)
    XCTAssertEqual(hardware.usageReadCount, 1, "hidden popovers stop input-use polling")
  }

  func testDeviceRemovalRefreshesInventoryAndClearsDefaultControls() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let initial = log.expectStatus("initial device inventory") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    let remainingDevice = secondDevice
    hardware.setReading(AudioInputReading(
      devices: [remainingDevice],
      defaultDeviceID: nil,
      deviceName: nil,
      scalar: nil,
      canSetVolume: false,
      muteState: nil,
      canSetMute: false
    ))
    let removed = log.expectStatus("device removal refreshes inventory and clears controls") {
      $0.devices == [remainingDevice] && $0.defaultDeviceID == nil
        && $0.scalar == nil && $0.muteState == nil
    }
    observation.emit(.devicesChanged)
    await fulfillment(of: [removed], timeout: 5)

    XCTAssertNil(observation.currentDevice)
    XCTAssertEqual(hardware.readRequests, [true, true])
  }

  func testRecoverRefreshesAndStoppedObservationCallbackIsIgnored() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let initial = log.expectStatus("initial refresh") {
      $0.defaultDeviceID == 11 && !$0.isRefreshing
    }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    // A cached status announcing the refresh must not satisfy this wait.
    hardware.setReading(reading(defaultID: 22))
    let recovered = log.expectStatus("sleep recovery refresh") {
      $0.defaultDeviceID == 22 && !$0.isRefreshing
    }
    monitor.recover()
    await fulfillment(of: [recovered], timeout: 5)
    XCTAssertEqual(hardware.fullReadCount, 2)

    monitor.setEnabled(false)
    XCTAssertTrue(observation.waitUntilStopped(timeout: 5))
    let readsAtStop = hardware.fullReadCount
    observation.emit(.controlsChanged, evenIfStopped: true)
    XCTAssertEqual(hardware.fullReadCount, readsAtStop)
  }

  func testSelectAndMuteRequireSystemReadbackConfirmation() async throws {
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setVisible(true)
    monitor.setEnabled(true)
    await fulfillment(of: [initial], timeout: 5)

    let selected = log.expectStatus("selected device confirmed from HAL") {
      $0.defaultDeviceID == 22 && !$0.isBusy && $0.error == nil
    }
    monitor.select(22)
    await fulfillment(of: [selected], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true, false])

    let muted = log.expectStatus("mute state confirmed from HAL") {
      $0.defaultDeviceID == 22 && $0.muteState == .muted && !$0.isBusy && $0.error == nil
    }
    monitor.toggleMute()
    await fulfillment(of: [muted], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true, false, false])
  }

  func testCoreAudioObservationRebindsAndRemovesCapturedListeners() throws {
    let propertyClient = FakeObservedAudioInputProperties()
    let listenerClient = FakeAudioInputListenerClient()
    let hardware = CoreAudioInputHardware(client: propertyClient, listenerClient: listenerClient)
    let eventLog = LockedAudioInputEvents()
    let observation = try hardware.observe { eventLog.append($0) }

    XCTAssertEqual(listenerClient.added.count, 2, "Only global device/default listeners start enabled")
    try observation.setCurrentDevice(11)
    let firstDeviceListeners = listenerClient.added.filter { $0.objectID == 11 }
    XCTAssertEqual(firstDeviceListeners.count, 6, "Main plus both input channels for volume and mute")
    XCTAssertTrue(firstDeviceListeners.allSatisfy { $0.address.mScope == kAudioObjectPropertyScopeInput })

    try observation.setCurrentDevice(22)
    XCTAssertEqual(listenerClient.removed.count, 6)
    let activeDeviceListeners = listenerClient.added.filter { $0.objectID == 22 }
    XCTAssertEqual(activeDeviceListeners.count, 6)

    for registration in firstDeviceListeners {
      registration.fire()
    }
    XCTAssertTrue(eventLog.events.isEmpty, "Callbacks from the prior device binding must be ignored")

    observation.stop()
    XCTAssertEqual(listenerClient.removed.count, listenerClient.added.count)
    XCTAssertEqual(listenerClient.mismatchedRemovals, 0, "Removal must use the captured object/address/queue")
    for registration in listenerClient.added {
      XCTAssertTrue(listenerClient.removed.contains { $0.matches(registration) })
    }
  }


  func testCoreAudioObservationReadsChannelCountOnceDuringHotUnplugRebind() throws {
    let propertyClient = FakeObservedAudioInputProperties(channelCounts: [1, 0])
    let listenerClient = FakeAudioInputListenerClient()
    let hardware = CoreAudioInputHardware(client: propertyClient, listenerClient: listenerClient)
    let observation = try hardware.observe { _ in }
    defer { observation.stop() }

    XCTAssertNoThrow(try observation.setCurrentDevice(11))
    XCTAssertEqual(propertyClient.channelCountReadCount, 1)
    XCTAssertEqual(listenerClient.added.filter { $0.objectID == 11 }.count, 4)
  }

  func testRejectedControlListenerReportsDegradationAndRecoverRetriesBinding() async throws {
    let propertyClient = FakeObservedAudioInputProperties()
    let listenerClient = FakeAudioInputListenerClient()
    listenerClient.rejectNextRegistration(
      objectID: 11,
      selector: kAudioDevicePropertyMute,
      status: OSStatus(-1)
    )
    let hardware = CoreAudioInputHardware(client: propertyClient, listenerClient: listenerClient)
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer { monitor.stop() }

    let degraded = log.expectStatus("listener rejection is visible while fresh reading is retained") {
      $0.defaultDeviceID == 11 && $0.error == .refreshFailed && !$0.isRefreshing
    }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [degraded], timeout: 5)

    XCTAssertEqual(listenerClient.removed.count, 3, "Partial per-device registration must be rolled back")

    let recovered = log.expectStatus("recover retries the failed device binding") {
      $0.defaultDeviceID == 11 && $0.error == nil && !$0.isRefreshing
    }
    monitor.recover()
    await fulfillment(of: [recovered], timeout: 5)
    XCTAssertEqual(listenerClient.added.filter { $0.objectID == 11 }.count - listenerClient.removed.count, 6)
  }

  func testScalarReadbackFromNewDefaultCannotConfirmWriteToOriginalDevice() async throws {
    let writeGate = ManualAudioGate()
    let writeStarted = expectation(description: "scalar HAL write started")
    writeGate.onEnter = { writeStarted.fulfill() }
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    hardware.blockNextScalarWrite(with: writeGate)
    let monitor = AudioInputMonitor(hardware: hardware, sleep: { try await sleeper.sleep(for: $0) })
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
      writeGate.release()
    }

    let initial = log.expectStatus("initial device read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)

    let rejected = log.expectStatus("matching scalar on a different device is not confirmation") {
      $0.error == .volumeFailed
    }
    let coalesced = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.8)
    await fulfillment(of: [coalesced], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    await fulfillment(of: [writeStarted], timeout: 5)

    hardware.setReading(reading(defaultID: 22, scalar: 0.8))
    writeGate.release()
    await fulfillment(of: [rejected], timeout: 5)
    XCTAssertEqual(hardware.scalarWrites, [0.8])
  }

  func testMuteReadbackFromNewDefaultCannotConfirmWriteToOriginalDevice() async throws {
    let writeGate = ManualAudioGate()
    let writeStarted = expectation(description: "mute HAL write started")
    writeGate.onEnter = { writeStarted.fulfill() }
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    hardware.blockNextMuteWrite(with: writeGate)
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      writeGate.release()
    }

    let initial = log.expectStatus("initial device read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)

    let rejected = log.expectStatus("matching mute state on a different device is not confirmation") {
      $0.error == .muteFailed
    }
    monitor.toggleMute()
    await fulfillment(of: [writeStarted], timeout: 5)

    hardware.setReading(reading(defaultID: 22, muteState: .muted))
    writeGate.release()
    await fulfillment(of: [rejected], timeout: 5)
  }

  func testDebouncedScalarKeepsDeviceIdentityAcrossBlockedRefreshAndDefaultSwitch() async throws {
    let readGate = ManualAudioGate()
    let readStarted = expectation(description: "refresh read started")
    readGate.onEnter = { readStarted.fulfill() }
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    let monitor = AudioInputMonitor(hardware: hardware, sleep: { try await sleeper.sleep(for: $0) })
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
      readGate.release()
    }

    let initial = log.expectStatus("initial device read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    hardware.blockNextRead(with: readGate, readAfterRelease: true)
    observation.emit(.defaultChanged)
    await fulfillment(of: [readStarted], timeout: 5)

    let coalesced = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.9)
    await fulfillment(of: [coalesced], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))

    let rejected = log.expectStatus("pending scalar for old input is rejected after device changes") {
      $0.defaultDeviceID == 22 && $0.error == .volumeFailed
    }
    hardware.setReading(reading(defaultID: 22, scalar: 0.7))
    readGate.release()
    await fulfillment(of: [rejected], timeout: 5)
    XCTAssertTrue(hardware.scalarWrites.isEmpty)
  }

  func testStaleBlockedReadCannotPublishAfterStop() async throws {
    let readGate = ManualAudioGate()
    let readStarted = expectation(description: "full read entered the gate")
    let readReturned = expectation(description: "blocked read returned")
    readGate.onEnter = { readStarted.fulfill() }
    readGate.onExit = { readReturned.fulfill() }
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    hardware.blockNextRead(with: readGate)
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    let refreshing = log.expectStatus("refresh starts") { $0.isRefreshing }

    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [readStarted, refreshing], timeout: 5)
    let updatesAtStop = log.values.count
    monitor.stop()
    readGate.release()
    await fulfillment(of: [readReturned], timeout: 5)

    XCTAssertEqual(log.values.count, updatesAtStop, "A completion after stop must not publish")
    XCTAssertTrue(hardware.waitForObservation(timeout: 5)?.waitUntilStopped(timeout: 5) ?? false)
  }

  func testHidingCancelsQueuedFullReadAndReopeningRunsOneRead() async throws {
    let observationGate = ManualAudioGate()
    let observationStarted = expectation(description: "observation registration blocks worker")
    observationGate.onEnter = { observationStarted.fulfill() }
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    hardware.blockNextObservation(with: observationGate)
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      observationGate.release()
    }

    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [observationStarted], timeout: 5)

    monitor.setVisible(false)
    observationGate.release()
    let reopenedSnapshot = log.expectStatus("reopened panel receives a fresh snapshot") {
      $0.defaultDeviceID == 11
    }
    monitor.setVisible(true)
    await fulfillment(of: [reopenedSnapshot], timeout: 5)

    XCTAssertEqual(hardware.readRequests, [true], "The hidden queued read must be cancelled")
  }

  func testScalarDragKeepsOnlyLatestPendingTargetAndWritesSerially() async throws {
    let firstWriteGate = ManualAudioGate()
    let firstWriteStarted = expectation(description: "first scalar write started")
    firstWriteGate.onEnter = { firstWriteStarted.fulfill() }
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    hardware.blockNextScalarWrite(with: firstWriteGate)
    let monitor = AudioInputMonitor(
      hardware: hardware,
      sleep: { try await sleeper.sleep(for: $0) }
    )
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
    }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setVisible(true)
    monitor.setEnabled(true)
    await fulfillment(of: [initial], timeout: 5)

    let firstWindow = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.2)
    await fulfillment(of: [firstWindow], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    await fulfillment(of: [firstWriteStarted], timeout: 5)

    let secondWindow = sleeper.expectCall(.milliseconds(80), count: 2)
    monitor.setScalar(0.4)
    await fulfillment(of: [secondWindow], timeout: 5)
    let thirdWindow = sleeper.expectCall(.milliseconds(80), count: 3)
    monitor.setScalar(0.8)
    await fulfillment(of: [thirdWindow], timeout: 5)
    let latestConfirmed = log.expectStatus("latest scalar readback") {
      $0.scalar == 0.8 && $0.error == nil
    }
    sleeper.releaseAll(.milliseconds(80))
    firstWriteGate.release()
    await fulfillment(of: [latestConfirmed], timeout: 5)

    XCTAssertEqual(hardware.scalarWrites, [0.2, 0.8])
    XCTAssertEqual(hardware.maximumConcurrentWrites, 1)
  }

  func testTimedOutWriteDoesNotReenterUntilBlockedHALCallReturns() async throws {
    let writeGate = ManualAudioGate()
    let writeStarted = expectation(description: "HAL scalar write started")
    writeGate.onEnter = { writeStarted.fulfill() }
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    hardware.blockNextScalarWrite(with: writeGate)
    let monitor = AudioInputMonitor(
      hardware: hardware,
      commandTimeout: .seconds(1),
      sleep: { try await sleeper.sleep(for: $0) }
    )
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
      writeGate.release()
    }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)

    let coalescing = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.3)
    await fulfillment(of: [coalescing], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    let timeoutScheduled = sleeper.expectCall(.seconds(1), count: 1)
    await fulfillment(of: [writeStarted, timeoutScheduled], timeout: 5)

    let timedOut = log.expectStatus("timed-out scalar command") { $0.error == .timedOut }
    sleeper.releaseNext(.seconds(1))
    await fulfillment(of: [timedOut], timeout: 5)

    let nextCoalesce = sleeper.expectCall(.milliseconds(80), count: 2)
    monitor.setScalar(0.9)
    await fulfillment(of: [nextCoalesce], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    XCTAssertEqual(hardware.scalarWriteCount, 1, "A timed-out synchronous write still owns the sole writer")
    let refreshed = log.expectStatus("late completion refreshes actual hardware state") {
      $0.scalar == 0.3 && !$0.isRefreshing
    }
    writeGate.release()

    await fulfillment(of: [refreshed], timeout: 5)
    XCTAssertEqual(hardware.maximumConcurrentWrites, 1)
  }

  func testTimedOutWriteCompletionAfterDeviceSwitchCannotPublishOldDeviceState() async throws {
    let writeGate = ManualAudioGate()
    let writeStarted = expectation(description: "old-device HAL write started")
    writeGate.onEnter = { writeStarted.fulfill() }
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    hardware.blockNextScalarWrite(with: writeGate)
    let monitor = AudioInputMonitor(
      hardware: hardware,
      commandTimeout: .seconds(1),
      sleep: { try await sleeper.sleep(for: $0) }
    )
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
      writeGate.release()
    }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [initial], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    let scalarDebounce = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.9)
    await fulfillment(of: [scalarDebounce], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    let timeoutScheduled = sleeper.expectCall(.seconds(1), count: 1)
    await fulfillment(of: [writeStarted, timeoutScheduled], timeout: 5)

    hardware.setReading(reading(defaultID: 22, scalar: 0.77))
    let invalidated = log.expectStatus("device event invalidates old-device completion") {
      $0.defaultDeviceID == 11 && $0.isRefreshing
    }
    observation.emit(.defaultChanged)
    await fulfillment(of: [invalidated], timeout: 5)

    let timedOut = log.expectStatus("old-device command reaches timeout") { $0.error == .timedOut }
    XCTAssertTrue(sleeper.releaseNext(.seconds(1)))
    await fulfillment(of: [timedOut], timeout: 5)

    let latest = log.expectStatus("late old-device completion leaves new system device intact") {
      $0.defaultDeviceID == 22 && $0.scalar == 0.77 && !$0.isBusy && !$0.isRefreshing
    }
    writeGate.release()
    await fulfillment(of: [latest], timeout: 5)

    XCTAssertTrue(observation.waitForCurrentDevice(22, timeout: 5))
    XCTAssertEqual(hardware.scalarWriteCount, 1)
    XCTAssertEqual(hardware.maximumConcurrentWrites, 1)
    XCTAssertEqual(hardware.readRequests, [true, false, true])
    XCTAssertFalse(log.values.contains { $0.defaultDeviceID == 11 && $0.scalar == 0.9 })
  }

  func testWriteFailureDoesNotPretendTheTargetWasApplied() async throws {
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    hardware.failScalarWrites(with: .unavailable)
    let monitor = AudioInputMonitor(
      hardware: hardware,
      sleep: { try await sleeper.sleep(for: $0) }
    )
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
    }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setVisible(true)
    monitor.setEnabled(true)
    await fulfillment(of: [initial], timeout: 5)

    let failed = log.expectStatus("HAL write failure is surfaced") {
      $0.error == .volumeFailed && $0.scalar == 0.1 && !$0.isBusy
    }
    let coalescing = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.9)
    await fulfillment(of: [coalescing], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    await fulfillment(of: [failed], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true, false])
  }

  func testReadInvalidatedByASecondEventIsDiscardedAndMergedRefreshRuns() async throws {
    let gate = ManualAudioGate()
    let firstReadStarted = expectation(description: "first full read entered gate")
    gate.onEnter = { firstReadStarted.fulfill() }
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11))
    hardware.blockNextRead(with: gate)
    let monitor = AudioInputMonitor(hardware: hardware)
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      gate.release()
    }

    let firstRead = log.expectStatus("initial read begins") { $0.isRefreshing }
    monitor.setEnabled(true)
    monitor.setVisible(true)
    await fulfillment(of: [firstReadStarted, firstRead], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    let invalidated = log.expectStatus("event invalidates blocked read") { $0.isRefreshing }
    observation.emit(.defaultChanged)
    await fulfillment(of: [invalidated], timeout: 5)
    hardware.setReading(reading(defaultID: 22, scalar: 0.7))
    gate.release()

    let latest = log.expectStatus("latest read wins") {
      $0.defaultDeviceID == 22 && $0.scalar == 0.7 && !$0.isRefreshing
    }
    await fulfillment(of: [latest], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true, true])
    XCTAssertFalse(log.values.contains { $0.defaultDeviceID == 11 })
  }

  func testStopPreventsReadbackAfterAnAlreadyStartedWrite() async throws {
    let writeGate = ManualAudioGate()
    let writeStarted = expectation(description: "HAL write started")
    let writeReturned = expectation(description: "HAL write returned")
    writeGate.onEnter = { writeStarted.fulfill() }
    writeGate.onExit = { writeReturned.fulfill() }
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(reading: reading(defaultID: 11, scalar: 0.1))
    hardware.blockNextScalarWrite(with: writeGate)
    let monitor = AudioInputMonitor(
      hardware: hardware,
      sleep: { try await sleeper.sleep(for: $0) }
    )
    defer {
      monitor.stop()
      sleeper.releaseAll()
      writeGate.release()
    }

    let initial = AudioInputStatusLog(monitor.updates).expectStatus("initial read") {
      $0.defaultDeviceID == 11
    }
    monitor.setVisible(true)
    monitor.setEnabled(true)
    await fulfillment(of: [initial], timeout: 5)
    let observation = try XCTUnwrap(hardware.waitForObservation(timeout: 5))

    let coalescing = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.3)
    await fulfillment(of: [coalescing], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    await fulfillment(of: [writeStarted], timeout: 5)
    XCTAssertEqual(hardware.readRequests, [true])

    monitor.stop()
    writeGate.release()
    await fulfillment(of: [writeReturned], timeout: 5)
    XCTAssertTrue(observation.waitUntilStopped(timeout: 5))
    XCTAssertEqual(hardware.readRequests, [true], "A stopped session must not issue the post-write readback")
  }

  func testReadbackMismatchReportsFailureThenErrorExpiresAndNewActionClearsIt() async throws {
    let sleeper = ManualAudioSleeper()
    let hardware = FakeAudioInputHardware(
      reading: reading(defaultID: 11, scalar: 0.1),
      ignoresScalarWrites: true
    )
    let monitor = AudioInputMonitor(
      hardware: hardware,
      sleep: { try await sleeper.sleep(for: $0) }
    )
    let log = AudioInputStatusLog(monitor.updates)
    defer {
      monitor.stop()
      sleeper.releaseAll()
    }

    let initial = log.expectStatus("initial visible read") { $0.defaultDeviceID == 11 }
    monitor.setVisible(true)
    monitor.setEnabled(true)
    await fulfillment(of: [initial], timeout: 5)

    let mismatch = log.expectStatus("target must be verified against readback") {
      $0.error == .volumeFailed
    }
    let coalesced = sleeper.expectCall(.milliseconds(80), count: 1)
    monitor.setScalar(0.9)
    await fulfillment(of: [coalesced], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    let firstExpiry = sleeper.expectCall(.seconds(4), count: 1)
    await fulfillment(of: [mismatch, firstExpiry], timeout: 5)
    XCTAssertEqual(log.values.last?.scalar, 0.1)

    let expired = log.expectStatus("failure clears after four seconds") { $0.error == nil }
    XCTAssertTrue(sleeper.releaseNext(.seconds(4)))
    await fulfillment(of: [expired], timeout: 5)

    let failedAgain = log.expectStatus("second readback failure") { $0.error == .volumeFailed }
    let secondCoalesce = sleeper.expectCall(.milliseconds(80), count: 2)
    monitor.setScalar(0.7)
    await fulfillment(of: [secondCoalesce], timeout: 5)
    XCTAssertTrue(sleeper.releaseNext(.milliseconds(80)))
    let secondExpiry = sleeper.expectCall(.seconds(4), count: 2)
    await fulfillment(of: [failedAgain, secondExpiry], timeout: 5)

    let clearedByAction = log.expectStatus("new action immediately clears prior failure") {
      $0.error == nil
    }
    monitor.setScalar(0.6)
    await fulfillment(of: [clearedByAction], timeout: 5)
  }

  private func reading(
    defaultID: AudioDeviceID?,
    scalar: Double? = 0.42,
    muteState: AudioInputMuteState = .unmuted,
    isDefaultInputInUse: Bool? = nil
  ) -> AudioInputReading {
    AudioInputReading(
      devices: [firstDevice, secondDevice],
      defaultDeviceID: defaultID,
      deviceName: [firstDevice, secondDevice].first { $0.id == defaultID }?.name,
      scalar: defaultID == nil ? nil : scalar,
      canSetVolume: defaultID != nil,
      muteState: defaultID == nil ? nil : muteState,
      canSetMute: defaultID != nil,
      isDefaultInputInUse: isDefaultInputInUse
    )
  }
}

private final class AudioInputStatusLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValues: [AudioInputStatus] = []
  private var waiters: [(@Sendable (AudioInputStatus) -> Bool, XCTestExpectation)] = []

  var values: [AudioInputStatus] {
    lock.lock()
    defer { lock.unlock() }
    return storedValues
  }

  init(_ updates: AsyncStream<AudioInputStatus>) {
    Task {
      for await status in updates {
        self.append(status)
      }
    }
  }

  func expectStatus(
    _ description: String,
    where predicate: @escaping @Sendable (AudioInputStatus) -> Bool
  ) -> XCTestExpectation {
    let expectation = XCTestExpectation(description: description)
    lock.lock()
    waiters.append((predicate, expectation))
    lock.unlock()
    return expectation
  }

  private func append(_ status: AudioInputStatus) {
    lock.lock()
    storedValues.append(status)
    let matching = waiters.filter { $0.0(status) }
    waiters.removeAll { waiter in matching.contains { $0.1 === waiter.1 } }
    lock.unlock()
    matching.forEach { $0.1.fulfill() }
  }
}

private final class ManualAudioGate: @unchecked Sendable {
  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var didRelease = false
  var onEnter: (@Sendable () -> Void)?
  var onExit: (@Sendable () -> Void)?

  func wait() {
    onEnter?()
    semaphore.wait()
    lock.lock()
    didRelease = true
    lock.unlock()
    onExit?()
  }

  func release() {
    lock.lock()
    let shouldSignal = !didRelease
    didRelease = true
    lock.unlock()
    if shouldSignal { semaphore.signal() }
  }
}

private final class ManualAudioSleeper: @unchecked Sendable {
  private struct Waiter {
    let id: UUID
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var waiters: [Waiter] = []
  private var cancelledBeforeRegistration = Set<UUID>()
  private var callCounts: [(Duration, Int)] = []
  private var callExpectations: [(Duration, Int, XCTestExpectation)] = []

  func expectCall(_ duration: Duration, count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "sleep(\(duration)) call \(count)")
    lock.lock()
    let observed = callCounts.first { $0.0 == duration }?.1 ?? 0
    if observed < count { callExpectations.append((duration, count, expectation)) }
    lock.unlock()
    if observed >= count { expectation.fulfill() }
    return expectation
  }

  func sleep(for duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler(
      operation: {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        lock.lock()
        if cancelledBeforeRegistration.remove(id) != nil {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
          return
        }
        waiters.append(Waiter(id: id, duration: duration, continuation: continuation))
        let index = callCounts.firstIndex { $0.0 == duration }
        if let index { callCounts[index].1 += 1 } else { callCounts.append((duration, 1)) }
        let callCount = callCounts.first { $0.0 == duration }!.1
        let satisfied = callExpectations.filter { $0.0 == duration && $0.1 <= callCount }
        callExpectations.removeAll { candidate in satisfied.contains { $0.2 === candidate.2 } }
        lock.unlock()
          satisfied.forEach { $0.2.fulfill() }
        }
      },
      onCancel: { self.cancel(id) }
    )
  }

  @discardableResult
  func releaseNext(_ duration: Duration) -> Bool {
    lock.lock()
    guard let index = waiters.firstIndex(where: { $0.duration == duration }) else {
      lock.unlock()
      return false
    }
    let waiter = waiters.remove(at: index)
    lock.unlock()
    waiter.continuation.resume()
    return true
  }

  func releaseAll(_ duration: Duration? = nil) {
    lock.lock()
    let released = waiters.filter { duration == nil || $0.duration == duration }
    waiters.removeAll { waiter in released.contains { $0.id == waiter.id } }
    lock.unlock()
    released.forEach { $0.continuation.resume() }
  }

  private func cancel(_ id: UUID) {
    lock.lock()
    if let index = waiters.firstIndex(where: { $0.id == id }) {
      let waiter = waiters.remove(at: index)
      lock.unlock()
      waiter.continuation.resume(throwing: CancellationError())
    } else {
      cancelledBeforeRegistration.insert(id)
      lock.unlock()
    }
  }
}

private final class FakeAudioInputObservation: AudioInputObservation, @unchecked Sendable {
  private let lock = NSLock()
  private let notify: @Sendable (AudioInputEvent) -> Void
  private var stopped = false
  private var currentDeviceID: AudioDeviceID?
  private let currentDeviceChanged = DispatchSemaphore(value: 0)
  private let stoppedSignal = DispatchSemaphore(value: 0)

  init(notify: @escaping @Sendable (AudioInputEvent) -> Void) {
    self.notify = notify
  }

  var isStopped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }

  var currentDevice: AudioDeviceID? {
    lock.lock()
    defer { lock.unlock() }
    return currentDeviceID
  }

  func setCurrentDevice(_ id: AudioDeviceID?) throws {
    lock.lock()
    currentDeviceID = id
    lock.unlock()
    currentDeviceChanged.signal()
  }

  func waitForCurrentDevice(_ id: AudioDeviceID, timeout: TimeInterval) -> Bool {
    let deadline = DispatchTime.now() + timeout
    while currentDevice != id {
      guard currentDeviceChanged.wait(timeout: deadline) == .success else { return false }
    }
    return true
  }

  func stop() {
    lock.lock()
    let shouldSignal = !stopped
    stopped = true
    lock.unlock()
    if shouldSignal { stoppedSignal.signal() }
  }

  func waitUntilStopped(timeout: TimeInterval) -> Bool {
    isStopped || stoppedSignal.wait(timeout: .now() + timeout) == .success
  }

  func emit(_ event: AudioInputEvent, evenIfStopped: Bool = false) {
    lock.lock()
    let shouldNotify = evenIfStopped || !stopped
    lock.unlock()
    if shouldNotify { notify(event) }
  }
}

private final class LockedAudioInputEvents: @unchecked Sendable {
  private let lock = NSLock()
  private var storedEvents: [AudioInputEvent] = []

  var events: [AudioInputEvent] {
    lock.lock()
    defer { lock.unlock() }
    return storedEvents
  }

  func append(_ event: AudioInputEvent) {
    lock.lock()
    storedEvents.append(event)
    lock.unlock()
  }
}

private struct FakeObservedAudioInputProperties: AudioInputPropertyClient {
  private let channelCounts: SequencedAudioInputChannelCounts

  init(channelCounts: [Int] = [2]) {
    self.channelCounts = SequencedAudioInputChannelCounts(channelCounts)
  }

  var channelCountReadCount: Int { channelCounts.readCount }

  func devices() throws -> [AudioDeviceID] { [11, 22] }
  func defaultInput() throws -> AudioDeviceID? { 11 }
  func activeInputProcessUsage() -> AudioInputProcessDeviceUsage? {
    AudioInputProcessDeviceUsage(activeInputDeviceIDs: [], isComplete: true)
  }
  func isDevice(_ id: AudioDeviceID) -> Bool { id == 11 || id == 22 }
  func isAlive(_ id: AudioDeviceID) -> Bool? { isDevice(id) }
  func isHidden(_ id: AudioDeviceID) -> Bool? { false }
  func canBeDefaultInput(_ id: AudioDeviceID) -> Bool? { isDevice(id) }
  func inputChannels(_ id: AudioDeviceID) -> Int { isDevice(id) ? channelCounts.next() : 0 }
  func name(_ id: AudioDeviceID) -> String? { "Device \(id)" }
  func uid(_ id: AudioDeviceID) -> String? { "device-\(id)" }
  func hasProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool {
    isDevice(id) && (0...2).contains(Int(element))
      && (selector == kAudioDevicePropertyVolumeScalar || selector == kAudioDevicePropertyMute)
  }
  func isSettable(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool { false }
  func readScalar(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Float32? { nil }
  func readMute(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool? { nil }
  func writeScalar(
    _ value: Float32,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws { throw AudioInputHardwareError.unsupported }
  func writeMute(
    _ value: Bool,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws { throw AudioInputHardwareError.unsupported }
  func writeDefaultInput(_ id: AudioDeviceID) throws { throw AudioInputHardwareError.unsupported }
}

private final class SequencedAudioInputChannelCounts: @unchecked Sendable {
  private let lock = NSLock()
  private let values: [Int]
  private var storedReadCount = 0

  init(_ values: [Int]) {
    self.values = values.isEmpty ? [0] : values
  }

  var readCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedReadCount
  }

  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    let index = min(storedReadCount, values.count - 1)
    storedReadCount += 1
    return values[index]
  }
}

private struct FakeAudioInputListenerRegistration {
  let objectID: AudioObjectID
  let address: AudioObjectPropertyAddress
  let queue: DispatchQueue?
  let block: AudioObjectPropertyListenerBlock

  func matches(_ other: Self) -> Bool {
    objectID == other.objectID
      && address.mSelector == other.address.mSelector
      && address.mScope == other.address.mScope
      && address.mElement == other.address.mElement
      && queue === other.queue
  }

  func fire() {
    var mutableAddress = address
    withUnsafePointer(to: &mutableAddress) { pointer in
      block(1, pointer)
    }
  }
}

private final class FakeAudioInputListenerClient: AudioInputPropertyListenerClient, @unchecked Sendable {
  private let lock = NSLock()
  private var storedAdded: [FakeAudioInputListenerRegistration] = []
  private var storedRemoved: [FakeAudioInputListenerRegistration] = []
  private var failedRemovalCount = 0
  private var rejection: (objectID: AudioObjectID, selector: AudioObjectPropertySelector, status: OSStatus)?

  var added: [FakeAudioInputListenerRegistration] {
    lock.lock()
    defer { lock.unlock() }
    return storedAdded
  }

  var removed: [FakeAudioInputListenerRegistration] {
    lock.lock()
    defer { lock.unlock() }
    return storedRemoved
  }

  var mismatchedRemovals: Int {
    lock.lock()
    defer { lock.unlock() }
    return failedRemovalCount
  }

  func rejectNextRegistration(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    status: OSStatus
  ) {
    lock.lock()
    rejection = (objectID, selector, status)
    lock.unlock()
  }

  func addListener(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    queue: DispatchQueue?,
    block: @escaping AudioObjectPropertyListenerBlock
  ) -> OSStatus {
    lock.lock()
    if let rejection, rejection.objectID == objectID, rejection.selector == address.mSelector {
      self.rejection = nil
      lock.unlock()
      return rejection.status
    }
    storedAdded.append(FakeAudioInputListenerRegistration(
      objectID: objectID,
      address: address,
      queue: queue,
      block: block
    ))
    lock.unlock()
    return noErr
  }

  func removeListener(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    queue: DispatchQueue?,
    block: @escaping AudioObjectPropertyListenerBlock
  ) -> OSStatus {
    let candidate = FakeAudioInputListenerRegistration(
      objectID: objectID,
      address: address,
      queue: queue,
      block: block
    )
    lock.lock()
    if storedAdded.contains(where: { $0.matches(candidate) }) {
      storedRemoved.append(candidate)
    } else {
      failedRemovalCount += 1
    }
    lock.unlock()
    return noErr
  }
}

private struct GatedAudioInputRead {
  let gate: ManualAudioGate
  let readAfterRelease: Bool
}

private final class FakeAudioInputHardware: AudioInputHardware, @unchecked Sendable {
  private let lock = NSLock()
  private var storedReading: AudioInputReading
  private var storedUsageReading: AudioInputUsageReading
  private var storedUsageReadCount = 0
  private var storedReadRequests: [Bool] = []
  private var observations: [FakeAudioInputObservation] = []
  private var observationGates: [ManualAudioGate] = []
  private var readGates: [GatedAudioInputRead] = []
  private var scalarWriteGates: [ManualAudioGate] = []
  private var muteWriteGates: [ManualAudioGate] = []
  private var writtenScalars: [Double] = []
  private var storedScalarWriteTargets: [AudioDeviceID] = []
  private var storedMuteWriteTargets: [AudioDeviceID] = []
  private var readErrors: [AudioInputHardwareError] = []
  private var activeWrites = 0
  private var maxConcurrentWrites = 0
  private let ignoresScalarWrites: Bool
  private var scalarWriteError: AudioInputHardwareError?

  private let observationCreated = DispatchSemaphore(value: 0)

  init(reading: AudioInputReading, ignoresScalarWrites: Bool = false) {
    storedReading = reading
    storedUsageReading = AudioInputUsageReading(
      defaultDeviceID: reading.defaultDeviceID,
      isDefaultInputInUse: reading.isDefaultInputInUse
    )
    self.ignoresScalarWrites = ignoresScalarWrites
  }

  var observationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return observations.count
  }

  var observationStopCount: Int {
    lock.lock()
    let count = observations.filter(\.isStopped).count
    lock.unlock()
    return count
  }

  var fullReadCount: Int { readRequests.filter { $0 }.count }

  var usageReadCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedUsageReadCount
  }

  var readRequests: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return storedReadRequests
  }

  var scalarWrites: [Double] {
    lock.lock()
    defer { lock.unlock() }
    return writtenScalars
  }

  var scalarWriteCount: Int { scalarWrites.count }

  var scalarWriteTargets: [AudioDeviceID] {
    lock.lock()
    defer { lock.unlock() }
    return storedScalarWriteTargets
  }

  var muteWriteTargets: [AudioDeviceID] {
    lock.lock()
    defer { lock.unlock() }
    return storedMuteWriteTargets
  }

  var maximumConcurrentWrites: Int {
    lock.lock()
    defer { lock.unlock() }
    return maxConcurrentWrites
  }

  func waitForObservation(timeout: TimeInterval) -> FakeAudioInputObservation? {
    guard observationCreated.wait(timeout: .now() + timeout) == .success else { return nil }
    lock.lock()
    let observation = observations.first
    lock.unlock()
    return observation
  }

  func setReading(_ reading: AudioInputReading) {
    lock.lock()
    storedReading = reading
    storedUsageReading = AudioInputUsageReading(
      defaultDeviceID: reading.defaultDeviceID,
      isDefaultInputInUse: reading.isDefaultInputInUse
    )
    lock.unlock()
  }

  func setUsageReading(_ reading: AudioInputUsageReading) {
    lock.lock()
    storedUsageReading = reading
    lock.unlock()
  }

  func blockNextObservation(with gate: ManualAudioGate) {
    lock.lock()
    observationGates.append(gate)
    lock.unlock()
  }

  func blockNextRead(with gate: ManualAudioGate, readAfterRelease: Bool = false) {
    lock.lock()
    readGates.append(GatedAudioInputRead(gate: gate, readAfterRelease: readAfterRelease))
    lock.unlock()
  }

  func failNextRead(with error: AudioInputHardwareError) {
    lock.lock()
    readErrors.append(error)
    lock.unlock()
  }

  func blockNextScalarWrite(with gate: ManualAudioGate) {
    lock.lock()
    scalarWriteGates.append(gate)
    lock.unlock()
  }

  func blockNextMuteWrite(with gate: ManualAudioGate) {
    lock.lock()
    muteWriteGates.append(gate)
    lock.unlock()
  }

  func failScalarWrites(with error: AudioInputHardwareError) {
    lock.lock()
    scalarWriteError = error
    lock.unlock()
  }

  func read(includeDevices: Bool) throws -> AudioInputReading {
    lock.lock()
    storedReadRequests.append(includeDevices)
    let gatedRead = readGates.isEmpty ? nil : readGates.removeFirst()
    let readError = readErrors.isEmpty ? nil : readErrors.removeFirst()
    let initialReading = storedReading
    lock.unlock()
    gatedRead?.gate.wait()
    if let readError { throw readError }
    let reading: AudioInputReading
    if gatedRead?.readAfterRelease == true {
      lock.lock()
      reading = storedReading
      lock.unlock()
    } else {
      reading = initialReading
    }
    guard !includeDevices else { return reading }
    return AudioInputReading(
      devices: nil,
      defaultDeviceID: reading.defaultDeviceID,
      deviceName: reading.deviceName,
      scalar: reading.scalar,
      canSetVolume: reading.canSetVolume,
      muteState: reading.muteState,
      canSetMute: reading.canSetMute,
      isDefaultInputInUse: reading.isDefaultInputInUse
    )
  }

  func readDefaultInputUsage() throws -> AudioInputUsageReading {
    lock.lock()
    defer { lock.unlock() }
    storedUsageReadCount += 1
    return storedUsageReading
  }

  func selectDefault(_ id: AudioDeviceID) throws {
    lock.lock()
    let reading = storedReading
    storedReading = AudioInputReading(
      devices: reading.devices,
      defaultDeviceID: id,
      deviceName: reading.devices?.first { $0.id == id }?.name,
      scalar: reading.scalar,
      canSetVolume: reading.canSetVolume,
      muteState: reading.muteState,
      canSetMute: reading.canSetMute,
      isDefaultInputInUse: nil
    )
    storedUsageReading = AudioInputUsageReading(defaultDeviceID: id, isDefaultInputInUse: nil)
    lock.unlock()
  }

  func setScalar(_ scalar: Double, on id: AudioDeviceID) throws {
    lock.lock()
    writtenScalars.append(scalar)
    storedScalarWriteTargets.append(id)
    activeWrites += 1
    maxConcurrentWrites = max(maxConcurrentWrites, activeWrites)
    let gate = scalarWriteGates.isEmpty ? nil : scalarWriteGates.removeFirst()
    let error = scalarWriteError
    lock.unlock()
    defer {
      lock.lock()
      activeWrites -= 1
      lock.unlock()
    }
    gate?.wait()
    if let error { throw error }
    lock.lock()
    if !ignoresScalarWrites, storedReading.defaultDeviceID == id {
      let reading = storedReading
      storedReading = AudioInputReading(
        devices: reading.devices,
        defaultDeviceID: reading.defaultDeviceID,
        deviceName: reading.deviceName,
        scalar: scalar,
        canSetVolume: reading.canSetVolume,
        muteState: reading.muteState,
        canSetMute: reading.canSetMute,
        isDefaultInputInUse: reading.isDefaultInputInUse
      )
    }
    lock.unlock()
  }

  func setMuted(_ muted: Bool, on id: AudioDeviceID) throws {
    lock.lock()
    storedMuteWriteTargets.append(id)
    let gate = muteWriteGates.isEmpty ? nil : muteWriteGates.removeFirst()
    lock.unlock()
    gate?.wait()
    lock.lock()
    if storedReading.defaultDeviceID == id {
      let reading = storedReading
      storedReading = AudioInputReading(
        devices: reading.devices,
        defaultDeviceID: reading.defaultDeviceID,
        deviceName: reading.deviceName,
        scalar: reading.scalar,
        canSetVolume: reading.canSetVolume,
        muteState: muted ? .muted : .unmuted,
        canSetMute: reading.canSetMute,
        isDefaultInputInUse: reading.isDefaultInputInUse
      )
    }
    lock.unlock()
  }

  func observe(_ notify: @escaping @Sendable (AudioInputEvent) -> Void) throws
    -> any AudioInputObservation
  {
    let observation = FakeAudioInputObservation(notify: notify)
    lock.lock()
    observations.append(observation)
    let gate = observationGates.isEmpty ? nil : observationGates.removeFirst()
    lock.unlock()
    observationCreated.signal()
    gate?.wait()
    return observation
  }
}
