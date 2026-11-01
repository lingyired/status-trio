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
/// - Built-in displays use BetterDisplay (only it can drive them).
///
/// Reads are demand-driven: no coordinator exists until the brightness section
/// is visible, and everything is torn down when it is hidden or the display
/// sleeps. Nothing polls on a timer.
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
    private let notificationCenter: NotificationCenter
    private var screenParameterObserver: NSObjectProtocol?

    init(
        catalog: DisplayCatalogProviding = LiveDisplayCatalog(),
        makeDDC: DDCMaker? = nil,
        makeDisplayServices: DisplayServicesMaker? = nil,
        makeBetterDisplay: BetterDisplayMaker? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.catalog = catalog
        self.notificationCenter = notificationCenter
        self.makeDDC = makeDDC ?? { displayID, onUpdate in
            DDCBrightnessCoordinator(onUpdate: onUpdate)
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
    }

    func stop() {
        started = false
        if let observer = screenParameterObserver {
            notificationCenter.removeObserver(observer)
            screenParameterObserver = nil
        }
        stopCoordinators()
        continuation.finish()
    }

    func refresh() {
        guard started, detailsVisible else { return }
        if entries.isEmpty {
            rebuild()
        } else {
            for entry in entries.values {
                switch entry.backend {
                case .ddc(let coordinator): coordinator.refresh()
                case .displayServices(let coordinator): coordinator.refresh()
                case .betterDisplay(let coordinator): coordinator.refresh()
                }
            }
        }
    }

    func recover() {
        guard started, detailsVisible else { return }
        rebuild()
        refresh()
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
            }
        }
        if !asleep, detailsVisible { rebuild() }
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
                ? (configuration.betterDisplayUUID ?? descriptor.id)
                : nil

            if var existing = updated[descriptor.id],
               existing.backendKind == desiredKind,
               existing.betterDisplayUUID == desiredBDBUUID {
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
                : .unavailable(.readFailed)
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
            let uuid = betterDisplayUUID ?? displayID
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

    private func teardown(_ entry: Entry) {
        switch entry.backend {
        case .ddc(let coordinator): coordinator.stop()
        case .displayServices(let coordinator): coordinator.stop()
        case .betterDisplay(let coordinator): coordinator.stop()
        }
    }

    private func stopCoordinators() {
        for entry in entries.values { teardown(entry) }
        entries.removeAll()
    }

    // MARK: - Update application

    private func apply(_ update: DDCBrightnessUpdate, systemDisplayID: String) {
        guard var entry = entries[systemDisplayID], entry.backendKind == .directDDC else { return }
        entry.state = DisplayBrightness(
            id: entry.descriptor.id,
            name: entry.descriptor.name,
            isBuiltin: entry.descriptor.isBuiltin,
            scalar: update.scalar,
            canAdjust: update.canAdjust,
            backend: .directDDC,
            source: update.source
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
            source: update.source
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
            source: update.source
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
