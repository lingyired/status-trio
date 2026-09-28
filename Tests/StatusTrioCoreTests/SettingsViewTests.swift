import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsViewDimensionsAndSections() {
        XCTAssertEqual(SettingsView.Section.allCases.count, 8)
        XCTAssertEqual(SettingsView.sidebarWidth, 190)
        XCTAssertEqual(SettingsView.width, 720)
        XCTAssertEqual(SettingsView.height, 530)
    }

    func testSidebarListsEveryStatusElementBeforeTheAppWidePanes() {
        XCTAssertEqual(
            SettingsView.Section.allCases,
            [.appIcon, .battery, .network, .bluetooth, .audio, .popover, .general, .about]
        )
        XCTAssertEqual(SettingsView.Section.allCases.first, .appIcon)
    }

    func testStatusElementPanesRenderWithoutCrashing() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)
        let statusStore = makeStatusStore()
        let isDark = Binding.constant(true)

        let panes: [(String, AnyView)] = [
            ("appIcon", AnyView(AppIconSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark,
                onShowIconGuide: {}
            ))),
            ("battery", AnyView(BatterySectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("network", AnyView(NetworkSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("bluetooth", AnyView(BluetoothSectionView(
                store: store,
                statusStore: statusStore,
                bluetoothDevices: statusStore.bluetoothDevices,
                previewIsDark: isDark
            ))),
            ("audio", AnyView(AudioSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("popover", AnyView(PopoverSectionView(
                store: store,
                statusStore: statusStore
            )))
        ]

        for (name, pane) in panes {
            let hostingView = NSHostingView(
                rootView: pane
                    .environmentObject(localization)
                    .environmentObject(ChargingEffectClock())
            )
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: SettingsView.width - SettingsView.sidebarWidth,
                height: SettingsView.height
            )
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertNotNil(hostingView.subviews, "\(name) pane should host")
        }
    }

    func testBatteryActionChoiceModelIncludesInstalledAndSelectedUnavailableApps() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let selectedMissing = BatteryActionSettingsView.choices(
            current: .knownApp(.alDente),
            installed: []
        )
        XCTAssertTrue(selectedMissing.contains(.systemSettings))
        XCTAssertTrue(selectedMissing.contains(.knownApp(.alDente)))
        XCTAssertFalse(selectedMissing.contains(.knownApp(.batFi)))
        XCTAssertTrue(selectedMissing.contains(.customApplication))
        XCTAssertTrue(selectedMissing.contains(.customURL))

        let availableAlDente = BatteryActionSettingsView.choices(
            current: .systemSettings,
            installed: [.alDente]
        )
        XCTAssertTrue(availableAlDente.contains(.knownApp(.alDente)))
        XCTAssertFalse(availableAlDente.contains(.knownApp(.batFi)))

        XCTAssertEqual(
            BatteryActionSettingsView.unavailableMessage(
                for: .knownApp(.alDente),
                installed: [],
                customApplicationAvailable: true,
                localization: localization
            ),
            "AlDente: \(localization.string(.batteryActionUnavailable))"
        )
    }

    func testBatteryActionSettingsPreserveUnavailableCustomNameAndIgnorePanelCancellation() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)
        let target = BatteryActionTarget.customApp(.init(
            displayName: "Saved Charging Tool",
            bundleIdentifier: nil,
            fallbackPath: nil
        ))
        store.batteryActionTarget = target

        XCTAssertEqual(
            BatteryActionPresentation.selectionName(for: target, localization: localization),
            "Saved Charging Tool"
        )
        XCTAssertEqual(
            BatteryActionSettingsView.unavailableMessage(
                for: target,
                installed: [],
                customApplicationAvailable: false,
                localization: localization
            ),
            "Saved Charging Tool: \(localization.string(.batteryActionUnavailable))"
        )

        BatteryActionSettingsView.applySelectedApplication(nil, to: store)

        XCTAssertEqual(store.batteryActionTarget, target)
    }

    func testBatteryActionSettingsRenderInEnglishAndSimplifiedChinese() {
        let suite = makeSuite()
        defer { clear(suite) }

        for language in ["en", "zh-Hans"] {
            let localization = Localization(
                defaults: suite.defaults,
                preferredLanguages: [language]
            )
            let store = SettingsStore(defaults: suite.defaults)
            let view = BatterySectionView(
                store: store,
                statusStore: makeStatusStore(),
                previewIsDark: .constant(true),
                launcher: BatteryActionLauncher(workspace: SettingsBatteryWorkspace())
            )
            let hostingView = NSHostingView(
                rootView: view
                    .environmentObject(localization)
                    .environmentObject(ChargingEffectClock())
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 530, height: 530)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertNotNil(hostingView.subviews, "Battery settings should render for \(language)")
            XCTAssertFalse(localization.string(.settingsBatteryActionTitle).isEmpty)
            XCTAssertEqual(
                localization.string(.settingsBatteryActionTitle),
                language == "en" ? "Battery action" : "电池动作"
            )
        }
    }

    func testBatteryActionURLValidationMessageAppearsForEmptyAndInvalidInput() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        XCTAssertEqual(
            BatteryActionSettingsView.invalidURLMessage(for: "", localization: localization),
            localization.string(.batteryActionInvalidURL)
        )
        XCTAssertEqual(
            BatteryActionSettingsView.invalidURLMessage(for: " \n\t ", localization: localization),
            localization.string(.batteryActionInvalidURL)
        )
        XCTAssertNil(
            BatteryActionSettingsView.invalidURLMessage(
                for: "raycast://battery/open",
                localization: localization
            )
        )
        XCTAssertEqual(
            BatteryActionSettingsView.invalidURLMessage(
                for: "example.com/path",
                localization: localization
            ),
            localization.string(.batteryActionInvalidURL)
        )
    }

    func testLongBatteryActionSelectorNameFitsAndKeepsItsFullAccessibilityValue() {
        let suite = makeSuite()
        defer { clear(suite) }

        let longName = "An Extremely Long Battery Charging Utility Name"
        let target = BatteryActionTarget.customApp(.init(
            displayName: longName,
            bundleIdentifier: nil,
            fallbackPath: nil
        ))

        for language in ["en", "zh-Hans"] {
            let localization = Localization(
                defaults: suite.defaults,
                preferredLanguages: [language]
            )
            let selectionName = BatteryActionPresentation.selectionName(
                for: target,
                localization: localization
            )
            let label = BatteryActionTargetSelectorLabel(
                selectionName: selectionName,
                changeTargetLabel: localization.string(.batteryActionChangeTarget)
            )
            let hostingView = NSHostingView(rootView: label)
            hostingView.frame = NSRect(x: 0, y: 0, width: 530, height: 50)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertLessThanOrEqual(hostingView.fittingSize.width, 230, language)
            XCTAssertEqual(label.accessibilityValue, longName, language)
        }
    }

    /// The order list is only reachable when the pane can read paired devices.
    /// The pane used to read `statusStore.bluetoothDevices.devices` without
    /// observing the controller and without activating it, so a fresh launch
    /// that opened Settings rendered "No paired devices available" while
    /// devices were paired. This renders the order list with a non-empty
    /// controller and pins that its non-empty branch really draws.
    func testBluetoothOrderListRendersPairedDevicesFromTheActivatedController() async {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true),
            BluetoothDevice(id: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: false),
            BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "MX Master 3", kind: .peripheral(.mouse), isConnected: false)
        ]
        let controller = SettingsBluetoothTestFactory.makeController(devices: devices)
        controller.activate()
        await waitForDevices(controller)

        XCTAssertEqual(
            controller.devices.count,
            devices.count,
            "the fixture controller must publish its paired devices before the pane renders"
        )

        let emptyStoreController = SettingsBluetoothTestFactory.makeController(devices: [])
        let populated = renderBluetoothPane(
            store: SettingsStore(defaults: suite.defaults),
            storeController: emptyStoreController,
            observedController: controller,
            localization: Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        )
        let empty = renderBluetoothPane(
            store: SettingsStore(defaults: suite.defaults),
            storeController: emptyStoreController,
            observedController: SettingsBluetoothTestFactory.makeController(devices: []),
            localization: Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        )

        XCTAssertGreaterThan(
            populated.height,
            empty.height + 40,
            "the order list must render three device rows, not the empty-state branch "
                + "(populated \(populated.height), empty \(empty.height))"
        )
        controller.deactivate()
    }

    /// The picker under the replace-network-icon toggle: off hides it, on
    /// draws the audio-device row and every classified paired device, and
    /// picking a device records its address and resolved symbol in the store.
    func testBluetoothNetworkIconSourcePickerRendersAndPicksADevice() async {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true),
            BluetoothDevice(id: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: false),
            BluetoothDevice(
                id: "AA:BB:CC:DD:EE:FF",
                name: "Ghost",
                kind: .unknown,
                isConnected: false,
                isUnpairedGhost: true
            )
        ]
        let controller = SettingsBluetoothTestFactory.makeController(devices: devices)
        controller.activate()
        await waitForDevices(controller)
        defer { controller.deactivate() }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)
        let emptyStoreController = SettingsBluetoothTestFactory.makeController(devices: [])

        store.replacesNetworkIconWithBluetoothAudio = false
        let withToggleOff = renderBluetoothPane(
            store: store,
            storeController: emptyStoreController,
            observedController: controller,
            localization: localization
        )
        store.replacesNetworkIconWithBluetoothAudio = true
        let withToggleOn = renderBluetoothPane(
            store: store,
            storeController: emptyStoreController,
            observedController: controller,
            localization: localization
        )

        XCTAssertGreaterThan(
            withToggleOn.height,
            withToggleOff.height + 40,
            "the picker must render the audio-device row and two classified devices "
                + "(on \(withToggleOn.height), off \(withToggleOff.height))"
        )

        // Picking the keyboard device records both halves of the choice; the
        // ghost device never made it into the picker to be picked instead.
        store.setBluetoothNetworkIconDevice(address: "d36d6c40a32e", symbolName: "keyboard")
        XCTAssertEqual(store.bluetoothNetworkIconDeviceAddress, "d36d6c40a32e")
        XCTAssertEqual(store.bluetoothNetworkIconSymbolName, "keyboard")
        XCTAssertEqual(
            store.bluetoothAudioIconOptions.networkIconSymbolOverride,
            "keyboard"
        )
    }

    func testSettingsViewHostingViewRendersWithoutCrashing() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removeTestSuite(named: name) }

        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: defaults)
        let statusStore = SystemStatusStore(
            batteryMonitor: DummyBatteryMonitor(),
            wifiMonitor: DummyWiFiMonitor(),
            volumeMonitor: DummyVolumeMonitor()
        )

        let view = SettingsView(
            store: store,
            statusStore: statusStore,
            localization: localization,
            onShowIconGuide: {}
        )

        let hostingView = NSHostingView(rootView: view.environmentObject(ChargingEffectClock()))
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testSectionTitlesLocalizedForAllLanguages() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removeTestSuite(named: name) }

        for lang in AppLanguage.allCases {
            let localization = Localization(defaults: defaults, preferredLanguages: [lang.rawValue])
            for section in SettingsView.Section.allCases {
                let title = section.title(localization)
                XCTAssertFalse(title.isEmpty, "Section \(section) title should not be empty for \(lang)")
            }
        }
    }
}

