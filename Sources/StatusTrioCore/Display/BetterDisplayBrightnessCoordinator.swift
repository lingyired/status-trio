import Foundation

/// Optional capability for a BetterDisplay request client that can surface OSD
/// brightness hints. Kept as a separate protocol so the existing audio event
/// stream (`BetterDisplayEvent` / `isAudioEvent`) keeps its exact semantics.
@MainActor
protocol BetterDisplayBrightnessHintSource: AnyObject {
    /// Registers (or clears, with `nil`) a handler invoked when BetterDisplay
    /// posts an OSD notification whose `controlTarget == "brightness"`.
    func setBrightnessOSDHandler(_ handler: (@MainActor () -> Void)?)
}

/// Reads and writes a single display's brightness through BetterDisplay's
/// notification API, keyed strictly by `displayUUID` (never by audio output).
///
/// This mirrors `BetterDisplayVolumeCoordinator`'s request shapes but is
/// deliberately standalone and small: it does not poll, does not own a catalog,
/// and never reports an optimistic value. Every write is followed by a read-back
/// and only a matching read-back is reported as `betterDisplay`; a mismatch is
/// reported as `.unavailable(.writeNotConfirmed)`.
///
/// Request shapes (mirroring the proven `volume` commands):
/// - get:  `commands: ["get"]`, parameters `UUID`, `brightness`, `value`, `min`,
///   `max` all present with `brightness`/`value`/`min`/`max` as `nil`.
///   Response payload is `"current,minimum,maximum"`.
/// - set:  `commands: ["set"]`, parameters `UUID`, `brightness` (raw value in the
///   display's native range), plus `min`/`max` from the last known range.
///
/// - Warning: The exact BetterDisplay parameter keys for `brightness` (as
///   opposed to the proven `volume` keys) and the payload framing are
///   **unverified against a live BetterDisplay build in this environment**.
///   Real-device behavior is NOT RUN; confirm both against a running app before
///   trusting the values.
@MainActor
final class BetterDisplayBrightnessCoordinator {
    /// One brightness observation for a single display, delivered to the monitor.
    struct Update: Equatable, Sendable {
        let displayUUID: String
        /// 0...1, or nil when the value is unknown/unreadable.
        let scalar: Double?
        /// Whether a write can currently be attempted.
        let canSet: Bool
        /// Where this observation came from, or why brightness is unavailable.
        let source: BrightnessControlSource
        /// Monotonic id for this operation, so the monitor can drop stale updates.
        let commandID: UInt64?
    }

    /// A write whose read-back differs from the requested value by more than this
    /// is treated as unconfirmed. 2% absorbs one native step on 0...100 scales.
    private static let confirmationTolerance = 0.02

    private struct BrightnessRange: Equatable {
        let current: Double
        let minimum: Double
        let maximum: Double

        var normalized: Double {
            (current - minimum) / (maximum - minimum)
        }

        func rawValue(for scalar: Double) -> Double {
            minimum + scalar * (maximum - minimum)
        }
    }

    let displayUUID: String

    private let client: any BetterDisplayRequesting
    private let onUpdate: @MainActor (Update) -> Void

    private(set) var latestUpdate: Update?
    private var lastRange: BrightnessRange?
    private var commandID: UInt64 = 0
    private var generation: UInt64 = 0
    private var isStarted = false
    private var isClientStarted = false
    private var requestInFlight = false
    private var pendingScalar: Double?

    init(
        client: any BetterDisplayRequesting,
        displayUUID: String,
        onUpdate: @escaping @MainActor (Update) -> Void
    ) {
        self.client = client
        self.displayUUID = displayUUID
        self.onUpdate = onUpdate
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        if let hintSource = client as? BetterDisplayBrightnessHintSource {
            hintSource.setBrightnessOSDHandler { [weak self] in
                self?.refresh()
            }
        }
        performRead()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        generation &+= 1
        requestInFlight = false
        pendingScalar = nil
        lastRange = nil
        (client as? BetterDisplayBrightnessHintSource)?
            .setBrightnessOSDHandler(nil)
        stopClient()
    }

    // MARK: - Operations

    /// Re-reads the current brightness.
    func refresh() {
        guard isStarted, !requestInFlight else { return }
        performRead()
    }

    /// Requests a brightness write and confirms it with a read-back.
    ///
    /// `scalar` is clamped to 0...1. If the native range is not known yet, one
    /// `get` is issued first so the raw value can be computed; a write is never
    /// sent blind.
    func setBrightness(_ scalar: Double) {
        guard isStarted else { return }
        let target = min(max(scalar, 0), 1)
        if requestInFlight {
            // A drag can outrun the display's request round-trip. Keep only the
            // newest value and send it when the current request ends, so the
            // final slider position is never silently dropped.
            pendingScalar = target
            return
        }
        performWrite(target)
    }

