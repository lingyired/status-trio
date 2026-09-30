import Combine
import CoreAudio
import Foundation

/// Owns the AirPods listening-mode surface for the Bluetooth panel's visible
/// lifetime.
///
/// It is deliberately a separate object from `BluetoothDeviceController` (the plan's
/// Option B): the paired-device controller is a large, carefully-synchronised
/// lifecycle owner, and this subsystem — one discovery on panel open, one write per
/// tap, a short read-back — is simpler to reason about and to test on its own. The
/// view holds both and drives this one from the same appear/disappear and refresh
/// hooks the device list already uses.
///
/// The guarantees that matter live here and are covered by tests: discovery runs
/// only when asked (never on a timer), capabilities are keyed by the normalized
/// Bluetooth address so a rename or a re-pair cannot strand a stale control, a
/// write is confirmed by read-back rather than assumed, and a failure rolls the UI
/// back to what the device actually reports.
@MainActor
final class BluetoothListeningModeController: ObservableObject {
    /// The control state per connected, eligible device, keyed by the same
    /// normalized address the battery levels use. Absence means "no control".
    @Published private(set) var presentations: [String: BluetoothListeningModePresentation] = [:]

    private let hal: BluetoothListeningModeHAL
    private let endpointProvider: any CoreAudioBluetoothEndpointProviding
    private let failureClearDelay: Duration
    /// How long a preview write shows its spinner before settling. Real writes
    /// settle when the read-back confirms, which is CoreAudio-bound; preview
    /// writes settle on a fixed delay so the busy state is visible without
    /// waiting on anything.
    private let previewSettleDelay: Duration

    /// Interface-preview mode. When true, `refresh` publishes a synthetic
    /// three-capsule presentation for every connected AirPods without consulting
    /// the HAL, the endpoint provider, or the identity mapper, and `setMode`
    /// walks the same `.changing` → `.settled` path but never issues a real
    /// write. The UI and the tap feedback look identical to a working device —
    /// that is the whole point. This is the only way a preview presentation can
    /// exist; it is set from a Settings toggle and cleared again on the next
    /// `refresh` once the toggle is off.
    var previewMode: Bool = false

    /// Preview's authoritative selection per normalized address. Real writes go
    /// to the device and are re-read; preview writes only live here, so the
    /// picker persists across refreshes while preview is on but is dropped when
    /// preview turns off and never reaches the actual device.
    private var previewSelectedModes: [String: BluetoothListeningMode] = [:]

    /// The modes preview publishes. Three (not `off`) matches what AirPods Pro
    /// expose in Control Center, and matches the plan's default set — it is
    /// deliberately fixed because the point of the preview is to render the
    /// layout without consulting the device.
    static let previewAvailableModes: [BluetoothListeningMode] = [
        .noiseCancellation, .transparency, .adaptive
    ]

    /// The address prefix a preview-only synthetic device must carry. The UI's
    /// preview block mints addresses like `PREVIEW:1` so `refreshPreview` can
    /// accept them regardless of the user's configured display name, which may
    /// not contain "AirPods" — the `isAirPods` name heuristic is for the real
    /// surface, and applying it to a synthetic row would silently hide it.
    nonisolated static let previewAddressPrefix = "PREVIEW:"

    /// The synthetic CoreAudio endpoint a preview device is hung off, so the audio
    /// output list — where the listening-mode control now lives — can find it by
    /// device id exactly as it finds a real one. Mapped into the very top of the
    /// `AudioDeviceID` space (`max - index`) so it can never collide with a real id,
    /// which the HAL allocates from the low end. Only the `PREVIEW:<index>` rows the
    /// preview injects get one; anything else is `nil`.
    nonisolated static func syntheticEndpoint(for id: String) -> AudioDeviceID? {
        guard id.hasPrefix(previewAddressPrefix),
              let index = Int(id.dropFirst(previewAddressPrefix.count)),
              index > 0 else {
            return nil
        }
        return AudioDeviceID.max - AudioDeviceID(index)
    }

