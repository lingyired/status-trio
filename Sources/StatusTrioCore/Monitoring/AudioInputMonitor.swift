import AudioToolbox
import Foundation

@MainActor
protocol AudioInputMonitoring: AnyObject {
  var updates: AsyncStream<AudioInputStatus> { get }
  func setEnabled(_ enabled: Bool)
  func setVisible(_ visible: Bool)
  func recover()
  func select(_ id: AudioDeviceID)
  func setScalar(_ value: Double, requestID: UUID)
  func toggleMute()
  func stop()
}

extension AudioInputMonitoring {
  func setScalar(_ value: Double) {
    setScalar(value, requestID: UUID())
  }
}

private struct AudioInputVisibilitySnapshot: Sendable {
  let isVisible: Bool
  let generation: UInt64
}

/// The HAL callback snapshots whether the panel was visible when the event occurred. The lock
/// closes the gap between a callback enqueueing a MainActor task and a synchronous visibility
/// transition running before that task is serviced.
private final class AudioInputVisibilityGate: @unchecked Sendable {
  private let lock = NSLock()
  private var isVisible = false
  private var generation: UInt64 = 0

  var snapshot: AudioInputVisibilitySnapshot {
    lock.lock()
    defer { lock.unlock() }
    return AudioInputVisibilitySnapshot(isVisible: isVisible, generation: generation)
  }

  func isCurrentVisible(_ snapshot: AudioInputVisibilitySnapshot) -> Bool {
    guard snapshot.isVisible else { return false }
    lock.lock()
    defer { lock.unlock() }
    return isVisible && generation == snapshot.generation
  }

  func setVisible(_ visible: Bool) {
    lock.lock()
    if isVisible != visible {
      isVisible = visible
      generation &+= 1
    }
    lock.unlock()
  }
}

/// Synchronously invalidated by the MainActor when monitoring is disabled or stopped. Work that
/// has not started can then be dropped on the worker queue, and an in-flight HAL write can skip
/// its follow-up read once it returns.
private final class AudioInputSessionGate: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true

  var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return active
  }

  func invalidate() {
    lock.lock()
    active = false
    lock.unlock()
  }
}

private enum AudioInputMonitorCommand: Sendable {
  case select(AudioDeviceID)
  case scalar(Double)
  case mute(Bool)

  var error: AudioInputError {
    switch self {
    case .select: .switchFailed
    case .scalar: .volumeFailed
    case .mute: .muteFailed
    }
  }
}

@MainActor
final class AudioInputMonitor: AudioInputMonitoring {

  private struct ActiveCommand {
    let id: UUID
    let sessionGeneration: UInt64
    let readGeneration: UInt64
    let deviceID: AudioDeviceID
    let command: AudioInputMonitorCommand
    let scalarRequestID: UUID?
    var timedOut = false
  }

  private struct QueuedCommand {
    let command: AudioInputMonitorCommand
    let deviceID: AudioDeviceID
  }

  private struct PendingScalar {
    let value: Double
    let deviceID: AudioDeviceID
    let requestID: UUID
  }

  let updates: AsyncStream<AudioInputStatus>
  private let continuation: AsyncStream<AudioInputStatus>.Continuation
  private let worker: AudioInputWorker
  private let visibilityGate = AudioInputVisibilityGate()
  private var sessionGate: AudioInputSessionGate?
  private let commandTimeout: Duration
  private let usagePollInterval: Duration
  private let sleep: @Sendable (Duration) async throws -> Void
  private let usageSleep: @Sendable (Duration) async throws -> Void

  private var status = AudioInputStatus.empty
  private var isEnabled = false
  private var isVisible = false
  private var isStopped = false
  private var isDirty = true
  private var observationDegraded = false
  private var sessionGeneration: UInt64 = 0
  private var readGeneration: UInt64 = 0
  private var readInFlight = false
  private var readInFlightID: UUID?
  private var refreshPending = false
  private var activeCommand: ActiveCommand?
  private var queuedCommands: [QueuedCommand] = []
  private var pendingScalar: PendingScalar?
  private var latestScalarRequestID: UUID?
  private var scalarConfirmationID: UUID?
  private var scalarDebounceToken: UUID?
  private var scalarDebounceReady = false
  private var scalarDebounceTask: Task<Void, Never>?
  private var commandTimeoutTask: Task<Void, Never>?
  private var errorExpiryToken: UUID?
  private var errorExpiryTask: Task<Void, Never>?
  private var usagePollTask: Task<Void, Never>?
  private var usageReadID: UUID?
  private var usageReadInFlight = false

