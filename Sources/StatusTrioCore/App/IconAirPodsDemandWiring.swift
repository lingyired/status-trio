import Combine
import Foundation

/// The Bluetooth capabilities the AirPods ring demand needs. Abstracted so the
/// wiring can be driven by a spy in tests without a live CoreBluetooth stack.
@MainActor
protocol IconAirPodsBluetoothDemandSource: AnyObject {
    var devices: [BluetoothDevice] { get }
    var devicesPublisher: AnyPublisher<[BluetoothDevice], Never> { get }
    var batteryLevelsPublisher: AnyPublisher<[String: BluetoothBatteryLevel], Never> { get }
    var batteryLevelsUpdatedAtPublisher: AnyPublisher<Date?, Never> { get }
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> { get }

    @discardableResult
    func requestActivation(_ token: String) -> Bool
    func releaseActivation(_ token: String)
    func requestBackgroundBatteryLevels(_ token: String)
    func releaseBackgroundBatteryLevels(_ token: String)
}

extension BluetoothDeviceController: IconAirPodsBluetoothDemandSource {
    var devicesPublisher: AnyPublisher<[BluetoothDevice], Never> { $devices.eraseToAnyPublisher() }
    var batteryLevelsPublisher: AnyPublisher<[String: BluetoothBatteryLevel], Never> { $batteryLevels.eraseToAnyPublisher() }
    var batteryLevelsUpdatedAtPublisher: AnyPublisher<Date?, Never> { $batteryLevelsUpdatedAt.eraseToAnyPublisher() }
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> { $availability.eraseToAnyPublisher() }
}

/// Keeps the Bluetooth owner claims an AirPods battery ring needs while it is
/// on screen.
///
/// The icon is always visible, so a ring sourced from the AirPods battery needs
/// the accessory level read in the background. The panel-only read that happens
/// while Bluetooth settings are open is not enough: without a background owner
/// the level ages out after `AirPodsBatteryIconSnapshot.freshnessInterval` and
/// the ring falls back to the Mac battery, which is the reported "selected but
/// does not take effect" bug.
///
/// The claim follows the *live* icon configuration (the same snapshot the scene
/// renders from), not the resolved demand: an AirPods ring that has gone stale
/// resolves to its Mac-battery fallback, and demand-based wiring would then drop
/// the very claim needed to refresh it.
///
/// Reconciling is coalesced to one pass per main-actor turn so a burst of
/// settings writes that ends in the "off" state never claims or reads anything.
@MainActor
final class IconAirPodsDemandWiring {
    private let settings: SettingsStore
    private let bluetooth: IconAirPodsBluetoothDemandSource
    private let onBluetoothDemandChange: (Bool) -> Void
    private let onRefresh: () -> Void

    private var bridge = IconSourceDemandBridge()
    private var latestPresentation: IconPresentationSettings?
    private var cancellables = Set<AnyCancellable>()
    private var isReconcileScheduled = false
    private var started = false

    init(
        settings: SettingsStore,
        bluetooth: IconAirPodsBluetoothDemandSource,
        onBluetoothDemandChange: @escaping (Bool) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.bluetooth = bluetooth
        self.onBluetoothDemandChange = onBluetoothDemandChange
        self.onRefresh = onRefresh
    }

    func start() {
        guard !started else { return }
        started = true

        // The live presentation snapshot carries the V1 configuration and slot
        // bindings the scene is rendered from, including a change made through
        // the settings surface (`outerRingContent`).
        settings.iconPresentationPublisher
            .sink { [weak self] presentation in
                guard let self else { return }
                self.latestPresentation = presentation
                self.scheduleReconcile()
            }
            .store(in: &cancellables)

        // Any of these can change whether a connected AirPods exists, or which
        // one the user selected. Battery levels also drive a repaint so a fresh
        // reading reaches the ring.
        Publishers.MergeMany([
            settings.$_refreshesAirPodsBatteryForIcon.map { _ in () }.eraseToAnyPublisher(),
            settings.$_airPodsIconDeviceAddress.map { _ in () }.eraseToAnyPublisher(),
            bluetooth.devicesPublisher.map { _ in () }.eraseToAnyPublisher(),
            bluetooth.batteryLevelsPublisher.map { _ in () }.eraseToAnyPublisher(),
            bluetooth.batteryLevelsUpdatedAtPublisher.map { _ in () }.eraseToAnyPublisher(),
            bluetooth.availabilityPublisher.map { _ in () }.eraseToAnyPublisher()
        ])
        .sink { [weak self] in
            self?.scheduleReconcile()
        }
        .store(in: &cancellables)
    }

    func stop() {
        guard started else { return }
        started = false
        cancellables.removeAll()
        isReconcileScheduled = false
        onBluetoothDemandChange(false)
        bridge.releaseAll(
            releaseActivation: { [weak self] token in
                self?.bluetooth.releaseActivation(token)
            },
            releaseBatteryLevels: { [weak self] token in
                self?.bluetooth.releaseBackgroundBatteryLevels(token)
            }
        )
    }

    /// Coalesces a burst of input changes into a single reconcile on the next
    /// main-actor turn, so only the final state decides whether to claim.
    private func scheduleReconcile() {
        guard !isReconcileScheduled else { return }
        isReconcileScheduled = true
        Task { @MainActor [weak self] in
            guard let self, self.started else { return }
            self.isReconcileScheduled = false
            self.reconcile()
            self.onRefresh()
        }
    }

    private func reconcile() {
        guard let presentation = latestPresentation else { return }
        let configuration = presentation.iconConfiguration
        // Selecting the AirPods ring is the opt-in: the ring cannot show a live
        // level without a background read, so a separate hidden switch would
        // leave the feature silently broken. The legacy flag still forces the
        // read on when it is set. Read the ring choice from the stored setting
        // rather than the delivered snapshot so a settings write that is still
        // settling cannot be judged on half-updated bindings.
        let needsAirPods = settings.outerRingContent == .airPodsBattery
        // Keep the storage owner in step for every Bluetooth source the icon
        // renders, so the store never tears the controller down under it.
        onBluetoothDemandChange(IconSourceDemandPolicy.requiresBluetoothMonitor(in: configuration))
        bridge.reconcile(
            configuration: configuration,
            userOptedInToBackgroundBattery: settings.refreshesAirPodsBatteryForIcon || needsAirPods,
            bluetoothDevices: bluetooth.devices,
            selectedAirPodsAddress: settings.airPodsIconDeviceAddress,
            requestActivation: { [weak self] token in
                self?.bluetooth.requestActivation(token) ?? false
            },
            releaseActivation: { [weak self] token in
                self?.bluetooth.releaseActivation(token)
            },
            requestBatteryLevels: { [weak self] token in
                self?.bluetooth.requestBackgroundBatteryLevels(token)
            },
            releaseBatteryLevels: { [weak self] token in
                self?.bluetooth.releaseBackgroundBatteryLevels(token)
            }
        )
    }
}
