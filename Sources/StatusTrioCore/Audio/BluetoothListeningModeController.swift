import Combine
import CoreAudio
import Foundation

/// Owns the Bluetooth listening-mode surface for the Bluetooth panel's visible
/// lifetime.
///
/// AirPods expose their modes through CoreAudio's private `lstm`/`lsms`
/// properties; HUAWEI FreeBuds-family devices expose the same three states
/// (off, cancellation, transparency) over a vendor SPP channel. The CoreAudio
/// path keeps its original discovery/write/read-back rules; the HUAWEI path adds
/// a transport and an endpoint resolver behind separate seams, so neither
/// device family changes the other's guarantees.
///
/// It is deliberately a separate object from `BluetoothDeviceController` (the plan's
/// Option B): the paired-device controller is a large, carefully-synchronised
/// lifecycle owner, and this subsystem — bounded discovery on panel open, one write
/// per tap, a short read-back — is simpler to reason about and to test on its own. The
/// view holds both and drives this one from the same appear/disappear and refresh
/// hooks the device list already uses.
///
/// The guarantees that matter live here and are covered by tests: discovery runs
/// only on visible-surface demand with finite readiness retries, capabilities are
/// keyed by the normalized Bluetooth address so a rename or a re-pair cannot
/// strand a stale control, a write is confirmed by read-back rather than assumed,
/// and a failure rolls the UI back to what the device actually reports.
@MainActor
final class BluetoothListeningModeController: ObservableObject {
    /// The control state per connected, eligible device, keyed by the same
    /// normalized address the battery levels use. Absence means "no control".
    @Published private(set) var presentations: [String: BluetoothListeningModePresentation] = [:]

    private let hal: BluetoothListeningModeHAL
    private let endpointProvider: any CoreAudioBluetoothEndpointProviding
    private let airPodsDiscoveryRetryDelays: [Duration]
    private let airPodsDiscoverySleep: @Sendable (Duration) async throws -> Void
    private var airPodsDiscoveryTask: Task<Void, Never>?
    private var airPodsDiscoveryToken: DeviceOperationToken?
    private let failureClearDelay: Duration
    /// How long a preview write shows its spinner before settling. Real writes
    /// settle when the read-back confirms, which is CoreAudio-bound; preview
    /// writes settle on a fixed delay so the busy state is visible without
    /// waiting on anything.
    private let previewSettleDelay: Duration

    /// Interface-preview mode. When true, `refresh` publishes synthetic
    /// presentations for connected AirPods without consulting the HAL or
    /// endpoint mapper. HUAWEI devices remain live and continue through SPP;
    /// preview toggles never redirect vendor writes to an in-memory selection.
    /// Preview is set from Settings and cleared on the next refresh after the
    /// toggle is turned off.
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
    /// One token per active address, so a cancelled or superseded write's
    /// completion cannot touch the presentation the next refresh published.
    private var changeTokens: [String: DeviceOperationToken] = [:]

    /// The `lstm` property listener seam. The controller subscribes per resolved
    /// endpoint in `refresh` and clears them in `stop`, so an external mode change
    /// (the stem, Control Center, another Mac, Siri) reflects here without waiting
    /// for the panel to reopen or for the user to tap. Preview mode never touches
    /// the seam — synthetic rows have no device to listen to.
    private let listenerBackend: (any BluetoothListeningModePropertyListening)?

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

    /// HUAWEI devices do not expose the CoreAudio `lstm` property; their noise
    /// control lives on a vendor SPP channel. The transport and endpoint resolver
    /// are separate seams so the CoreAudio path keeps its existing guarantees.
    private let huaweiTransport: any HuaweiListeningModeTransporting
    private let huaweiEndpointProvider: any HuaweiAudioEndpointProviding
    private let huaweiFirstReadRetryDelays: [Duration]
    /// Addresses whose controls are backed by the HUAWEI transport. `setMode`
    /// branches on this rather than re-reading the device.
    private var huaweiAddresses: Set<String> = []
    /// One in-flight state read per device, so repeated panel refreshes do not
    /// stack queries on the same channel. The token identifies the task that owns
    /// the dictionary slot, so a cancelled read cannot clear a newer one, and it
    /// invalidates the read it replaced, so a superseded read cannot publish.
    private var huaweiRefreshTasks: [String: Task<Void, Never>] = [:]
    private var huaweiReadTokens: [String: DeviceOperationToken] = [:]