    /// The endpoint each address resolved to at the last refresh, so a later tap
    /// writes the same target discovery chose and a re-resolve can invalidate it.
    private var resolvedEndpoints: [String: AudioDeviceID] = [:]

    /// In-flight write tasks, kept so a refresh or a panel close can cancel them
    /// rather than let a late read-back publish onto a control that has gone away.
    private var changeTasks: [String: Task<Void, Never>] = [:]
    private var failureClearTasks: [String: Task<Void, Never>] = [:]
    /// Per-address generation, so a cancelled or superseded write's completion
    /// cannot touch the presentation the next refresh published.
    private var generations: [String: UInt64] = [:]

    /// The `lstm` property listener seam. The controller subscribes per resolved
    /// endpoint in `refresh` and clears them in `stop`, so an external mode change
    /// (the stem, Control Center, another Mac, Siri) reflects here without waiting
    /// for the panel to reopen or for the user to tap. Preview mode never touches
    /// the seam — synthetic rows have no device to listen to.
    private let listenerBackend: any BluetoothListeningModePropertyListening

    /// The queue CoreAudio dispatches `lstm` signals on. Serial so a burst of
    /// notifications does not fan out; the block body only hops to MainActor, so
    /// the queue itself is not where the presentation is mutated.
    private let listenerQueue = DispatchQueue(
        label: "com.lingsmbp.StatusTrio.bluetooth.listeningMode.listener"
    )

    /// The active subscription per endpoint we are listening on. Keeping the exact
    /// block reference here is what lets `AudioObjectRemovePropertyListenerBlock`
    /// match the same registration — a fresh closure would leave the CoreAudio
    /// side subscribed and the callback firing into a controller that already
    /// dropped the presentation.
    private var subscriptions: [AudioDeviceID: BluetoothListeningModeSubscription] = [:]

    init(
        hal: BluetoothListeningModeHAL = BluetoothListeningModeHAL(),
        endpointProvider: any CoreAudioBluetoothEndpointProviding = CoreAudioBluetoothListeningModeEndpointProvider(),
        listenerBackend: any BluetoothListeningModePropertyListening = CoreAudioBluetoothListeningModeListenerBackend(),
        failureClearDelay: Duration = .seconds(2),
        previewSettleDelay: Duration = .milliseconds(400)
    ) {
        self.hal = hal
        self.endpointProvider = endpointProvider
        self.listenerBackend = listenerBackend
        self.failureClearDelay = failureClearDelay
        self.previewSettleDelay = previewSettleDelay
    }

    /// Discovers and publishes the controls for the currently connected AirPods.
    ///
    /// Called when the panel becomes visible and again on a user refresh — never on
    /// a timer. Each connected AirPods candidate is resolved to an endpoint by the
    /// identity mapper; anything the mapper is not certain about simply gets no
    /// entry, so the row keeps its existing appearance and writes nothing.
    ///
    /// In `previewMode`, discovery is bypassed entirely: every connected AirPods
    /// gets a synthetic three-capsule presentation and no CoreAudio call is made.
    /// Turning preview off re-runs the real path, so any presentation that the real
    /// subsystem would not have published disappears on the next refresh.
    func refresh(devices: [BluetoothDevice]) {
        if previewMode {
            refreshPreview(devices: devices)
            return
        }
        let eligible = devices.filter { $0.isConnected && $0.isAirPods }
        let endpoints = eligible.isEmpty ? [] : endpointProvider.discoverEndpoints(using: hal)

        var next: [String: BluetoothListeningModePresentation] = [:]
        var nextResolved: [String: AudioDeviceID] = [:]

        for device in eligible {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty,
                  let endpointID = BluetoothListeningModeEndpointMapper.endpointID(
                      forNormalizedAddress: address,
                      connectedEligibleAirPodsCount: eligible.count,
                      in: endpoints
                  ),
                  let endpoint = endpoints.first(where: { $0.audioDeviceID == endpointID }),
                  endpoint.capability.isControllable else {
                continue
            }
            // Preserve an in-flight state if the device is still resolved to the same
            // endpoint, so a refresh mid-write does not erase the spinner.
            if let existing = presentations[address], existing.isChanging,
               resolvedEndpoints[address] == endpointID {
                next[address] = existing
            } else {
                next[address] = BluetoothListeningModePresentation(capability: endpoint.capability)
            }
            nextResolved[address] = endpointID
        }

        // Anything no longer resolved has its tasks cancelled and its generation
        // bumped, so a late completion cannot resurrect it.
        for address in presentations.keys where next[address] == nil {
            cancelTasks(for: address)
            bumpGeneration(for: address)
        }

        presentations = next
        resolvedEndpoints = nextResolved
        // A real refresh invalidates every preview selection: preview state must
        // never leak back onto the live control surface after the toggle is off.
        previewSelectedModes.removeAll()
        // Reconcile the `lstm` listeners against the freshly-resolved endpoint set:
        // a new subscription catches a mode change on a just-connected AirPods, an
        // unsubscribe stops a change on a disconnected one from firing into a
        // controller that already dropped the presentation.
        syncSubscriptions(to: Set(nextResolved.values))
    }