@MainActor
private func makeSuite() -> (defaults: UserDefaults, name: String) {
    let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removeTestSuite(named: name)
    return (defaults, name)
}

private func clear(_ suite: (defaults: UserDefaults, name: String)) {
    suite.defaults.removeTestSuite(named: suite.name)
}

@MainActor
private func makeStatusStore() -> SystemStatusStore {
    SystemStatusStore(
        batteryMonitor: DummyBatteryMonitor(),
        wifiMonitor: DummyWiFiMonitor(),
        volumeMonitor: DummyVolumeMonitor()
    )
}

@MainActor
private final class SettingsBatteryWorkspace: BatteryWorkspace {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func fileExists(at url: URL) -> Bool { false }
    func openURL(_ url: URL) -> Bool { false }
    func openApplication(_ url: URL) async throws {}
}

/// A `BluetoothDeviceController` whose paired-device read answers with the
/// fixture and whose monitor already holds the grant, so `activate()` starts
/// the monitor without a permission prompt, exactly as the granted app does.
@MainActor
private enum SettingsBluetoothTestFactory {
    static func makeController(devices: [BluetoothDevice]) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: SettingsBluetoothDeviceReaderStub(result: .success(devices)),
            stateMonitor: SettingsBluetoothStateMonitorStub(),
            batteryReader: SettingsBluetoothBatteryReaderStub(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
    }
}