  init(
    hardware: any AudioInputHardware = CoreAudioInputHardware(),
    commandTimeout: Duration = .seconds(2),
    usagePollInterval: Duration = .seconds(1),
    usageSleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
      try await Task.sleep(for: duration)
    },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
      try await Task.sleep(for: duration)
    }
  ) {
    let (updates, continuation) = AsyncStream.makeStream(
      of: AudioInputStatus.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    self.updates = updates
    self.continuation = continuation
    self.worker = AudioInputWorker(hardware: hardware)
    self.commandTimeout = commandTimeout
    self.usagePollInterval = usagePollInterval
    self.usageSleep = usageSleep
    self.sleep = sleep
    continuation.yield(.empty)
  }

  func setEnabled(_ enabled: Bool) {
    guard !isStopped, enabled != isEnabled else { return }
    if !enabled {
      sessionGate?.invalidate()
      sessionGate = nil
      stopUsagePolling()
    }
    sessionGeneration &+= 1
    readGeneration &+= 1
    isEnabled = enabled
    isDirty = true
    refreshPending = false
    readInFlight = false
    readInFlightID = nil
    activeCommand = nil
    queuedCommands.removeAll()
    clearPendingScalar()
    finishLatestScalarRequest()
    commandTimeoutTask?.cancel()
    commandTimeoutTask = nil
    clearError()

    if enabled {
      let generation = sessionGeneration
      let sessionGate = AudioInputSessionGate()
      self.sessionGate = sessionGate
      let visibilityGate = visibilityGate
      worker.startObservation(
        sessionGate: sessionGate,
        notify: { [weak self] event in
          let visibilityAtEvent = visibilityGate.snapshot
          Task { @MainActor [weak self] in
            self?.receive(
              event,
              sessionGeneration: generation,
              visibilityAtEvent: visibilityAtEvent
            )
          }
        },
        completion: { [weak self] error in
          Task { @MainActor [weak self] in
            self?.observationStarted(error, sessionGeneration: generation)
          }
        }
      )
      if isVisible {
        requestRefresh()
        startUsagePolling()
      }
    } else {
      worker.stopObservation()
      status.isRefreshing = false
      status.isBusy = false
      status.isDefaultInputInUse = nil
      publish()
    }
  }

  func setVisible(_ visible: Bool) {
    guard !isStopped, visible != isVisible else { return }
    visibilityGate.setVisible(visible)
    isVisible = visible
    if visible {
      if isEnabled {
        requestRefresh()
        startUsagePolling()
      }
    } else {
      stopUsagePolling()
      readGeneration &+= 1
      isDirty = true
      refreshPending = false
      // A queued full read can no longer satisfy the visible panel. Drop its logical lock now;
      // the serial worker still prevents any new HAL call from overlapping an already-running one.
      readInFlight = false
      readInFlightID = nil
      status.isRefreshing = false
      status.isDefaultInputInUse = nil
      publish()
      startNextWorkIfPossible()
    }
  }

  func recover() {
    guard !isStopped, isEnabled else { return }
    if isVisible {
      requestRefresh()
    } else {
      isDirty = true
    }
  }

  func select(_ id: AudioDeviceID) {
    beginUserAction()
    guard canAcceptAction else { return }
    guard status.devices.contains(where: { $0.id == id }) else {
      showError(.switchFailed)
      return
    }
    cancelPendingScalar()
    enqueueOrStart(QueuedCommand(command: .select(id), deviceID: id))
  }

  func setScalar(_ value: Double, requestID: UUID = UUID()) {
    beginUserAction()
    guard isEnabled, !isStopped else { return }
    guard value.isFinite, status.canSetVolume, let deviceID = status.defaultDeviceID else {
      showError(.volumeFailed)
      return
    }
    latestScalarRequestID = requestID
    scalarConfirmationID = nil
    pendingScalar = PendingScalar(
      value: min(max(value, 0), 1), deviceID: deviceID, requestID: requestID
    )
    scalarDebounceReady = false
    let token = UUID()
    scalarDebounceToken = token
    scalarDebounceTask?.cancel()
    scalarDebounceTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.sleep(.milliseconds(80))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self.scalarDebounceElapsed(token: token)
    }
  }

  func toggleMute() {
    beginUserAction()
    guard canAcceptAction else { return }
    guard status.canSetMute, let deviceID = status.defaultDeviceID,
      let muteState = status.muteState
    else {
      showError(.muteFailed)
      return
    }
    let target = muteState != .muted
    cancelPendingScalar()
    enqueueOrStart(QueuedCommand(command: .mute(target), deviceID: deviceID))
  }

  func stop() {
    guard !isStopped else { return }
    sessionGate?.invalidate()
    sessionGate = nil
    stopUsagePolling()
    isStopped = true
    isEnabled = false
    isVisible = false
    sessionGeneration &+= 1
    readGeneration &+= 1
    refreshPending = false
    queuedCommands.removeAll()
    activeCommand = nil
    readInFlight = false
    readInFlightID = nil
    clearPendingScalar()
    commandTimeoutTask?.cancel()
    commandTimeoutTask = nil
    clearError()
    worker.stopObservation()
    continuation.finish()
  }

  private var canAcceptAction: Bool {
    isEnabled && !isStopped && activeCommand?.timedOut != true
  }

  private func beginUserAction() {
    clearError()
  }

  private func receive(
    _ event: AudioInputEvent,
    sessionGeneration expected: UInt64,
    visibilityAtEvent: AudioInputVisibilitySnapshot
  ) {
    guard isEnabled, !isStopped, expected == sessionGeneration else { return }
    switch event {
    case .devicesChanged, .defaultChanged, .controlsChanged:
      isDirty = true
      let currentVisibility = visibilityGate.snapshot
      guard visibilityAtEvent.isVisible,
        visibilityAtEvent.generation == currentVisibility.generation,
        isVisible
      else { return }
      requestRefresh()
    }
  }

  private func observationStarted(
    _ error: AudioInputHardwareError?,
    sessionGeneration expected: UInt64
  ) {
    guard isEnabled, !isStopped, expected == sessionGeneration, error != nil else { return }
    showError(.refreshFailed)
  }

  private func requestRefresh() {
    guard isEnabled, isVisible, !isStopped else {
      isDirty = true
      return
    }
    readGeneration &+= 1
    isDirty = true
    refreshPending = true
    status.isRefreshing = true
    publish()
    startPendingRefreshIfPossible()
  }

  private func startPendingRefreshIfPossible() {
    guard refreshPending, isEnabled, isVisible, !isStopped,
      !readInFlight, activeCommand == nil, queuedCommands.isEmpty,
      let sessionGate
    else { return }

    refreshPending = false
    readInFlight = true
    let readID = UUID()
    readInFlightID = readID
    let expectedSession = sessionGeneration
    let expectedRead = readGeneration
    let visibilitySnapshot = visibilityGate.snapshot
    worker.readAll(
      sessionGate: sessionGate,
      visibilityGate: visibilityGate,
      visibilitySnapshot: visibilitySnapshot
    ) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.refreshCompleted(
          result,
          readID: readID,
          sessionGeneration: expectedSession,
          readGeneration: expectedRead
        )
      }
    }
  }

  private func refreshCompleted(
    _ result: Result<AudioInputRefreshResult, AudioInputHardwareError>,
    readID: UUID,
    sessionGeneration expectedSession: UInt64,
    readGeneration expectedRead: UInt64
  ) {
    guard expectedSession == sessionGeneration, isEnabled, !isStopped,
      readInFlightID == readID
    else { return }
    readInFlight = false
    readInFlightID = nil

    guard expectedRead == readGeneration, isVisible else {
      if isVisible { refreshPending = true }
      startPendingRefreshIfPossible()
      return
    }

    switch result {
    case let .success(refresh):
      apply(refresh.reading)
      if let scalarConfirmationID {
        finishScalarRequest(scalarConfirmationID)
      }
      isDirty = false
      observationDegraded = refresh.observationError != nil
      if observationDegraded {
        showError(.refreshFailed)
      } else {
        clearError()
      }
    case .failure:
      invalidateDefaultControlReadback()
      showError(.refreshFailed)
    }
    status.isRefreshing = false
    publish()
    startNextWorkIfPossible()
  }

  private func invalidateDefaultControlReadback() {
    status.defaultDeviceID = nil
    status.deviceName = nil
    status.scalar = nil
    status.canSetVolume = false
    status.muteState = nil
    status.canSetMute = false
    status.isDefaultInputInUse = nil
    status.isBusy = false

    queuedCommands.removeAll()
    clearPendingScalar()
    finishLatestScalarRequest()
    refreshPending = false
  }

  private func enqueueOrStart(_ queued: QueuedCommand) {
    if activeCommand != nil || readInFlight || !queuedCommands.isEmpty {
      queuedCommands.append(queued)
      status.isBusy = true
      publish()
      return
    }
    start(queued.command, deviceID: queued.deviceID)
  }

  private func scalarDebounceElapsed(token: UUID) {
    guard scalarDebounceToken == token, pendingScalar != nil else { return }
    scalarDebounceReady = true
    scalarDebounceTask = nil
    guard activeCommand?.timedOut != true else {
      clearPendingScalar()
      finishLatestScalarRequest()
      publish()
      return
    }
    if activeCommand == nil, readInFlight == false, queuedCommands.isEmpty {
      startPendingScalar()
    }
  }

  private func startPendingScalar() {
    guard scalarDebounceReady, let scalar = pendingScalar else { return }
    clearPendingScalar()
    guard status.defaultDeviceID == scalar.deviceID, status.canSetVolume else {
      finishScalarRequest(scalar.requestID)
      showError(.volumeFailed)
      startNextWorkIfPossible()
      return
    }
    start(.scalar(scalar.value), deviceID: scalar.deviceID, scalarRequestID: scalar.requestID)
  }

  private func startNextWorkIfPossible() {
    guard activeCommand == nil, !readInFlight else { return }
    if !queuedCommands.isEmpty {
      let next = queuedCommands.removeFirst()
      start(next.command, deviceID: next.deviceID)
      return
    }
    if scalarDebounceReady, pendingScalar != nil {
      startPendingScalar()
      return
    }
    startPendingRefreshIfPossible()
  }

  private func start(
    _ command: AudioInputMonitorCommand,
    deviceID: AudioDeviceID,
    scalarRequestID: UUID? = nil
  ) {
    guard isEnabled, !isStopped, activeCommand == nil else { return }
    if case .select = command {
      guard status.devices.contains(where: { $0.id == deviceID }) else {
        showError(.switchFailed)
        return
      }
    } else if status.defaultDeviceID != deviceID {
      showError(command.error)
      return
    }

    readGeneration &+= 1
    refreshPending = refreshPending || readInFlight
    let active = ActiveCommand(
      id: UUID(),
      sessionGeneration: sessionGeneration,
      readGeneration: readGeneration,
      deviceID: deviceID,
      command: command,
      scalarRequestID: scalarRequestID
    )
    guard let sessionGate, sessionGate.isActive else { return }
    activeCommand = active
    status.isBusy = true
    status.error = nil
    publish()
    scheduleCommandTimeout(for: active.id)
    worker.execute(command, on: deviceID, sessionGate: sessionGate) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.commandCompleted(result, commandID: active.id)
      }
    }
  }

  private func scheduleCommandTimeout(for commandID: UUID) {
    commandTimeoutTask?.cancel()
    commandTimeoutTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.sleep(self.commandTimeout)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self.commandTimedOut(commandID)
    }
  }

  private func commandTimedOut(_ commandID: UUID) {
    guard var active = activeCommand, active.id == commandID, !active.timedOut else { return }
    active.timedOut = true
    activeCommand = active
    clearPendingScalar()
    finishLatestScalarRequest()
    queuedCommands.removeAll()
    showError(.timedOut)
  }

  private func commandCompleted(_ result: AudioInputCommandResult, commandID: UUID) {
    guard let active = activeCommand, active.id == commandID else { return }
    commandTimeoutTask?.cancel()
    commandTimeoutTask = nil
    activeCommand = nil

    guard isEnabled, !isStopped, active.sessionGeneration == sessionGeneration else { return }

    if result.observationError != nil {
      observationDegraded = true
    } else if result.reading != nil {
      observationDegraded = false
    }

    let isCurrent = active.readGeneration == readGeneration
      && status.defaultDeviceID == active.deviceID
    if active.timedOut {
      if isCurrent, let reading = result.reading,
        reading.defaultDeviceID == active.deviceID
      {
        apply(reading)
        isDirty = false
      } else if isVisible {
        refreshPending = true
      }
      status.isBusy = false
      status.isRefreshing = refreshPending
      publish()
      startNextWorkIfPossible()
      return
    }

    if isCurrent, let reading = result.reading, reading.defaultDeviceID == active.deviceID {
      apply(reading)
      isDirty = false
    } else if case .select = active.command,
      active.readGeneration == readGeneration,
      let reading = result.reading
    {
      apply(reading)
      isDirty = false
    } else if isVisible {
      refreshPending = true
    }

    let commandError = commandFailure(
      active.command,
      expectedDeviceID: active.deviceID,
      result: result
    )
    if let requestID = active.scalarRequestID, requestID == latestScalarRequestID {
      if commandError != nil || (isCurrent && result.reading?.defaultDeviceID == active.deviceID) {
        finishScalarRequest(requestID)
      } else {
        // A HAL notification can invalidate the command readback. Only the
        // replacement refresh can then confirm this request, not busy -> idle.
        scalarConfirmationID = requestID
      }
    }
    let failure = commandError ?? (observationDegraded ? .refreshFailed : nil)
    status.error = failure
    status.isBusy = false
    status.isRefreshing = refreshPending || readInFlight
    publish()
    if let commandError {
      showError(commandError)
    } else if observationDegraded {
      showError(.refreshFailed)
    } else {
      clearError()
    }
    startNextWorkIfPossible()
  }

  private func commandFailure(
    _ command: AudioInputMonitorCommand,
    expectedDeviceID: AudioDeviceID,
    result: AudioInputCommandResult
  ) -> AudioInputError? {
    guard result.operationError == nil, result.readError == nil,
      let reading = result.reading
    else { return command.error }

    switch command {
    case let .select(id):
      return reading.defaultDeviceID == id ? nil : .switchFailed
    case let .scalar(target):
      guard reading.defaultDeviceID == expectedDeviceID,
        reading.canSetVolume,
        let actual = reading.scalar,
        abs(actual - target) <= 0.01
      else { return .volumeFailed }
      return nil
    case let .mute(target):
      let expected: AudioInputMuteState = target ? .muted : .unmuted
      guard reading.defaultDeviceID == expectedDeviceID,
        reading.canSetMute,
        reading.muteState == expected
      else { return .muteFailed }
      return nil
    }
  }

  private func apply(_ reading: AudioInputReading) {
    if let devices = reading.devices {
      status.devices = devices
    }
    status.defaultDeviceID = reading.defaultDeviceID
    status.deviceName = reading.deviceName
    status.scalar = reading.scalar
    status.canSetVolume = reading.canSetVolume
    status.muteState = reading.muteState
    status.canSetMute = reading.canSetMute
    status.isDefaultInputInUse = reading.isDefaultInputInUse
  }

  private func startUsagePolling() {
    guard usagePollTask == nil, isEnabled, isVisible, !isStopped else { return }
    let expectedSession = sessionGeneration
    usagePollTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          try await self.usageSleep(self.usagePollInterval)
        } catch {
          break
        }
        guard !Task.isCancelled else { break }
        self.refreshDefaultInputUsage(sessionGeneration: expectedSession)
      }
      if self.sessionGeneration == expectedSession {
        self.usagePollTask = nil
      }
    }
  }

  private func stopUsagePolling() {
    usagePollTask?.cancel()
    usagePollTask = nil
    usageReadID = nil
    usageReadInFlight = false
  }

  private func refreshDefaultInputUsage(sessionGeneration expectedSession: UInt64) {
    guard isEnabled, isVisible, !isStopped,
      sessionGeneration == expectedSession,
      !usageReadInFlight,
      let sessionGate
    else { return }

    let readID = UUID()
    usageReadID = readID
    usageReadInFlight = true
    let visibilitySnapshot = visibilityGate.snapshot
    worker.readDefaultInputUsage(
      sessionGate: sessionGate,
      visibilityGate: visibilityGate,
      visibilitySnapshot: visibilitySnapshot
    ) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.defaultInputUsageCompleted(
          result,
          readID: readID,
          sessionGeneration: expectedSession
        )
      }
    }
  }

  private func defaultInputUsageCompleted(
    _ result: Result<AudioInputUsageReading, AudioInputHardwareError>,
    readID: UUID,
    sessionGeneration expectedSession: UInt64
  ) {
    guard usageReadID == readID, isEnabled, isVisible, !isStopped,
      expectedSession == sessionGeneration
    else { return }
    usageReadID = nil
    usageReadInFlight = false

    switch result {
    case let .success(reading):
      guard reading.defaultDeviceID == status.defaultDeviceID else {
        guard status.isDefaultInputInUse != nil else { return }
        status.isDefaultInputInUse = nil
        publish()
        return
      }
      guard reading.isDefaultInputInUse != status.isDefaultInputInUse else { return }
      status.isDefaultInputInUse = reading.isDefaultInputInUse
      publish()
    case .failure:
      guard status.isDefaultInputInUse != nil else { return }
      status.isDefaultInputInUse = nil
      publish()
    }
  }

  private func showError(_ error: AudioInputError) {
    status.error = error
    publish()
    errorExpiryTask?.cancel()
    let token = UUID()
    errorExpiryToken = token
    errorExpiryTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.sleep(.seconds(4))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self.expireError(token: token)
    }
  }

  private func expireError(token: UUID) {
    guard errorExpiryToken == token else { return }
    errorExpiryToken = nil
    errorExpiryTask = nil
    guard status.error != nil else { return }
    if observationDegraded {
      if status.error != .refreshFailed {
        status.error = .refreshFailed
        publish()
      }
      return
    }
    status.error = nil
    publish()
  }

  private func clearError() {
    errorExpiryToken = nil
    errorExpiryTask?.cancel()
    errorExpiryTask = nil
    guard status.error != nil else { return }
    status.error = nil
    publish()
  }

  private func clearPendingScalar() {
    pendingScalar = nil
    scalarDebounceReady = false
    scalarDebounceToken = nil
    scalarDebounceTask?.cancel()
    scalarDebounceTask = nil
  }

  private func cancelPendingScalar() {
    let requestID = pendingScalar?.requestID
    clearPendingScalar()
    if let requestID {
      finishScalarRequest(requestID)
    }
  }

  private func finishScalarRequest(_ requestID: UUID) {
    guard requestID == latestScalarRequestID else { return }
    status.completedScalarRequestID = requestID
    latestScalarRequestID = nil
    scalarConfirmationID = nil
  }

  private func finishLatestScalarRequest() {
    if let requestID = latestScalarRequestID {
      finishScalarRequest(requestID)
    }
  }

  private func publish() {
    guard !isStopped else { return }
    if let activeCommand, case .scalar = activeCommand.command {
      status.isAdjustingScalar = !activeCommand.timedOut && queuedCommands.isEmpty
    } else {
      status.isAdjustingScalar = false
    }
    continuation.yield(status)
  }
}

