import CoreAudio
import Foundation

@MainActor
final class BetterDisplayVolumeCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct PendingVolume {
        let commandID: UInt64
        let scalar: Double
    }

    private struct PendingMute {
        let commandID: UInt64
        let isMuted: Bool
    }

    private struct ReadConfirmation {
        let commandID: UInt64
        let scalar: Double?
        let isMuted: Bool?

        func merging(_ newer: ReadConfirmation) -> ReadConfirmation {
            ReadConfirmation(
                commandID: max(commandID, newer.commandID),
                scalar: newer.scalar ?? scalar,
                isMuted: newer.isMuted ?? isMuted
            )
        }
    }

    private enum CatalogTargetState: Equatable {
        case unknown
        case valid
        case invalid
    }

    let catalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    private let catalogContinuation: AsyncStream<BetterDisplayCatalogUpdate>.Continuation
    private let client: any BetterDisplayRequesting
    private let sleep: Sleep
    private let readFramebuffers: @Sendable () async -> [BetterDisplayFramebufferIdentity]
    private let onUpdate: @MainActor (BetterDisplayVolumeUpdate) -> Void
    private let debounce: Duration

    private(set) var generation: UInt64 = 0
    private var inputGeneration: UInt64 = 0
    private var outputID: AudioDeviceID?
    private var uid: String?
    private var displayUUID: String?
    private var catalog: [BetterDisplayDevice]?
    private var framebuffers: [BetterDisplayFramebufferIdentity] = []
    private var latestRange: BetterDisplayVolumeRange?
    private var latestMuteState: VolumeMuteState = .unknown
    private var desiredMuteState: VolumeMuteState?
    private var desiredScalar: Double?
    private var canSetVolume = false
    private var canMute = false
    private var commandID: UInt64?
    private var nextCommandID: UInt64 = 0
    private var pendingVolume: PendingVolume?
    private var pendingMute: PendingMute?
    private var readConfirmation: ReadConfirmation?
    private var discoveryRequested = false
    private var readRequested = false
    private var requestInFlight = false
    private var discoveryGeneration: UInt64?
    private var nextRequestToken: UInt64 = 0
    private var activeRequestToken: UInt64?
    private var volumeRateTask: Task<Void, Never>?
    private var volumeSendWindowOpen = true
    private var pollTask: Task<Void, Never>?
    private var detailsVisible = false
    private var displayAsleep = false
    private var isStarted = false
    private var isStopped = false
    private var isClientStarted = false
    private var isAppUnavailable = false

    init(
        client: any BetterDisplayRequesting,
        debounce: Duration = .milliseconds(150),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        readFramebuffers: @escaping @Sendable () async -> [BetterDisplayFramebufferIdentity] = {
            await BetterDisplayFramebufferReader.readInBackground()
        },
        onUpdate: @escaping @MainActor (BetterDisplayVolumeUpdate) -> Void
    ) {
        self.client = client
        self.debounce = debounce
        self.sleep = sleep
        self.readFramebuffers = readFramebuffers
        self.onUpdate = onUpdate
        (catalogUpdates, catalogContinuation) = MonitorStream.make(
            of: BetterDisplayCatalogUpdate.self
        )
    }

    func start() {
        guard !isStarted, !isStopped else { return }
        isStarted = true
    }

    func select(
        outputID: AudioDeviceID,
        uid: String,
        displayUUID: String?
    ) {
        guard isStarted, !isStopped, !uid.isEmpty else { return }
        let displayUUID = displayUUID?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        generation &+= 1
        inputGeneration &+= 1
        self.outputID = outputID
        self.uid = uid
        self.displayUUID = displayUUID?.isEmpty == false ? displayUUID : nil
        latestRange = nil
        latestMuteState = .unknown
        desiredMuteState = nil
        desiredScalar = nil
        canSetVolume = false
        canMute = false
        commandID = nil
        pendingVolume = nil
        pendingMute = nil
        readConfirmation = nil
        readRequested = false
        cancelScheduledWork()
        guard self.displayUUID != nil else {
            if catalog != nil {
                emit(availability: .deviceUnassociated)
            } else {
                requestDiscovery(invalidateSelection: false)
            }
            return
        }
        if isAppUnavailable {
            emit(
                availability: .appAbsent,
                scalar: nil,
                muteState: .unknown,
                canSetVolume: false,
                canMute: false
            )
            emitCatalog(availability: .appAbsent)
            return
        }
        emit(availability: .discovering)

        if catalog == nil {
            requestDiscovery(invalidateSelection: false)
        } else {
            validateSelectionAgainstCatalog()
        }
    }

    func clearSelection() {
        guard !isStopped else { return }
        generation &+= 1
        inputGeneration &+= 1
        outputID = nil
        uid = nil
        displayUUID = nil
        latestRange = nil
        latestMuteState = .unknown
        desiredMuteState = nil
        desiredScalar = nil
        canSetVolume = false
        canMute = false
        commandID = nil
        pendingVolume = nil
        pendingMute = nil
        readConfirmation = nil
        readRequested = false
        discoveryRequested = false
        isAppUnavailable = false
        cancelScheduledWork()
        stopClient()
        emitCatalog(devices: [], availability: .idle)
    }

    func refreshDevices() {
        guard isStarted, !isStopped else { return }
        isAppUnavailable = false
        requestDiscovery(invalidateSelection: true)
    }

    func refresh() {
        guard isStarted, !isStopped, !isAppUnavailable else {
            return
        }
        guard displayUUID != nil, catalog != nil else {
            requestDiscovery(invalidateSelection: false)
            return
        }
        requestRead(confirmation: nil)
    }

    func setVolume(_ scalar: Double) {
        guard isStarted, !isStopped, !displayAsleep, !isAppUnavailable,
              displayUUID != nil,
              latestRange != nil, canSetVolume, scalar.isFinite
        else {
            return
        }
        let target = min(1, max(0, scalar))
        desiredScalar = target
        inputGeneration &+= 1
        nextCommandID &+= 1
        let pending = PendingVolume(commandID: nextCommandID, scalar: target)
        pendingVolume = pending
        pollTask?.cancel()
        pollTask = nil

        emit(
            availability: .syncing,
            scalar: target,
            muteState: desiredMuteState ?? latestMuteState,
            canSetVolume: true,
            canMute: canMute,
            commandID: pending.commandID
        )

        scheduleVolumeSendWindowIfNeeded()
    }

    func flushPendingVolume() {
        guard !isAppUnavailable else { return }
        if volumeSendWindowOpen, !requestInFlight {
            volumeRateTask?.cancel()
            volumeRateTask = nil
        }
        drain()
        scheduleVolumeSendWindowIfNeeded()
    }

    func toggleMute() {
        guard isStarted, !isStopped, !displayAsleep, !isAppUnavailable,
              displayUUID != nil, latestRange != nil, canMute
        else {
            return
        }
        let currentTarget = desiredMuteState ?? latestMuteState
        guard currentTarget != .unknown else { return }
        nextCommandID &+= 1
        inputGeneration &+= 1
        let isMuted = currentTarget == .unmuted
        desiredMuteState = isMuted ? .muted : .unmuted
        let pending = PendingMute(commandID: nextCommandID, isMuted: isMuted)
        pendingMute = pending
        pollTask?.cancel()
        pollTask = nil
        emit(
            availability: .syncing,
            scalar: desiredScalar ?? latestRange?.normalizedScalar,
            muteState: isMuted ? .muted : .unmuted,
            canSetVolume: canSetVolume,
            canMute: true,
            commandID: pending.commandID
        )
        drain()
    }

    func setDetailsVisible(_ visible: Bool) {
        detailsVisible = visible
        if isStopped
            || displayAsleep
            || isAppUnavailable
            || displayUUID == nil
            || latestRange == nil {
            pollTask?.cancel()
            pollTask = nil
        } else {
            schedulePoll()
        }
    }

    func setDisplayAsleep(_ asleep: Bool) {
        guard !isStopped, displayAsleep != asleep else { return }
        displayAsleep = asleep
        generation &+= 1
        inputGeneration &+= 1
        catalog = nil
        latestRange = nil
        latestMuteState = .unknown
        desiredMuteState = nil
        desiredScalar = nil
        canSetVolume = false
        canMute = false
        pendingVolume = nil
        pendingMute = nil
        readConfirmation = nil
        readRequested = false
        discoveryRequested = false
        cancelScheduledWork()

        if asleep {
            stopClient()
            emit(
                availability: .idle,
                scalar: nil,
                muteState: .unknown,
                canSetVolume: false,
                canMute: false
            )
            emitCatalog(devices: [], availability: .idle)
        } else if outputID != nil {
            requestDiscovery(invalidateSelection: false)
        }
    }

    func topologyChanged() {
        guard isStarted, !isStopped else { return }
        generation &+= 1
        inputGeneration &+= 1
        catalog = nil
        latestRange = nil
        latestMuteState = .unknown
        desiredMuteState = nil
        desiredScalar = nil
        canSetVolume = false
        canMute = false
        pendingVolume = nil
        pendingMute = nil
        readConfirmation = nil
        readRequested = false
        cancelScheduledWork()
        if outputID != nil {
            requestDiscovery(invalidateSelection: false)
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        generation &+= 1
        inputGeneration &+= 1
        cancelScheduledWork()
        pendingVolume = nil
        pendingMute = nil
        readConfirmation = nil
        activeRequestToken = nil
        requestInFlight = false
        discoveryRequested = false
        readRequested = false
        if isClientStarted {
            stopClient()
        }
        catalogContinuation.finish()
    }

    private func requestDiscovery(invalidateSelection: Bool) {
        guard isStarted, !isStopped, !displayAsleep, !isAppUnavailable else {
            return
        }
        guard discoveryGeneration != generation else { return }
        if invalidateSelection {
            catalog = nil
        }
        if invalidateSelection, displayUUID != nil {
            generation &+= 1
            inputGeneration &+= 1
            latestRange = nil
            latestMuteState = .unknown
            desiredMuteState = nil
            desiredScalar = nil
            canSetVolume = false
            canMute = false
            pendingVolume = nil
            pendingMute = nil
            readConfirmation = nil
            readRequested = false
            cancelScheduledWork()
        }
        isAppUnavailable = false
        discoveryRequested = true
        emit(
            availability: .discovering,
            scalar: nil,
            muteState: .unknown,
            canSetVolume: false,
            canMute: false
        )
        emitCatalog(availability: .discovering)
        drain()
    }

    private func requestRead(confirmation: ReadConfirmation?) {
        guard isStarted, !isStopped, !displayAsleep, !isAppUnavailable,
              displayUUID != nil
        else {
            return
        }
        readRequested = true
        if let confirmation {
            readConfirmation = readConfirmation.map {
                $0.merging(confirmation)
            } ?? confirmation
        }
        drain()
    }

    private func drain() {
        guard isStarted, !isStopped, !displayAsleep, !isAppUnavailable,
              !requestInFlight
        else {
            return
        }
        if discoveryRequested {
            discoveryRequested = false
            performDiscovery()
            return
        }
        if pendingMute != nil {
            performMuteMutation()
            return
        }
        if pendingVolume != nil {
            if volumeSendWindowOpen {
                performVolumeMutation()
            }
            return
        }
        if readRequested, displayUUID != nil {
            readRequested = false
            performRead(confirmation: readConfirmation)
        }
    }

    private func performDiscovery() {
        guard let outputID,
              let uid,
              let displayUUID
        else {
            performCatalogDiscovery()
            return
        }
        ensureClientStarted()
        let requestToken = beginRequest()
        let selectedGeneration = generation
        discoveryGeneration = selectedGeneration
        let parameters: [String: String?] = [
            "identifiers": nil
        ]
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.canBeginRequest(requestToken, generation: selectedGeneration) else {
                self.finishRequest(requestToken)
                return
            }
            do {
                let payload = try await self.client.request(
                    commands: ["get"],
                    parameters: parameters
                )
                guard !self.isStopped, !self.displayAsleep else {
                    self.finishRequest(requestToken)
                    return
                }
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: self.inputGeneration
                ) else {
                    self.finishRequest(requestToken)
                    return
                }
                guard let payload else {
                    throw BetterDisplayIntegrationError.invalidResponse
                }
                let devices = try BetterDisplayVolumeParser.parseDevices(payload)
                let framebuffers = await self.readFramebuffers()
                guard self.accepts(
                    outputID: outputID, uid: uid, displayUUID: displayUUID,
                    generation: selectedGeneration, inputGeneration: self.inputGeneration
                ) else {
                    self.finishRequest(requestToken)
                    return
                }
                self.framebuffers = framebuffers
                self.catalog = devices
                self.isAppUnavailable = false
                if devices.contains(where: { $0.uuid == displayUUID }) {
                    self.emitCatalog(devices: devices, availability: .discovering)
                    self.validateSelectionAgainstCatalog()
                } else {
                    self.invalidateCatalogTarget(catalog: devices)
                }
            } catch {
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: self.inputGeneration
                ) else {
                    self.finishRequest(requestToken)
                    return
                }
                self.handleFailure(error, operation: .discovery)
            }
            self.finishRequest(requestToken)
        }
    }

    private func performCatalogDiscovery() {
        ensureClientStarted()
        let requestToken = beginRequest()
        let selectedGeneration = generation
        discoveryGeneration = selectedGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.canBeginRequest(requestToken, generation: selectedGeneration) else {
                self.finishRequest(requestToken)
                return
            }
            do {
                let payload = try await self.client.request(
                    commands: ["get"],
                    parameters: ["identifiers": nil]
                )
                guard !self.isStopped, !self.displayAsleep else {
                    self.finishRequest(requestToken)
                    return
                }
                guard self.generation == selectedGeneration else {
                    self.finishRequest(requestToken)
                    return
                }
                guard let payload else {
                    throw BetterDisplayIntegrationError.invalidResponse
                }
                let devices = try BetterDisplayVolumeParser.parseDevices(payload)
                let framebuffers = await self.readFramebuffers()
                guard !self.isStopped, !self.displayAsleep,
                      self.generation == selectedGeneration else {
                    self.finishRequest(requestToken)
                    return
                }
                self.framebuffers = framebuffers
                self.catalog = devices
                self.isAppUnavailable = false
                if let displayUUID = self.displayUUID {
                    if devices.contains(where: { $0.uuid == displayUUID }) {
                        self.emitCatalog(devices: devices, availability: .discovering)
                        self.validateSelectionAgainstCatalog()
                    } else {
                        self.invalidateCatalogTarget(catalog: devices)
                    }
                } else {
                    self.emitCatalog(
                        devices: devices,
                        availability: .deviceUnassociated
                    )
                    self.emit(
                        availability: .deviceUnassociated,
                        scalar: nil,
                        muteState: .unknown,
                        canSetVolume: false,
                        canMute: false
                    )
                }
            } catch {
                guard !self.isStopped,
                      !self.displayAsleep,
                      self.generation == selectedGeneration
                else {
                    self.finishRequest(requestToken)
                    return
                }
                self.handleFailure(error, operation: .discovery)
            }
            self.completeCatalogDiscovery(requestToken: requestToken)
        }
    }

    private func performRead(confirmation: ReadConfirmation?) {
        guard let outputID, let uid, let displayUUID else { return }
        guard requireCatalogTarget(displayUUID) else { return }
        ensureClientStarted()
        let requestToken = beginRequest()
        let selectedGeneration = generation
        let selectedInputGeneration = inputGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.canBeginRequest(requestToken, generation: selectedGeneration),
                  self.inputGeneration == selectedInputGeneration,
                  self.catalogTargetState(for: displayUUID) == .valid
            else {
                self.finishRequest(requestToken)
                return
            }
            do {
                let volumePayload = try await self.client.request(
                    commands: ["get"],
                    parameters: [
                        "UUID": displayUUID,
                        "volume": nil,
                        "value": nil,
                        "min": nil,
                        "max": nil
                    ]
                )
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: selectedInputGeneration
                ), self.catalogTargetState(for: displayUUID) == .valid else {
                    if self.catalogTargetState(for: displayUUID) == .invalid,
                       let catalog = self.catalog {
                        self.invalidateCatalogTarget(catalog: catalog)
                    }
                    self.finishRequest(requestToken)
                    return
                }
                guard let volumePayload else {
                    throw BetterDisplayIntegrationError.invalidResponse
                }
                let range = try BetterDisplayVolumeParser.parseVolumeRange(volumePayload)

                let mutePayload = try? await self.client.request(
                    commands: ["get"],
                    parameters: [
                        "UUID": displayUUID,
                        "mute": nil
                    ]
                )
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: selectedInputGeneration
                ), self.catalogTargetState(for: displayUUID) == .valid else {
                    if self.catalogTargetState(for: displayUUID) == .invalid,
                       let catalog = self.catalog {
                        self.invalidateCatalogTarget(catalog: catalog)
                    }
                    self.finishRequest(requestToken)
                    return
                }

                let muteState = BetterDisplayVolumeParser.parseMuteState(mutePayload)
                let volumeMatches = confirmation?.scalar.map {
                    abs(range.normalizedScalar - $0) <= 0.001
                } ?? true
                let muteMatches = confirmation?.isMuted.map {
                    switch muteState {
                    case .muted:
                        return $0
                    case .unmuted:
                        return !$0
                    case .unknown:
                        return false
                    }
                } ?? true
                let confirmed = volumeMatches && muteMatches
                let availability: BetterDisplayAvailability =
                    confirmation == nil || confirmed ? .available : .writeNotConfirmed
                let writable = confirmed

                self.latestRange = range
                self.latestMuteState = muteState
                self.desiredScalar = range.normalizedScalar
                self.desiredMuteState = muteState == .unknown ? nil : muteState
                self.canSetVolume = writable
                self.canMute = muteState != .unknown && muteMatches
                self.commandID = confirmation?.commandID
                self.readConfirmation = nil
                self.emit(
                    availability: availability,
                    scalar: range.normalizedScalar,
                    muteState: muteState,
                    canSetVolume: writable,
                    canMute: self.canMute,
                    commandID: confirmation?.commandID
                )
                self.schedulePoll()
            } catch {
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: selectedInputGeneration
                ) else {
                    self.finishRequest(requestToken)
                    return
                }
                self.handleFailure(error, operation: .read)
            }
            self.finishRequest(requestToken)
        }
    }

    private func performVolumeMutation() {
        guard let pendingVolume,
              let outputID,
              let uid,
              let displayUUID,
              let range = latestRange
        else {
            self.pendingVolume = nil
            return
        }
        guard requireCatalogTarget(displayUUID) else {
            self.pendingVolume = nil
            return
        }
        self.pendingVolume = nil
        volumeSendWindowOpen = false
        scheduleVolumeSendWindow()
        ensureClientStarted()
        let requestToken = beginRequest()
        let selectedGeneration = generation
        let selectedInputGeneration = inputGeneration
        let rawValue = range.rawValue(for: pendingVolume.scalar)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.canBeginRequest(requestToken, generation: selectedGeneration),
                  self.catalogTargetState(for: displayUUID) == .valid
            else {
                self.finishRequest(requestToken)
                return
            }
            do {
                _ = try await self.client.request(
                    commands: ["set"],
                    parameters: [
                        "UUID": displayUUID,
                        "volume": String(rawValue),
                        "min": String(range.minimum),
                        "max": String(range.maximum)
                    ]
                )
                guard self.acceptsMutationTarget(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration
                ), self.catalogTargetState(for: displayUUID) == .valid else {
                    if self.catalogTargetState(for: displayUUID) == .invalid,
                       let catalog = self.catalog {
                        self.invalidateCatalogTarget(catalog: catalog)
                    }
                    self.finishRequest(requestToken)
                    return
                }
                self.requestRead(
                    confirmation: ReadConfirmation(
                        commandID: pendingVolume.commandID,
                        scalar: pendingVolume.scalar,
                        isMuted: nil
                    )
                )
            } catch {
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: selectedInputGeneration
                ) else {
                    self.finishRequest(requestToken)
                    return
                }
                self.handleFailure(error, operation: .write)
            }
            self.finishRequest(requestToken)
        }
    }

    private func performMuteMutation() {
        guard let pendingMute,
              let outputID,
              let uid,
              let displayUUID
        else {
            self.pendingMute = nil
            return
        }
        guard requireCatalogTarget(displayUUID) else {
            self.pendingMute = nil
            return
        }
        self.pendingMute = nil
        ensureClientStarted()
        let requestToken = beginRequest()
        let selectedGeneration = generation
        let selectedInputGeneration = inputGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.canBeginRequest(requestToken, generation: selectedGeneration),
                  self.catalogTargetState(for: displayUUID) == .valid
            else {
                self.finishRequest(requestToken)
                return
            }
            do {
                _ = try await self.client.request(
                    commands: ["set"],
                    parameters: [
                        "UUID": displayUUID,
                        "mute": pendingMute.isMuted ? "on" : "off"
                    ]
                )
                guard self.acceptsMutationTarget(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration
                ), self.catalogTargetState(for: displayUUID) == .valid else {
                    if self.catalogTargetState(for: displayUUID) == .invalid,
                       let catalog = self.catalog {
                        self.invalidateCatalogTarget(catalog: catalog)
                    }
                    self.finishRequest(requestToken)
                    return
                }
                self.requestRead(
                    confirmation: ReadConfirmation(
                        commandID: pendingMute.commandID,
                        scalar: nil,
                        isMuted: pendingMute.isMuted
                    )
                )
            } catch {
                guard self.accepts(
                    outputID: outputID,
                    uid: uid,
                    displayUUID: displayUUID,
                    generation: selectedGeneration,
                    inputGeneration: selectedInputGeneration
                ) else {
                    self.finishRequest(requestToken)
                    return
                }
                self.handleFailure(error, operation: .write)
            }
            self.finishRequest(requestToken)
        }
    }

    private func validateSelectionAgainstCatalog() {
        guard let displayUUID, let catalog else { return }
        guard catalogTargetState(for: displayUUID) == .valid else {
            invalidateCatalogTarget(catalog: catalog)
            return
        }
        requestRead(confirmation: nil)
    }

    private func requireCatalogTarget(_ displayUUID: String) -> Bool {
        switch catalogTargetState(for: displayUUID) {
        case .valid:
            return true
        case .invalid:
            if let catalog {
                invalidateCatalogTarget(catalog: catalog)
            }
            return false
        case .unknown:
            // Do not guess an association while the catalog is unavailable.
            // Let a bounded discovery establish whether the target is valid.
            requestDiscovery(invalidateSelection: false)
            return false
        }
    }

    private func catalogTargetState(for displayUUID: String) -> CatalogTargetState {
        guard let catalog else { return .unknown }
        return catalog.contains(where: { $0.uuid == displayUUID })
            ? .valid
            : .invalid
    }

    private func invalidateCatalogTarget(catalog: [BetterDisplayDevice]) {
        self.catalog = catalog
        generation &+= 1
        inputGeneration &+= 1
        latestRange = nil
        latestMuteState = .unknown
        desiredMuteState = nil
        desiredScalar = nil
        canSetVolume = false
        canMute = false
        commandID = nil
        pendingVolume = nil
        pendingMute = nil
        readConfirmation = nil
        readRequested = false
        discoveryRequested = false
        cancelScheduledWork()
        emitCatalog(devices: catalog, availability: .deviceUnassociated)
        emit(
            availability: .deviceUnassociated,
            scalar: nil,
            muteState: .unknown,
            canSetVolume: false,
            canMute: false
        )
    }

    private func canBeginRequest(_ token: UInt64, generation: UInt64) -> Bool {
        // Selection can change between creating the task and executing it.
        // Reject stale work before it can send a command to the old display.
        !isStopped
            && !displayAsleep
            && !isAppUnavailable
            && self.generation == generation
            && activeRequestToken == token
    }

    private func beginRequest() -> UInt64 {
        nextRequestToken &+= 1
        activeRequestToken = nextRequestToken
        requestInFlight = true
        return nextRequestToken
    }

    private func finishRequest(_ token: UInt64) {
        guard activeRequestToken == token else { return }
        activeRequestToken = nil
        requestInFlight = false
        discoveryGeneration = nil
        drain()
    }

    private func completeCatalogDiscovery(requestToken: UInt64) {
        guard activeRequestToken == requestToken else { return }
        activeRequestToken = nil
        requestInFlight = false
        discoveryGeneration = nil
        let shouldStopClient = displayUUID == nil
            && !discoveryRequested
            && pendingVolume == nil
            && pendingMute == nil
            && !readRequested
        if shouldStopClient {
            stopClient()
            return
        }
        drain()
    }

    private func accepts(
        outputID: AudioDeviceID,
        uid: String,
        displayUUID: String,
        generation: UInt64,
        inputGeneration: UInt64
    ) -> Bool {
        !isStopped
            && !displayAsleep
            && !isAppUnavailable
            && self.outputID == outputID
            && self.uid == uid
            && self.displayUUID == displayUUID
            && self.generation == generation
            && self.inputGeneration == inputGeneration
    }

    private func acceptsMutationTarget(
        outputID: AudioDeviceID,
        uid: String,
        displayUUID: String,
        generation: UInt64
    ) -> Bool {
        !isStopped
            && !displayAsleep
            && !isAppUnavailable
            && self.outputID == outputID
            && self.uid == uid
            && self.displayUUID == displayUUID
            && self.generation == generation
    }

    private func ensureClientStarted() {
        guard !isClientStarted, !isStopped else { return }
        isClientStarted = true
        client.start { [weak self] event in
            self?.receive(event)
        }
    }

    private func stopClient() {
        guard isClientStarted else { return }
        client.stop()
        isClientStarted = false
    }

    private func receive(_ event: BetterDisplayEvent) {
        guard !isStopped else { return }
        switch event {
        case .launched:
            isAppUnavailable = false
            requestDiscovery(invalidateSelection: true)
        case .terminated:
            isAppUnavailable = true
            generation &+= 1
            inputGeneration &+= 1
            latestRange = nil
            latestMuteState = .unknown
            desiredMuteState = nil
            desiredScalar = nil
            canSetVolume = false
            canMute = false
            commandID = nil
            pendingVolume = nil
            pendingMute = nil
            readConfirmation = nil
            readRequested = false
            discoveryRequested = false
            activeRequestToken = nil
            requestInFlight = false
            cancelScheduledWork()
            emit(
                availability: .appAbsent,
                scalar: nil,
                muteState: .unknown,
                canSetVolume: false,
                canMute: false
            )
            emitCatalog(availability: .appAbsent)
        case .audioChanged:
            guard !isAppUnavailable else { return }
            requestRead(confirmation: nil)
        }
    }

    private func handleFailure(
        _ error: Error,
        operation: FailureOperation
    ) {
        guard !isStopped, !displayAsleep else { return }
        let availability = Self.availability(for: error)
        if availability == .unresponsive {
            isAppUnavailable = true
            pollTask?.cancel()
            pollTask = nil
            emitCatalog(availability: .unresponsive)
        }
        switch operation {
        case .discovery:
            emitCatalog(availability: availability)
            if displayUUID != nil {
                emit(
                    availability: availability,
                    scalar: nil,
                    muteState: .unknown,
                    canSetVolume: false,
                    canMute: false
                )
            }
        case .read, .write:
            latestRange = nil
            latestMuteState = .unknown
            desiredMuteState = nil
            desiredScalar = nil
            canSetVolume = false
            canMute = false
            pendingVolume = nil
            pendingMute = nil
            emit(
                availability: availability,
                scalar: nil,
                muteState: .unknown,
                canSetVolume: false,
                canMute: false
            )
        }
    }

    private func schedulePoll() {
        guard !isStopped,
              !displayAsleep,
              !isAppUnavailable,
              displayUUID != nil,
              latestRange != nil
        else {
            return
        }
        pollTask?.cancel()
        let interval: Duration = detailsVisible ? .seconds(2) : .seconds(10)
        let sleep = self.sleep
        pollTask = Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !self.isStopped else { return }
            self.requestRead(confirmation: nil)
        }
    }

    private func cancelScheduledWork() {
        pollTask?.cancel()
        pollTask = nil
        volumeRateTask?.cancel()
        volumeRateTask = nil
        volumeSendWindowOpen = true
    }

    private func scheduleVolumeSendWindowIfNeeded() {
        guard pendingVolume != nil else { return }
        scheduleVolumeSendWindow()
    }

    private func scheduleVolumeSendWindow() {
        guard volumeRateTask == nil,
              !isStopped,
              !displayAsleep,
              !isAppUnavailable
        else {
            return
        }
        let delay = debounce
        let sleep = self.sleep
        volumeRateTask = Task { @MainActor [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !self.isStopped else { return }
            self.volumeRateTask = nil
            self.volumeSendWindowOpen = true
            self.drain()
        }
    }

    private func emitCatalog(
        devices: [BetterDisplayDevice]? = nil,
        availability: BetterDisplayAvailability
    ) {
        catalogContinuation.yield(
            BetterDisplayCatalogUpdate(
                devices: devices ?? catalog ?? [],
                availability: availability,
                isCatalogLoaded: catalog != nil,
                outputUID: uid,
                displayUUID: displayUUID,
                canSetVolume: canSetVolume,
                automaticDisplayUUID: uid.flatMap {
                    BetterDisplayAudioDisplayMatcher.match(
                        outputUID: $0,
                        framebuffers: framebuffers,
                        devices: catalog ?? []
                    )
                }
            )
        )
    }

    private func emit(
        availability: BetterDisplayAvailability,
        scalar: Double? = nil,
        muteState: VolumeMuteState = .unknown,
        canSetVolume: Bool = false,
        canMute: Bool = false,
        commandID: UInt64? = nil
    ) {
        guard let outputID, let uid else { return }
        onUpdate(
            BetterDisplayVolumeUpdate(
                outputID: outputID,
                uid: uid,
                displayUUID: displayUUID,
                generation: generation,
                scalar: scalar,
                muteState: muteState,
                canSetVolume: canSetVolume,
                canMute: canMute,
                availability: availability,
                commandID: commandID
            )
        )
        emitCatalog(availability: availability)
    }

    private static func availability(for error: Error) -> BetterDisplayAvailability {
        if let error = error as? BetterDisplayIntegrationError {
            switch error {
            case .timedOut, .notStarted, .stopped:
                return .unresponsive
            case .invalidResponse:
                return .invalidResponse
            case .requestFailed, .tooManyPendingRequests:
                return .requestFailed
            }
        }
        if error is BetterDisplayVolumeParserError {
            return .invalidResponse
        }
        return .requestFailed
    }

    private enum FailureOperation {
        case discovery
        case read
        case write
    }
}
