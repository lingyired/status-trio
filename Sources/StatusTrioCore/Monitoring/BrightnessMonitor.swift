import AppKit
import CoreGraphics
import Foundation
import os

private let brightnessMonitorLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "BrightnessMonitor"
)

/// Aggregates per-display brightness backends into one published
/// `BrightnessStatus`.
///
/// Backend choice per display:
/// - External displays default to direct DDC (`VCP 0x10`).
/// - Built-in displays use DisplayServices (only it can drive them).
///
/// Reads are demand-driven: no coordinator exists until the brightness section
/// is visible, and everything is torn down when it is hidden or the display
/// sleeps. Built-in external changes arrive via DisplayServices' push
/// notification. External backends have no comparable system notification, so
/// the monitor re-reads only those rows while the brightness surface is
/// visible; the loop stops on hide, sleep and stop. Nothing polls in the
/// background.
@MainActor
final class BrightnessMonitor: BrightnessMonitoring {
    typealias DDCMaker = @MainActor (
        _ displayID: String,
        _ onUpdate: @escaping @MainActor (DDCBrightnessUpdate) -> Void
    ) -> DDCBrightnessCoordinator

    typealias BetterDisplayMaker = @MainActor (
        _ displayUUID: String,
        _ onUpdate: @escaping @MainActor (BetterDisplayBrightnessCoordinator.Update) -> Void
    ) -> BetterDisplayBrightnessCoordinator

    typealias DisplayServicesMaker = @MainActor (
        _ displayID: UInt32,
        _ onUpdate: @escaping @MainActor (DisplayServicesBrightnessUpdate) -> Void
    ) -> DisplayServicesBrightnessController

    private enum BackendKind: Equatable {
        case directDDC
        case displayServices
        case betterDisplay
    }

    private enum Backend {
        case ddc(DDCBrightnessCoordinator)
        case displayServices(DisplayServicesBrightnessController)
        case betterDisplay(BetterDisplayBrightnessCoordinator)
        /// No backend could be safely constructed for this display (e.g. an
        /// external without a resolvable CG display id). The row still appears
        /// but stays unavailable instead of writing to another screen.
        case unavailable
    }

    private struct Entry {
        var descriptor: DisplayDescriptor
        var backendKind: BackendKind
        /// The UUID handed to BetterDisplay (may differ from the system id).
        var betterDisplayUUID: String?
        var backend: Backend
        var state: DisplayBrightness
    }

    private let catalog: DisplayCatalogProviding
    private let makeDDC: DDCMaker
    private let makeDisplayServices: DisplayServicesMaker
    private let makeBetterDisplay: BetterDisplayMaker
    private let continuation: AsyncStream<BrightnessStatus>.Continuation
    let updates: AsyncStream<BrightnessStatus>

    private var entries: [String: Entry] = [:]
    /// Last known per-display state, kept across hide/show so the panel can draw
    /// the display list immediately instead of waiting for a fresh DDC read.
    private var cachedStates: [String: DisplayBrightness] = [:]
    private var configurations: [String: ExternalBrightnessConfiguration] = [:]
    private var detailsVisible = false
    private var displayAsleep = false
    private var started = false
    private var generation: UInt64 = 0
    private var readSequence: UInt64 = 0
    private let notificationCenter: NotificationCenter
    private let externalRefreshInterval: Duration
    private let externalRefreshSleep: @Sendable (Duration) async throws -> Void
    private var externalRefreshTask: Task<Void, Never>?
    private var screenParameterObserver: NSObjectProtocol?