private struct AudioInputRefreshResult: Sendable {
  let reading: AudioInputReading
  let observationError: AudioInputHardwareError?
}

private struct AudioInputCommandResult: Sendable {
  let operationError: AudioInputHardwareError?
  let reading: AudioInputReading?
  let readError: AudioInputHardwareError?
  let observationError: AudioInputHardwareError?
}

/// All synchronous HAL reads, writes, listener changes, and listener teardown are serialized here.
/// The observation reference is only accessed on `queue`; this is the `@unchecked Sendable` invariant.
private final class AudioInputWorker: @unchecked Sendable {
  private let hardware: any AudioInputHardware
  private let queue = DispatchQueue(label: "com.status-trio.audio-input-io", qos: .utility)
  private var observation: (any AudioInputObservation)?

  init(hardware: any AudioInputHardware) {
    self.hardware = hardware
  }

  func startObservation(
    sessionGate: AudioInputSessionGate,
    notify: @escaping @Sendable (AudioInputEvent) -> Void,
    completion: @escaping @Sendable (AudioInputHardwareError?) -> Void
  ) {
    queue.async {
      guard sessionGate.isActive else { return }
      guard self.observation == nil else {
        completion(nil)
        return
      }
      do {
        self.observation = try self.hardware.observe(notify)
        completion(nil)
      } catch {
        completion(Self.hardwareError(error))
      }
    }
  }