    init(
        hal: BluetoothListeningModeHAL = BluetoothListeningModeHAL(),
        endpointProvider: (any CoreAudioBluetoothEndpointProviding)? = nil,
        listenerBackend: (any BluetoothListeningModePropertyListening)? = nil,
        huaweiTransport: any HuaweiListeningModeTransporting = HuaweiRFCOMMTransport(),
        huaweiEndpointProvider: any HuaweiAudioEndpointProviding = CoreAudioHuaweiAudioEndpointProvider(),
        huaweiReadRetryDelays: [Duration] = [.milliseconds(150), .milliseconds(450)],
        airPodsDiscoveryRetryDelays: [Duration] = [.milliseconds(150), .milliseconds(450), .seconds(1)],
        airPodsDiscoverySleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        failureClearDelay: Duration = .seconds(2),
        previewSettleDelay: Duration = .milliseconds(400)
    ) {
        self.hal = hal
        self.endpointProvider = endpointProvider ?? UnavailableBluetoothListeningModeEndpointProvider()
        self.listenerBackend = listenerBackend
        self.huaweiTransport = huaweiTransport
        self.huaweiEndpointProvider = huaweiEndpointProvider
        self.huaweiFirstReadRetryDelays = huaweiReadRetryDelays
        self.airPodsDiscoveryRetryDelays = airPodsDiscoveryRetryDelays
        self.airPodsDiscoverySleep = airPodsDiscoverySleep
        self.failureClearDelay = failureClearDelay
        self.previewSettleDelay = previewSettleDelay
    }

    /// Discovers controls for connected devices while a panel surface is visible.
    /// AirPods require a resolved CoreAudio endpoint. HUAWEI devices use their
    /// Bluetooth address and SPP transport, so their control remains available
    /// in the paired-device row when macOS has not opened an audio route.
    /// Preview mode substitutes only the AirPods surface; live HUAWEI discovery
    /// and writes remain active while previews are enabled.
    func refresh(devices: [BluetoothDevice]) {
        cancelAirPodsDiscovery()
        if previewMode {
            refreshPreview(devices: devices)
            return
        }
        let needsRetry = refreshAirPods(devices: devices)
        refreshHuawei(devices: devices)
        if needsRetry { retryAirPodsDiscovery(devices: devices) }
    }

    private func refreshAirPods(devices: [BluetoothDevice]) -> Bool {
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

        let airPodsEndpointIDs = Set(nextResolved.values)
        preserveHuaweiPresentations(in: &next, endpoints: &nextResolved, devices: devices)

        // Anything no longer resolved has its tasks cancelled and its token
        // retired, so a late completion cannot resurrect it. HUAWEI addresses are
        // handled by `refreshHuawei` below, which owns their tasks.
        for address in presentations.keys where next[address] == nil && !huaweiAddresses.contains(address) {
            cancelTasks(for: address)
            retireChangeToken(for: address)
        }

        presentations = next
        resolvedEndpoints = nextResolved
        // A real refresh invalidates every preview selection: preview state must
        // never leak back onto the live control surface after the toggle is off.
        previewSelectedModes.removeAll()
        syncSubscriptions(to: airPodsEndpointIDs)
        return eligible.count == 1 && airPodsEndpointIDs.isEmpty
    }