    /// The preview-side refresh. No HAL, no endpoint provider, no identity mapper.
    /// Selection rides on `previewSelectedModes` so a re-open of the panel keeps
    /// whatever the user last tapped; a mode that was mid-write before this refresh
    /// keeps its changing state so the spinner does not disappear under the finger.
    ///
    /// Eligibility is `isConnected && (isAirPods || preview-prefixed address)`.
    /// The prefix branch lets the UI inject synthetic rows that exercise the
    /// composed layout even when the operator picks a display name that would not
    /// match the "AirPods" heuristic — a preview row the user renamed to
    /// "Long-Name-Test" should still render.
    private func refreshPreview(devices: [BluetoothDevice]) {
        let eligible = devices.filter { device in
            device.isConnected && (
                device.isAirPods || device.id.hasPrefix(Self.previewAddressPrefix)
            )
        }
        var next: [String: BluetoothListeningModePresentation] = [:]
        var nextEndpoints: [String: AudioDeviceID] = [:]

        for device in eligible {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty else { continue }
            if let existing = presentations[address], existing.isChanging {
                next[address] = existing
            } else {
                next[address] = BluetoothListeningModePresentation(
                    availableModes: Self.previewAvailableModes,
                    selectedMode: previewSelectedModes[address] ?? .noiseCancellation
                )
            }
            // Mint the same synthetic endpoint the preview output row is built
            // with, so `control(forEndpoint:)` resolves a preview capsule exactly
            // as a real one — the control now lives on the output list, not the
            // Bluetooth row, and it needs an endpoint to hang off.
            if let endpoint = Self.syntheticEndpoint(for: device.id) {
                nextEndpoints[address] = endpoint
            }
        }

        for address in presentations.keys where next[address] == nil {
            cancelTasks(for: address)
            bumpGeneration(for: address)
        }

        presentations = next
        resolvedEndpoints = nextEndpoints
        // Preview has no real device to subscribe to. Any subscription the previous
        // real refresh left behind must go away, or a live AirPods would keep
        // firing signals into a controller that is only rendering synthetic rows.
        syncSubscriptions(to: [])
    }

    /// Asks a device to switch to `mode`, publishing the in-flight state and
    /// reconciling the result against the read-back.
    ///
    /// In `previewMode`, the write is not issued. The state machine still publishes
    /// `.changing(to:)` and later `.settled(on:)`, and the guard rules — no re-tap
    /// on the selected mode, no stacking a second write on a changing capsule — are
    /// identical, so the row's tap feedback matches what a real device produces.
    func setMode(_ mode: BluetoothListeningMode, for device: BluetoothDevice) {
        setMode(mode, forAddress: BluetoothBatteryReader.normalizedAddress(device.id))
    }