    private func performWrite(_ target: Double) {
        ensureClientStarted()
        requestInFlight = true
        generation &+= 1
        let requestGeneration = generation
        let operationID = nextCommandID()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var range = self.lastRange
                if range == nil {
                    let payload = try await self.requestGet()
                    guard self.accepts(requestGeneration) else { return }
                    guard let payload, let parsed = Self.parseRange(payload) else {
                        self.finish(
                            requestGeneration,
                            scalar: nil,
                            canSet: false,
                            source: .unavailable(.readFailed),
                            commandID: operationID
                        )
                        return
                    }
                    range = parsed
                    self.lastRange = parsed
                }
                guard let range else {
                    self.finish(
                        requestGeneration,
                        scalar: nil,
                        canSet: false,
                        source: .unavailable(.readFailed),
                        commandID: operationID
                    )
                    return
                }

                let raw = range.rawValue(for: target)
                _ = try await self.client.request(
                    commands: ["set"],
                    parameters: [
                        "UUID": self.displayUUID,
                        "brightness": String(raw),
                        "min": String(range.minimum),
                        "max": String(range.maximum)
                    ]
                )
                guard self.accepts(requestGeneration) else { return }

                let confirmationPayload = try await self.requestGet()
                guard self.accepts(requestGeneration) else { return }
                guard
                    let confirmationPayload,
                    let confirmed = Self.parseRange(confirmationPayload)
                else {
                    self.finish(
                        requestGeneration,
                        scalar: nil,
                        canSet: false,
                        source: .unavailable(.readFailed),
                        commandID: operationID
                    )
                    return
                }
                self.lastRange = confirmed
                if abs(confirmed.normalized - target)
                    <= Self.confirmationTolerance
                {
                    self.finish(
                        requestGeneration,
                        scalar: confirmed.normalized,
                        canSet: true,
                        source: .betterDisplay,
                        commandID: operationID
                    )
                } else {
                    self.finish(
                        requestGeneration,
                        scalar: confirmed.normalized,
                        canSet: true,
                        source: .unavailable(.writeNotConfirmed),
                        commandID: operationID
                    )
                }
            } catch {
                guard self.accepts(requestGeneration) else { return }
                self.finish(
                    requestGeneration,
                    scalar: nil,
                    canSet: false,
                    source: Self.source(for: error),
                    commandID: operationID
                )
            }
        }
    }

    // MARK: - Reads

    private func performRead() {
        ensureClientStarted()
        requestInFlight = true
        generation &+= 1
        let requestGeneration = generation
        let operationID = nextCommandID()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.requestGet()
                guard self.accepts(requestGeneration) else { return }
                guard let payload, let parsed = Self.parseRange(payload) else {
                    self.finish(
                        requestGeneration,
                        scalar: nil,
                        canSet: false,
                        source: .unavailable(.readFailed),
                        commandID: operationID
                    )
                    return
                }
                self.lastRange = parsed
                self.finish(
                    requestGeneration,
                    scalar: parsed.normalized,
                    canSet: true,
                    source: .betterDisplay,
                    commandID: operationID
                )
            } catch {
                guard self.accepts(requestGeneration) else { return }
                self.finish(
                    requestGeneration,
                    scalar: nil,
                    canSet: false,
                    source: Self.source(for: error),
                    commandID: operationID
                )
            }
        }
    }

    private func requestGet() async throws -> String? {
        try await client.request(
            commands: ["get"],
            parameters: [
                "UUID": displayUUID,
                "brightness": nil,
                "value": nil,
                "min": nil,
                "max": nil
            ]
        )
    }

    // MARK: - Events

    private func receive(_ event: BetterDisplayEvent) {
        guard isStarted else { return }
        switch event {
        case .launched:
            refresh()
        case .terminated:
            lastRange = nil
            generation &+= 1
            requestInFlight = false
            emit(
                scalar: nil,
                canSet: false,
                source: .unavailable(.appAbsent),
                commandID: nil
            )
        case .audioChanged:
            // The brightness coordinator does not react to audio OSD hints.
            break
        }
    }

    private func ensureClientStarted() {
        guard !isClientStarted, isStarted else { return }
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

    // MARK: - Helpers

    private func nextCommandID() -> UInt64 {
        commandID &+= 1
        return commandID
    }

    private func accepts(_ requestGeneration: UInt64) -> Bool {
        isStarted && requestGeneration == generation
    }

    private func finish(
        _ requestGeneration: UInt64,
        scalar: Double?,
        canSet: Bool,
        source: BrightnessControlSource,
        commandID: UInt64?
    ) {
        guard accepts(requestGeneration) else { return }
        requestInFlight = false
        emit(
            scalar: scalar,
            canSet: canSet,
            source: source,
            commandID: commandID
        )
        drainPendingWrite()
    }

    private func drainPendingWrite() {
        guard isStarted, !requestInFlight, let next = pendingScalar else { return }
        pendingScalar = nil
        performWrite(next)
    }

    private func emit(
        scalar: Double?,
        canSet: Bool,
        source: BrightnessControlSource,
        commandID: UInt64?
    ) {
        let update = Update(
            displayUUID: displayUUID,
            scalar: scalar,
            canSet: canSet,
            source: source,
            commandID: commandID
        )
        latestUpdate = update
        onUpdate(update)
    }

    private static func parseRange(_ payload: String) -> BrightnessRange? {
        let values = payload
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard
            values.count == 3,
            let current = Double(values[0]),
            let minimum = Double(values[1]),
            let maximum = Double(values[2]),
            current.isFinite,
            minimum.isFinite,
            maximum.isFinite,
            maximum > minimum,
            current >= minimum,
            current <= maximum
        else {
            return nil
        }
        return BrightnessRange(
            current: current,
            minimum: minimum,
            maximum: maximum
        )
    }

    private static func source(for error: Error) -> BrightnessControlSource {
        guard let error = error as? BetterDisplayIntegrationError else {
            return .unavailable(.unresponsive)
        }
        switch error {
        case .timedOut:
            return .unavailable(.timeout)
        case .invalidResponse:
            return .unavailable(.readFailed)
        case .notStarted, .tooManyPendingRequests, .requestFailed, .stopped:
            return .unavailable(.unresponsive)
        }
    }
}