    /// CoreAudio can publish the Bluetooth connection before its mode properties
    /// are ready. Retry only this discovery, never HUAWEI reads or device writes.
    private func retryAirPodsDiscovery(devices: [BluetoothDevice]) {
        guard !airPodsDiscoveryRetryDelays.isEmpty else { return }
        let token = DeviceOperationToken()
        airPodsDiscoveryToken = token
        let delays = airPodsDiscoveryRetryDelays
        let sleep = airPodsDiscoverySleep
        airPodsDiscoveryTask = Task { [weak self] in
            for delay in delays {
                do {
                    try await sleep(delay)
                } catch {
                    break
                }
                guard !Task.isCancelled, let self,
                      self.airPodsDiscoveryToken == token, !self.previewMode else { return }
                if !self.refreshAirPods(devices: devices) { break }
            }
            guard let self, self.airPodsDiscoveryToken == token else { return }
            self.airPodsDiscoveryTask = nil
            self.airPodsDiscoveryToken = nil
        }
    }

    private func cancelAirPodsDiscovery() {
        airPodsDiscoveryTask?.cancel()
        airPodsDiscoveryTask = nil
        airPodsDiscoveryToken = nil
    }

    /// Discovers HUAWEI controls by Bluetooth address and reads their current
    /// mode over SPP. CoreAudio output endpoint resolution is optional: it only
    /// chooses whether the capsules appear on the volume row or as a fallback on
    /// the connected Bluetooth-device row.
    private func refreshHuawei(devices: [BluetoothDevice]) {
        let eligible = devices.filter {
            $0.isConnected && $0.isHuaweiAudio && !$0.id.hasPrefix(Self.previewAddressPrefix)
        }
        let addresses = Set(eligible.map { BluetoothBatteryReader.normalizedAddress($0.id) })
            .filter { !$0.isEmpty }
        let removed = huaweiAddresses.subtracting(addresses)

        for address in removed {
            huaweiRefreshTasks[address]?.cancel()
            huaweiRefreshTasks[address] = nil
            huaweiReadTokens[address] = nil
            cancelTasks(for: address)
            retireChangeToken(for: address)
            presentations[address] = nil
            resolvedEndpoints[address] = nil
        }
        huaweiAddresses = addresses

        for device in eligible {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty else { continue }
            let endpointID = huaweiEndpointProvider.endpointID(for: device)
            resolvedEndpoints[address] = endpointID

            // A write owns the presentation until its read-back settles; a
            // concurrent discovery read would race that result.
            if presentations[address]?.isChanging == true { continue }
            if huaweiRefreshTasks[address] != nil { continue }

            let token = DeviceOperationToken()
            huaweiReadTokens[address] = token
            huaweiRefreshTasks[address] = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.huaweiReadTokens[address] == token {
                        self.huaweiRefreshTasks[address] = nil
                        self.huaweiReadTokens[address] = nil
                    }
                }
                let delays = self.presentations[address] == nil
                    ? self.huaweiFirstReadRetryDelays
                    : []
                for attempt in 0...delays.count {
                    do {
                        let state = try await self.huaweiTransport.state(address: address)
                        guard !Task.isCancelled,
                              self.huaweiReadTokens[address] == token,
                              self.huaweiAddresses.contains(address),
                              self.presentations[address]?.isChanging != true else {
                            return
                        }
                        self.presentations[address] = BluetoothListeningModePresentation(
                            availableModes: HuaweiNoiseState.selectableListeningModes,
                            selectedMode: state.listeningMode
                        )
                        return
                    } catch {
                        guard attempt < delays.count else { return }
                        do {
                            try await Task.sleep(for: delays[attempt])
                        } catch {
                            return
                        }
                        guard !Task.isCancelled,
                              self.huaweiReadTokens[address] == token,
                              self.huaweiAddresses.contains(address),
                              self.presentations[address]?.isChanging != true else {
                            return
                        }
                    }
                }
            }
        }
    }

    /// Keeps an existing HUAWEI presentation while AirPods or preview rows are
    /// rebuilt. HUAWEI mode state is keyed by Bluetooth address, independent of
    /// whether CoreAudio currently exposes an output endpoint.
    private func preserveHuaweiPresentations(
        in next: inout [String: BluetoothListeningModePresentation],
        endpoints nextEndpoints: inout [String: AudioDeviceID],
        devices: [BluetoothDevice]
    ) {
        for device in devices where device.isConnected && device.isHuaweiAudio
            && !device.id.hasPrefix(Self.previewAddressPrefix) {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty, huaweiAddresses.contains(address) else { continue }
            if let presentation = presentations[address] {
                next[address] = presentation
            }
            if let endpointID = resolvedEndpoints[address] {
                nextEndpoints[address] = endpointID
            }
        }
    }


    /// The preview-side refresh. AirPods and synthetic rows get in-memory
    /// presentations; HUAWEI devices stay on the real SPP path.
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
            if let endpoint = Self.syntheticEndpoint(for: device.id) {
                nextEndpoints[address] = endpoint
            }
        }

        preserveHuaweiPresentations(in: &next, endpoints: &nextEndpoints, devices: devices)
        // HUAWEI addresses are owned by `refreshHuawei` below, exactly as they
        // are in the live path: a preview refresh must not cancel a vendor write
        // whose SPP frame has already gone out.
        for address in presentations.keys where next[address] == nil
            && !huaweiAddresses.contains(address) {
            cancelTasks(for: address)
            retireChangeToken(for: address)
        }

        presentations = next
        resolvedEndpoints = nextEndpoints
        syncSubscriptions(to: [])
        refreshHuawei(devices: devices)
    }

    /// Asks a device to switch to `mode`, publishing the in-flight state and
    /// reconciling the result against the read-back. Preview writes stay in memory;
    /// live HUAWEI writes always use SPP, including while AirPods preview is enabled.
    func setMode(_ mode: BluetoothListeningMode, for device: BluetoothDevice) {
        setMode(mode, forAddress: BluetoothBatteryReader.normalizedAddress(device.id))
    }

    /// The address-driven entry point. The originating row identifies the device;
    /// the controller keeps vendor writes and CoreAudio writes on their own paths.
    func setMode(_ mode: BluetoothListeningMode, forAddress address: String) {
        if huaweiAddresses.contains(address) {
            setHuaweiMode(mode, forAddress: address)
            return
        }
        if previewMode {
            setModePreview(mode, forAddress: address)
            return
        }
        guard var presentation = presentations[address],
              let endpointID = resolvedEndpoints[address],
              presentation.availableModes.contains(mode) else {
            return
        }
        guard !presentation.isChanging, presentation.selectedMode != mode else { return }

        presentation = presentation.changing(to: mode)
        presentations[address] = presentation
        let token = issueChangeToken(for: address)

        changeTasks[address] = Task { [weak self, hal = self.hal] in
            let result = await hal.setMode(mode, for: endpointID)
            guard let self, !Task.isCancelled, self.changeTokens[address] == token else { return }
            self.apply(result, of: mode, to: presentation, at: address, endpointID: endpointID)
        }
    }

    /// The HUAWEI branch of `setMode`. It mirrors the CoreAudio state machine:
    /// publish the spinner, write over SPP, and settle on the state read back by
    /// the transport — never on the requested mode alone. A transport error rolls
    /// back to the last confirmed selection and shows the same failure mark.
    private func setHuaweiMode(_ mode: BluetoothListeningMode, forAddress address: String) {
        guard var presentation = presentations[address],
              presentation.availableModes.contains(mode),
              let noiseMode = HuaweiNoiseState.noiseMode(for: mode) else {
            return
        }
        guard !presentation.isChanging, presentation.selectedMode != mode else { return }

        presentation = presentation.changing(to: mode)
        presentations[address] = presentation
        let token = issueChangeToken(for: address)

        changeTasks[address] = Task { [weak self, transport = self.huaweiTransport] in
            do {
                let state = try await transport.setMode(noiseMode, address: address)
                guard let self, !Task.isCancelled, self.changeTokens[address] == token else { return }
                self.changeTasks[address] = nil
                if state.listeningMode == mode {
                    self.retireChangeToken(for: address)
                    self.presentations[address] = presentation.settled(on: mode)
                } else {
                    self.showFailure(state.listeningMode, previous: presentation, at: address)
                }
            } catch {
                guard let self, !Task.isCancelled, self.changeTokens[address] == token else { return }
                self.changeTasks[address] = nil
                self.showFailure(presentation.selectedMode, previous: presentation, at: address)
            }
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


    /// Presentation for the Bluetooth row, used only when no CoreAudio output
    /// endpoint exists. If there is an endpoint, the volume row remains the sole
    /// visible owner of the listening-mode control.
    func control(
        forBluetoothAddress address: String
    ) -> BluetoothListeningModePresentation? {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard huaweiAddresses.contains(key),
              resolvedEndpoints[key] == nil,
              let presentation = presentations[key],
              presentation.isControllable else {
            return nil
        }
        return presentation
    }


    /// HUAWEI presentations with no audio endpoint; render these under the
    /// corresponding connected Bluetooth row instead of hiding them.
    var huaweiBluetoothRowPresentations: [String: BluetoothListeningModePresentation] {
        huaweiAddresses.reduce(into: [:]) { result, address in
            guard resolvedEndpoints[address] == nil,
                  let presentation = presentations[address],
                  presentation.isControllable else {
                return
            }
            result[address] = presentation
        }
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
        let token = issueChangeToken(for: address)

        changeTasks[address] = Task { [weak self, delay = self.previewSettleDelay] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.changeTokens[address] == token else { return }
            self.previewSelectedModes[address] = mode
            self.presentations[address] = presentation.settled(on: mode)
            self.changeTasks[address] = nil
            self.retireChangeToken(for: address)
        }
    }

    /// Cancels every outstanding observation and clears the surface. The view calls
    /// this when the panel disappears, honouring the plan's "no residual timer or
    /// task once the panel closes".
    func stop() {
        cancelAirPodsDiscovery()
        for address in presentations.keys {
            cancelTasks(for: address)
            retireChangeToken(for: address)
        }
        for address in huaweiAddresses {
            huaweiRefreshTasks[address]?.cancel()
            huaweiReadTokens[address] = nil
        }
        huaweiRefreshTasks.removeAll()
        huaweiReadTokens.removeAll()
        huaweiAddresses.removeAll()
        changeTasks.removeAll()
        failureClearTasks.removeAll()
        presentations = [:]
        resolvedEndpoints = [:]
        // The panel is going away; the plan's "no residual timer or task once the
        // panel closes" applies to CoreAudio subscriptions too. `syncSubscriptions`
        // with an empty set removes every registered block.
        syncSubscriptions(to: [])
        huaweiTransport.closeAll()
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
        guard let listenerBackend,
              let address = listenerBackend.listeningModeAddress else { return }
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
        guard let listenerBackend,
              let subscription = subscriptions.removeValue(forKey: endpointID) else { return }
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
        defer {
            if case .confirmed = result {
                retireChangeToken(for: address)
            }
        }
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
        let token = issueChangeToken(for: address)

        failureClearTasks[address] = Task { [weak self, delay = self.failureClearDelay] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.changeTokens[address] == token,
                  case .failed = self.presentations[address]?.actionState else { return }
            self.presentations[address] = self.presentations[address]?.settledAfterFailure() ?? failed
            self.failureClearTasks[address] = nil
            self.retireChangeToken(for: address)
        }
    }

    // MARK: - Task / token bookkeeping

    private func cancelTasks(for address: String) {
        changeTasks[address]?.cancel()
        changeTasks[address] = nil
        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = nil
    }

    @discardableResult
    private func issueChangeToken(for address: String) -> DeviceOperationToken {
        let token = DeviceOperationToken()
        changeTasks[address]?.cancel()
        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = nil
        changeTokens[address] = token
        return token
    }

    private func retireChangeToken(for address: String) {
        changeTokens.removeValue(forKey: address)
    }

    var activeChangeTokenCount: Int {
        changeTokens.count
    }

    func activeChangeTokenSnapshot(forAddress address: String) -> DeviceOperationToken? {
        changeTokens[BluetoothBatteryReader.normalizedAddress(address)]
    }
}