    /// The address-driven entry point. The audio output list resolves a row to a
    /// control via `control(forEndpoint:)`, then hands the resolved address back
    /// here — the same target `refresh` chose, so a write never needs the original
    /// `BluetoothDevice`.
    func setMode(_ mode: BluetoothListeningMode, forAddress address: String) {
        if previewMode {
            setModePreview(mode, forAddress: address)
            return
        }
        guard var presentation = presentations[address],
              let endpointID = resolvedEndpoints[address],
              presentation.availableModes.contains(mode) else {
            return
        }
        // Already switching, or already on that mode: never stack a second write, and
        // never write to re-select the highlighted button (§21).
        guard !presentation.isChanging, presentation.selectedMode != mode else { return }

        presentation = presentation.changing(to: mode)
        presentations[address] = presentation
        let generation = bumpGeneration(for: address)
        changeTasks[address]?.cancel()

        changeTasks[address] = Task { [weak self, hal = self.hal] in
            let result = await hal.setMode(mode, for: endpointID)
            guard let self, !Task.isCancelled, self.generations[address] == generation else { return }
            self.apply(result, of: mode, to: presentation, at: address, endpointID: endpointID)
        }
    }

    /// The control, if any, that belongs to a CoreAudio output endpoint. The audio
    /// output list asks this for each row: a hit means the row is an AirPods whose
    /// listening mode is switchable here, so the row renders the capsules under it.
    /// Absence means the row draws exactly as any other output device.
    func control(
        forEndpoint endpoint: AudioDeviceID
    ) -> (address: String, presentation: BluetoothListeningModePresentation)? {
        guard let address = address(forEndpoint: endpoint),
              let presentation = presentations[address],
              presentation.isControllable else {
            return nil
        }
        return (address, presentation)
    }

    /// Which address, if any, the last refresh resolved to this endpoint. Only the
    /// resolved endpoints carry a control, so the reverse lookup is exactly the set
    /// the output list may light up.
    private func address(forEndpoint endpoint: AudioDeviceID) -> String? {
        resolvedEndpoints.first { $0.value == endpoint }?.key
    }

    /// Preview-side setMode. Same guards, same state machine, but the "write" only
    /// moves the in-memory preview selection and the settle happens after a fixed
    /// short delay so the spinner stays visible. No HAL, no endpoint, no failure
    /// branch — a preview write always "succeeds", because that is what makes the
    /// interaction feel the same without touching a device.
    private func setModePreview(_ mode: BluetoothListeningMode, forAddress address: String) {
        guard var presentation = presentations[address],
              presentation.availableModes.contains(mode) else { return }
        guard !presentation.isChanging, presentation.selectedMode != mode else { return }

        presentation = presentation.changing(to: mode)
        presentations[address] = presentation
        let generation = bumpGeneration(for: address)
        changeTasks[address]?.cancel()

        changeTasks[address] = Task { [weak self, delay = self.previewSettleDelay] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.generations[address] == generation else { return }
            self.previewSelectedModes[address] = mode
            self.presentations[address] = presentation.settled(on: mode)
            self.changeTasks[address] = nil
        }
    }

    /// Cancels every outstanding observation and clears the surface. The view calls
    /// this when the panel disappears, honouring the plan's "no residual timer or
    /// task once the panel closes".
    func stop() {
        for address in presentations.keys {
            cancelTasks(for: address)
            bumpGeneration(for: address)
        }
        changeTasks.removeAll()
        failureClearTasks.removeAll()
        presentations = [:]
        resolvedEndpoints = [:]
        // The panel is going away; the plan's "no residual timer or task once the
        // panel closes" applies to CoreAudio subscriptions too. `syncSubscriptions`
        // with an empty set removes every registered block.
        syncSubscriptions(to: [])
    }

    // MARK: - External `lstm` changes

    /// Reconciles the active subscription set with the freshly resolved endpoints.
    /// Called at the tail of every real `refresh`, and with an empty set when
    /// preview takes over or when the panel stops.
    ///
    /// A stable endpoint keeps its existing subscription — `AudioObjectAddPropertyListenerBlock`
    /// on the same (deviceID, queue, block) triple is not idempotent, so we never
    /// re-subscribe unless the endpoint genuinely disappears and comes back.
    private func syncSubscriptions(to endpoints: Set<AudioDeviceID>) {
        for endpointID in endpoints where subscriptions[endpointID] == nil {
            subscribe(endpointID: endpointID)
        }
        for endpointID in subscriptions.keys where !endpoints.contains(endpointID) {
            unsubscribe(endpointID: endpointID)
        }
    }