  func readAll(
    sessionGate: AudioInputSessionGate,
    visibilityGate: AudioInputVisibilityGate,
    visibilitySnapshot: AudioInputVisibilitySnapshot,
    completion: @escaping @Sendable (Result<AudioInputRefreshResult, AudioInputHardwareError>) -> Void
  ) {
    queue.async {
      guard sessionGate.isActive, visibilityGate.isCurrentVisible(visibilitySnapshot) else { return }
      let reading: AudioInputReading
      do {
        reading = try self.hardware.read(includeDevices: true)
        guard sessionGate.isActive,
          visibilityGate.isCurrentVisible(visibilitySnapshot)
        else { return }
      } catch {
        guard sessionGate.isActive,
          visibilityGate.isCurrentVisible(visibilitySnapshot)
        else { return }
        completion(.failure(Self.hardwareError(error)))
        return
      }

      var observationError: AudioInputHardwareError?
      do {
        try self.observation?.setCurrentDevice(reading.defaultDeviceID)
      } catch {
        observationError = Self.hardwareError(error)
      }
      guard sessionGate.isActive,
        visibilityGate.isCurrentVisible(visibilitySnapshot)
      else { return }
      completion(.success(AudioInputRefreshResult(
        reading: reading,
        observationError: observationError
      )))
    }
  }