/// Renders the Bluetooth settings pane into a hosting view and returns the size
/// its own content needs at the pane's real width.
///
/// `storeController` and `observedController` are deliberately two different
/// controllers: the pane renders the one it observes, while the store keeps an
/// empty one, so a pane that fell back to `statusStore.bluetoothDevices` would
/// still draw the empty branch.
@MainActor
private func renderBluetoothPane(
    store: SettingsStore,
    storeController: BluetoothDeviceController,
    observedController: BluetoothDeviceController,
    localization: Localization
) -> NSSize {
    let statusStore = SystemStatusStore(
        batteryMonitor: DummyBatteryMonitor(),
        wifiMonitor: DummyWiFiMonitor(),
        volumeMonitor: DummyVolumeMonitor(),
        bluetoothDevices: storeController
    )
    let pane = BluetoothSectionView(
        store: store,
        statusStore: statusStore,
        bluetoothDevices: observedController,
        previewIsDark: .constant(true)
    )
    .environmentObject(localization)
    .environmentObject(ChargingEffectClock())

    let hosting = NSHostingView(rootView: pane)
    hosting.frame = NSRect(
        x: 0,
        y: 0,
        width: SettingsView.width - SettingsView.sidebarWidth,
        height: SettingsView.height
    )
    hosting.layoutSubtreeIfNeeded()
    return hosting.fittingSize
}

@MainActor
private func waitForDevices(_ controller: BluetoothDeviceController) async {
    for _ in 0..<1_000 {
        if !controller.devices.isEmpty { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

private final class SettingsBluetoothDeviceReaderStub: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(result)
    }
}

private final class SettingsBluetoothBatteryReaderStub: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class SettingsBluetoothStateMonitorStub: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(authorization, .poweredOn)
    }

    func stop() {}
}

@MainActor
private final class DummyBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class DummyWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class DummyVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