    private func subscribe(endpointID: AudioDeviceID) {
        let address = BluetoothListeningModeProperty.address(
            BluetoothListeningModeProperty.listeningMode
        )
        let queue = listenerQueue
        // The block only hops to the MainActor — the presentation is mutated there,
        // so nothing else is captured. `weak self` keeps CoreAudio from holding the
        // controller alive past the panel's lifetime; a nil self simply no-ops.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleExternalChange(endpointID: endpointID)
            }
        }
        let status = listenerBackend.addListener(
            deviceID: endpointID,
            address: address,
            queue: queue,
            block: block
        )
        guard status == noErr else { return }
        subscriptions[endpointID] = BluetoothListeningModeSubscription(
            deviceID: endpointID,
            address: address,
            queue: queue,
            block: block
        )
    }

    private func unsubscribe(endpointID: AudioDeviceID) {
        guard let subscription = subscriptions.removeValue(forKey: endpointID) else { return }
        _ = listenerBackend.removeListener(
            deviceID: subscription.deviceID,
            address: subscription.address,
            queue: subscription.queue,
            block: subscription.block
        )
    }

    /// Publishes the device's current `lstm` value after a signal from CoreAudio.
    ///
    /// Guards on `previewMode` (preview never subscribes, but the seam could fire
    /// during a real→preview flip that races the unsubscribe), on the endpoint
    /// still mapping to a live address, and on the presentation not being in-flight
    /// — while our own write is still reconciling, the read-back path owns the
    /// state and an external signal must not overwrite it.
    private func handleExternalChange(endpointID: AudioDeviceID) {
        if previewMode { return }
        guard let address = address(forEndpoint: endpointID),
              let presentation = presentations[address] else {
            return
        }
        if presentation.isChanging { return }

        let observed = hal.currentMode(for: endpointID)
        let resolved = observed.flatMap { presentation.availableModes.contains($0) ? $0 : nil }
        presentations[address] = presentation.settled(on: resolved)
    }

    // MARK: - Reconciliation

    private func apply(
        _ result: BluetoothListeningModeWriteResult,
        of mode: BluetoothListeningMode,
        to previous: BluetoothListeningModePresentation,
        at address: String,
        endpointID: AudioDeviceID
    ) {
        changeTasks[address] = nil
        switch result {
        case .confirmed(let settled):
            presentations[address] = previous.settled(on: settled)
        case .unconfirmed(let observed):
            // The control surface never settled on the target. Fall back to whatever
            // it now reports — never to the requested mode — and flag it briefly.
            showFailure(observed, previous: previous, at: address)
        case .failed:
            // Re-read the live mode so the rollback reflects the device, not the tap.
            let observed = hal.currentMode(for: endpointID).flatMap { previous.availableModes.contains($0) ? $0 : nil }
            showFailure(observed, previous: previous, at: address)
        }
    }

    /// Marks the control failed at `observed` for a moment, then returns to idle, so
    /// a failed switch is visible without leaving the row stuck.
    private func showFailure(
        _ observed: BluetoothListeningMode?,
        previous: BluetoothListeningModePresentation,
        at address: String
    ) {
        let failed = BluetoothListeningModePresentation(
            availableModes: previous.availableModes,
            selectedMode: observed,
            actionState: .failed
        )
        presentations[address] = failed
        let generation = bumpGeneration(for: address)

        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = Task { [weak self, delay = self.failureClearDelay] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.generations[address] == generation,
                  case .failed = self.presentations[address]?.actionState else { return }
            self.presentations[address] = self.presentations[address]?.settledAfterFailure() ?? failed
            self.failureClearTasks[address] = nil
        }
    }

    // MARK: - Task / generation bookkeeping

    private func cancelTasks(for address: String) {
        changeTasks[address]?.cancel()
        changeTasks[address] = nil
        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = nil
    }

    @discardableResult
    private func bumpGeneration(for address: String) -> UInt64 {
        let next = (generations[address] ?? 0) &+ 1
        generations[address] = next
        return next
    }
}