  func readDefaultInputUsage(
    sessionGate: AudioInputSessionGate,
    visibilityGate: AudioInputVisibilityGate,
    visibilitySnapshot: AudioInputVisibilitySnapshot,
    completion: @escaping @Sendable (Result<AudioInputUsageReading, AudioInputHardwareError>) -> Void
  ) {
    queue.async {
      guard sessionGate.isActive, visibilityGate.isCurrentVisible(visibilitySnapshot) else { return }
      do {
        let reading = try self.hardware.readDefaultInputUsage()
        guard sessionGate.isActive,
          visibilityGate.isCurrentVisible(visibilitySnapshot)
        else { return }
        completion(.success(reading))
      } catch {
        guard sessionGate.isActive,
          visibilityGate.isCurrentVisible(visibilitySnapshot)
        else { return }
        completion(.failure(Self.hardwareError(error)))
      }
    }
  }

  func execute(
    _ command: AudioInputMonitorCommand,
    on deviceID: AudioDeviceID,
    sessionGate: AudioInputSessionGate,
    completion: @escaping @Sendable (AudioInputCommandResult) -> Void
  ) {
    queue.async {
      guard sessionGate.isActive else { return }
      var operationError: AudioInputHardwareError?
      do {
        switch command {
        case let .select(id):
          try self.hardware.selectDefault(id)
        case let .scalar(value):
          try self.hardware.setScalar(value, on: deviceID)
        case let .mute(value):
          try self.hardware.setMuted(value, on: deviceID)
        }
      } catch {
        operationError = Self.hardwareError(error)
      }

      // HAL calls are synchronous and cannot be cancelled. If this session ended while the
      // write was blocked, do not touch the device again for a stale readback.
      guard sessionGate.isActive else { return }
      var reading: AudioInputReading?
      var readError: AudioInputHardwareError?
      var observationError: AudioInputHardwareError?
      do {
        reading = try self.hardware.read(includeDevices: false)
        guard sessionGate.isActive else { return }
      } catch {
        guard sessionGate.isActive else { return }
        readError = Self.hardwareError(error)
      }
      if readError == nil, let reading {
        do {
          try self.observation?.setCurrentDevice(reading.defaultDeviceID)
        } catch {
          observationError = Self.hardwareError(error)
        }
      }
      guard sessionGate.isActive else { return }
      completion(AudioInputCommandResult(
        operationError: operationError,
        reading: reading,
        readError: readError,
        observationError: observationError
      ))
    }
  }

  func stopObservation() {
    queue.async {
      let observation = self.observation
      self.observation = nil
      observation?.stop()
    }
  }

  private static func hardwareError(_ error: Error) -> AudioInputHardwareError {
    error as? AudioInputHardwareError ?? .unavailable
  }
}