    init(
        catalog: DisplayCatalogProviding = LiveDisplayCatalog(),
        makeDDC: DDCMaker? = nil,
        makeDisplayServices: DisplayServicesMaker? = nil,
        makeBetterDisplay: BetterDisplayMaker? = nil,
        notificationCenter: NotificationCenter = .default,
        externalRefreshInterval: Duration = .seconds(2),
        externalRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.catalog = catalog
        self.notificationCenter = notificationCenter
        self.externalRefreshInterval = externalRefreshInterval
        self.externalRefreshSleep = externalRefreshSleep
        self.makeDDC = makeDDC ?? { displayID, onUpdate in
            // DDC owns its timer, including failure backoff and the busy gate.
            // The monitor's fallback loop must never enqueue reads over writes.
            DDCBrightnessCoordinator(pollInterval: .seconds(2), onUpdate: onUpdate)
        }
        self.makeDisplayServices = makeDisplayServices ?? { displayID, onUpdate in
            DisplayServicesBrightnessController(
                displayID: CGDirectDisplayID(displayID),
                onUpdate: onUpdate
            )
        }
        self.makeBetterDisplay = makeBetterDisplay ?? { displayUUID, onUpdate in
            BetterDisplayBrightnessCoordinator(
                client: BetterDisplayIntegrationClient(),
                displayUUID: displayUUID,
                onUpdate: onUpdate
            )
        }

        var captured: AsyncStream<BrightnessStatus>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { captured = $0 }
        continuation = captured
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        // Display hot-plug is an AppKit notification; without it the list only
        // rebuilt on wake, so a panel already open when a screen is added or
        // removed kept the old rows and the old DDC service.
        screenParameterObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.topologyChanged() }
        }
        if detailsVisible, !displayAsleep { rebuild() }
    }

    deinit {
        externalRefreshTask?.cancel()
    }

    func stop() {
        started = false
        if let observer = screenParameterObserver {
            notificationCenter.removeObserver(observer)
            screenParameterObserver = nil
        }
        stopExternalRefreshLoop()
        stopCoordinators()
        continuation.finish()
    }

    func refresh() {
        guard started, detailsVisible, !displayAsleep else { return }
        if entries.isEmpty {
            rebuild()
        } else {
            for entry in entries.values {
                switch entry.backend {
                case .ddc(let coordinator): coordinator.refresh()
                case .displayServices(let coordinator): coordinator.refresh()
                case .betterDisplay(let coordinator): coordinator.refresh()
                case .unavailable: break
                }
            }
        }
    }

    func recover() {
        guard started, detailsVisible else { return }
        rebuild()
        refresh()
    }

    private var needsExternalRefreshLoop: Bool {
        entries.values.contains { entry in
            guard !entry.descriptor.isBuiltin else { return false }
            switch entry.backend {
            case .betterDisplay, .displayServices: return true
            case .ddc, .unavailable: return false
            }
        }
    }

    /// BetterDisplay OSD dispatch is optional, so visible external rows need a
    /// read fallback. DDC retains its own timer/backoff; the built-in panel uses
    /// native notifications. No fallback timer exists without a supported row.
    private func startExternalRefreshLoop() {
        guard started, detailsVisible, !displayAsleep, needsExternalRefreshLoop else {
            stopExternalRefreshLoop()
            return
        }
        guard externalRefreshTask == nil else { return }
        let interval = externalRefreshInterval
        let sleep = externalRefreshSleep
        externalRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.refreshExternalDisplays()
            }
        }
    }

    private func stopExternalRefreshLoop() {
        externalRefreshTask?.cancel()
        externalRefreshTask = nil
    }

    private func refreshExternalDisplays() {
        guard started, detailsVisible, !displayAsleep else { return }
        guard needsExternalRefreshLoop else {
            stopExternalRefreshLoop()
            return
        }
        for entry in entries.values where !entry.descriptor.isBuiltin {
            switch entry.backend {
            case .ddc: break
            case .displayServices(let coordinator): coordinator.refresh()
            case .betterDisplay(let coordinator): coordinator.refresh()
            case .unavailable: break
            }
        }
    }

    func setDetailsVisible(_ visible: Bool) {
        guard detailsVisible != visible else { return }
        detailsVisible = visible
        if visible {
            guard started, !displayAsleep else { return }
            rebuild()
        } else {
            // Stop the workers but keep the last published state in `cachedStates`
            // (and therefore in the store snapshot) so reopening the section draws
            // the list instantly instead of blanking first.
            stopExternalRefreshLoop()
            stopCoordinators()
        }
    }

    func setDisplayAsleep(_ asleep: Bool) {
        guard displayAsleep != asleep else { return }
        displayAsleep = asleep
        for entry in entries.values {
            switch entry.backend {
            case .ddc(let coordinator): coordinator.setDisplayAsleep(asleep)
            case .displayServices(let coordinator):
                if asleep { coordinator.stop() } else { coordinator.start() }
            case .betterDisplay(let coordinator):
                if asleep { coordinator.stop() } else { coordinator.start() }
            case .unavailable: break
            }
        }
        if asleep {
            stopExternalRefreshLoop()
        } else if detailsVisible {
            rebuild()
        }
    }

    func topologyChanged() {
        guard started, detailsVisible, !displayAsleep else { return }
        // A screen add/remove/rearrange can keep the same display identity while
        // the framebuffer behind it changes, so a retained DDC service may point
        // at hardware that is gone. Rebuild from scratch: tear every backend down
        // and let each display re-resolve, instead of reusing a stale service.
        rebuild(force: true)
        refresh()
    }

    // MARK: - Configuration

    func setBackend(_ backend: BrightnessBackend, forDisplayID displayID: String) {
        guard !displayID.isEmpty else { return }
        var configuration = ExternalBrightnessConfiguration.default
        configuration.backend = backend
        configurations[displayID] = configuration
        if detailsVisible { rebuild() }
    }

    func setExternalBrightnessConfigurations(
        _ configurations: [String: ExternalBrightnessConfiguration]
    ) {
        guard self.configurations != configurations else { return }
        self.configurations = configurations
        if detailsVisible { rebuild() }
    }

    // MARK: - Writes

    func setBrightness(_ scalar: Double, forDisplayID displayID: String) {
        guard let entry = entries[displayID], entry.state.canAdjust else { return }
        switch entry.backend {
        case .ddc(let coordinator):
            coordinator.setBrightness(scalar)
        case .displayServices(let coordinator):
            coordinator.setBrightness(scalar)
        case .betterDisplay(let coordinator):
            coordinator.setBrightness(scalar)
        case .unavailable:
            break
        }
    }

    func finishBrightnessAdjustment(displayID: String) {
        guard let entry = entries[displayID] else { return }
        if case .ddc(let coordinator) = entry.backend {
            coordinator.flushPendingBrightness()
        }
    }

    // MARK: - Rebuild

    private func rebuild(force: Bool = false) {
        guard started, detailsVisible, !displayAsleep else { return }
        generation &+= 1
        let descriptors = catalog.currentDisplays()
        var updated = entries

        // A forced rebuild (screen topology change) drops every backend so a
        // display that survived the change still re-resolves its service and
        // discards any write queued against the old connection.
        if force {
            for entry in entries.values { teardown(entry) }
            updated.removeAll(keepingCapacity: true)
        }

        // Drop entries whose display is gone.
        for (id, entry) in Array(updated) where !descriptors.contains(where: { $0.id == id }) {
            teardown(entry)
            updated.removeValue(forKey: id)
        }

        for descriptor in descriptors {
            let configuration = configuration(for: descriptor)
            let desiredKind: BackendKind
            switch configuration.backend {
            case .directDDC: desiredKind = .directDDC
            case .displayServices: desiredKind = .displayServices
            case .betterDisplay: desiredKind = .betterDisplay
            }
            let desiredBDBUUID = configuration.backend == .betterDisplay
                ? Self.resolvedBetterDisplayUUID(
                    for: descriptor,
                    explicit: configuration.betterDisplayUUID
                )
                : nil

            // Reuse only when the backend identity is unchanged. Comparing
            // `displayID` matters for DisplayServices/unavailable rows whose
            // descriptor id (EDID/UUID) can stay the same while the resolved CG
            // display id changes; reusing would keep a controller pointed at the
            // old display.
            if var existing = updated[descriptor.id],
               existing.backendKind == desiredKind,
               existing.betterDisplayUUID == desiredBDBUUID,
               existing.descriptor.displayID == descriptor.displayID {
                existing.descriptor = descriptor
                updated[descriptor.id] = existing
                continue
            }

            if let existing = updated[descriptor.id] {
                teardown(existing)
            }
            updated[descriptor.id] = makeEntry(
                for: descriptor,
                kind: desiredKind,
                betterDisplayUUID: desiredBDBUUID,
                allowsCachedAdjustability: !force
            )
        }

        entries = updated
        startExternalRefreshLoop()
        publish()
    }

    private func configuration(for descriptor: DisplayDescriptor) -> ExternalBrightnessConfiguration {
        // Built-in displays use DisplayServices; external displays use the
        // configured backend (direct DDC by default).
        if descriptor.isBuiltin {
            return ExternalBrightnessConfiguration(backend: .displayServices, betterDisplayUUID: nil)
        }
        return configurations[descriptor.id] ?? .default
    }

    /// The BetterDisplay device UUID for a display.
    ///
    /// - An explicit UUID from the stored configuration always wins; it is the
    ///   only identity we can trust without a CG lookup.
    /// - Built-in displays already key `descriptor.id` on the CG UUID
    ///   BetterDisplay addresses them by.
    /// - External displays must resolve their real `CGDirectDisplayID` to the
    ///   CG UUID BetterDisplay accepts. `displayID == 0` is never queried:
    ///   `CGDisplayCreateUUIDFromDisplayID(0)` resolves to the built-in display.
    ///   The catalog's `display-<id>` failure sentinel is also rejected. Both
    ///   cases return `nil` so the caller reports the display unavailable
    ///   instead of driving the wrong screen.
    static func resolvedBetterDisplayUUID(
        for descriptor: DisplayDescriptor,
        explicit: String? = nil,
        cgUUID: (UInt32) -> String = LiveDisplayCatalog.displayUUIDString
    ) -> String? {
        let explicitUUID = explicit?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitUUID, !explicitUUID.isEmpty {
            return explicitUUID
        }
        if descriptor.isBuiltin {
            return descriptor.id.isEmpty ? nil : descriptor.id
        }
        guard descriptor.displayID != 0 else { return nil }
        let uuid = cgUUID(descriptor.displayID)
        guard !uuid.isEmpty, !uuid.hasPrefix("display-") else { return nil }
        return uuid
    }

    private func makeEntry(
        for descriptor: DisplayDescriptor,
        kind: BackendKind,
        betterDisplayUUID: String?,
        allowsCachedAdjustability: Bool = true
    ) -> Entry {
        let cached = cachedStates[descriptor.id]
        let backend: BrightnessBackend
        switch kind {
        case .directDDC: backend = .directDDC
        case .displayServices: backend = .displayServices
        case .betterDisplay: backend = .betterDisplay
        }
        // After a topology change the cached value is only a hint for drawing the
        // row immediately; a possibly different display must re-read before the
        // panel offers a slider that writes to the wrong hardware.
        let initialState = DisplayBrightness(
            id: descriptor.id,
            name: descriptor.name,
            isBuiltin: descriptor.isBuiltin,
            scalar: cached?.scalar,
            canAdjust: allowsCachedAdjustability ? (cached?.canAdjust ?? false) : false,
            backend: backend,
            source: allowsCachedAdjustability
                ? (cached?.source ?? .unavailable(.readFailed))
                : .unavailable(.readFailed),
            readSequence: cached?.readSequence
        )
        let displayID = descriptor.id

        switch kind {
        case .directDDC:
            let coordinator = makeDDC(displayID) { [weak self] update in
                self?.apply(update, systemDisplayID: displayID)
            }
            coordinator.select(displayID: displayID)
            return Entry(
                descriptor: descriptor,
                backendKind: .directDDC,
                betterDisplayUUID: nil,
                backend: .ddc(coordinator),
                state: initialState
            )
        case .displayServices:
            // DisplayServices needs a real CG display id. 0 resolves to the
            // built-in panel, so never construct a controller for it.
            guard descriptor.displayID != 0 else {
                return unavailableEntry(for: descriptor, backend: .displayServices)
            }
            let coordinator = makeDisplayServices(descriptor.displayID) { [weak self] update in
                self?.apply(update, systemDisplayID: displayID)
            }
            coordinator.start()
            return Entry(
                descriptor: descriptor,
                backendKind: .displayServices,
                betterDisplayUUID: nil,
                backend: .displayServices(coordinator),
                state: initialState
            )
        case .betterDisplay:
            // No explicit UUID and no reliable CG UUID: fail closed rather than
            // fall back to the EDID id (which BetterDisplay cannot address) or
            // to displayID 0 (the built-in screen).
            guard let uuid = betterDisplayUUID, !uuid.isEmpty else {
                return unavailableEntry(for: descriptor, backend: .betterDisplay)
            }
            let coordinator = makeBetterDisplay(uuid) { [weak self] update in
                self?.apply(update, systemDisplayID: displayID)
            }
            coordinator.start()
            return Entry(
                descriptor: descriptor,
                backendKind: .betterDisplay,
                betterDisplayUUID: uuid,
                backend: .betterDisplay(coordinator),
                state: initialState
            )
        }
    }

    /// A row with no safe backend. It still publishes so the panel can show the
    /// display as unavailable, but it never constructs a coordinator that could
    /// write to the wrong screen.
    private func unavailableEntry(
        for descriptor: DisplayDescriptor,
        backend: BrightnessBackend
    ) -> Entry {
        Entry(
            descriptor: descriptor,
            backendKind: backend == .betterDisplay ? .betterDisplay : .displayServices,
            betterDisplayUUID: nil,
            backend: .unavailable,
            state: DisplayBrightness(
                id: descriptor.id,
                name: descriptor.name,
                isBuiltin: descriptor.isBuiltin,
                scalar: nil,
                canAdjust: false,
                backend: backend,
                source: .unavailable(.noBackend)
            )
        )
    }

    private func teardown(_ entry: Entry) {
        switch entry.backend {
        case .ddc(let coordinator): coordinator.stop()
        case .displayServices(let coordinator): coordinator.stop()
        case .betterDisplay(let coordinator): coordinator.stop()
        case .unavailable: break
        }
    }

    private func stopCoordinators() {
        for entry in entries.values { teardown(entry) }
        entries.removeAll()
    }

    // MARK: - Update application

    func latestUpdateSequence(forDisplayID displayID: String) -> UInt64 {
        entries[displayID]?.state.readSequence ?? 0
    }

    private func nextReadSequence() -> UInt64 {
        readSequence &+= 1
        return readSequence
    }

    private func apply(_ update: DDCBrightnessUpdate, systemDisplayID: String) {
        guard var entry = entries[systemDisplayID], entry.backendKind == .directDDC else { return }
        entry.state = DisplayBrightness(
            id: entry.descriptor.id,
            name: entry.descriptor.name,
            isBuiltin: entry.descriptor.isBuiltin,
            scalar: update.scalar,
            canAdjust: update.canAdjust,
            backend: .directDDC,
            source: update.source,
            readSequence: nextReadSequence()
        )
        entries[systemDisplayID] = entry
        publish()
    }

    private func apply(
        _ update: DisplayServicesBrightnessUpdate,
        systemDisplayID: String
    ) {
        guard var entry = entries[systemDisplayID], entry.backendKind == .displayServices else {
            return
        }
        entry.state = DisplayBrightness(
            id: entry.descriptor.id,
            name: entry.descriptor.name,
            isBuiltin: entry.descriptor.isBuiltin,
            scalar: update.scalar,
            canAdjust: update.canAdjust,
            backend: .displayServices,
            source: update.source,
            readSequence: nextReadSequence()
        )
        entries[systemDisplayID] = entry
        publish()
    }

    private func apply(
        _ update: BetterDisplayBrightnessCoordinator.Update,
        systemDisplayID: String
    ) {        guard var entry = entries[systemDisplayID], entry.backendKind == .betterDisplay else {
            return
        }
        entry.state = DisplayBrightness(
            id: entry.descriptor.id,
            name: entry.descriptor.name,
            isBuiltin: entry.descriptor.isBuiltin,
            scalar: update.scalar,
            canAdjust: update.canSet,
            backend: .betterDisplay,
            source: update.source,
            readSequence: nextReadSequence()
        )
        entries[systemDisplayID] = entry
        publish()
    }

    private func publish() {
        let displays = entries.values
            .sorted { lhs, rhs in
                if lhs.descriptor.isBuiltin != rhs.descriptor.isBuiltin {
                    return lhs.descriptor.isBuiltin
                }
                if lhs.descriptor.name != rhs.descriptor.name {
                    return lhs.descriptor.name < rhs.descriptor.name
                }
                return lhs.descriptor.id < rhs.descriptor.id
            }
            .map(\.state)
        for display in displays {
            cachedStates[display.id] = display
        }
        continuation.yield(
            BrightnessStatus(displays: displays, transitionGeneration: generation)
        )
    }
}
