import XCTest
@testable import StatusTrioCore

@MainActor
final class InputSourceSettingsTests: XCTestCase {
    func testCenterSourceDefaultsToAutomaticAndNetworkWarningsStayOn() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(store.connectionCenterSource, .automatic)
        XCTAssertTrue(store.prioritizesNetworkErrorsOverInputSource)
        XCTAssertEqual(store.connectionIconOptions.centerSource, .automatic)
        XCTAssertTrue(store.connectionIconOptions.prioritizesNetworkErrorsOverInputSource)
    }

    func testUnknownStoredSourceDecodesToAutomatic() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "some-future-mode",
            forKey: SettingsStore.connectionCenterSourceDefaultsKey
        )

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).connectionCenterSource, .automatic)
    }

    func testChoicesPersistAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.connectionCenterSource = .inputSource
        first.prioritizesNetworkErrorsOverInputSource = false

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.connectionCenterSource, .inputSource)
        XCTAssertFalse(second.prioritizesNetworkErrorsOverInputSource)
    }

    func testAStoredPanelListGainsTheSectionWithoutEnablingIt() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            ["volume", "battery"],
            forKey: SettingsStore.popupSectionOrderDefaultsKey
        )
        suite.defaults.set(
            ["volume", "battery"],
            forKey: SettingsStore.enabledPopupSectionsDefaultsKey
        )
        // Keep this test about the input-source row: the one-shot VPN migration
        // has its own coverage in `VPNRowSettingsTests`.
        suite.defaults.set(true, forKey: SettingsStore.vpnPopupSectionIntroducedDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(store.popupSectionOrder.last, .inputSource)
        XCTAssertEqual(store.popupSectionOrder.first, .volume)
        XCTAssertFalse(store.enabledPopupSections.contains(.inputSource))
        XCTAssertEqual(store.visiblePopupSections, [.volume, .battery])
    }

    func testFreshInstallKeepsTheInputSourceRowHidden() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.enabledPopupSections.contains(.inputSource))
        XCTAssertFalse(store.visiblePopupSections.contains(.inputSource))
        XCTAssertTrue(store.popupSectionOrder.contains(.inputSource))
    }
}

/// The panel section's own store wiring: the row is drawn from the live
/// controller and clicking it routes through `StatusPanelActions`.
@MainActor
final class InputSourcePanelTests: XCTestCase {
    func testPanelRowsMirrorTheControllerStateAndMarkTheCurrentSource() {
        let controller = makeController(
            current: "com.example.pinyin",
            sources: [abcRaw, pinyinRaw]
        )
        controller.start()

        let state = InputSourcePanelMapper.map(
            state: controller.state,
            failure: nil,
            localization: makeLocalization()
        )

        XCTAssertEqual(state.rows.map(\.id), [abcRaw.id, pinyinRaw.id])
        XCTAssertEqual(state.rows.map(\.isCurrent), [false, true])
        XCTAssertEqual(state.currentName, "Example 拼音")
        XCTAssertNil(state.emptyMessage)
    }

    func testEmptyStateCarriesAnExplicitMessageInsteadOfAnEmptyList() {
        let controller = makeController(current: nil, sources: [])
        controller.start()

        let state = InputSourcePanelMapper.map(
            state: controller.state,
            failure: nil,
            localization: makeLocalization()
        )

        XCTAssertTrue(state.rows.isEmpty)
        XCTAssertNil(state.currentName)
        XCTAssertNotNil(state.emptyMessage)
    }

    func testDuplicateNamesKeepTheirUniqueIDs() {
        let duplicateA = RawInputSource(
            id: "com.example.a",
            localizedName: "Same Name",
            languages: [],
            iconImageURL: nil,
            isEnabled: true,
            isSelectCapable: true
        )
        let duplicateB = RawInputSource(
            id: "com.example.b",
            localizedName: "Same Name",
            languages: [],
            iconImageURL: nil,
            isEnabled: true,
            isSelectCapable: true
        )
        let state = InputSourceState.resolved(selectedID: duplicateA.id, rawSources: [duplicateA, duplicateB])

        let panel = InputSourcePanelMapper.map(
            state: state,
            failure: nil,
            localization: makeLocalization()
        )

        XCTAssertEqual(panel.rows.map(\.id), ["com.example.a", "com.example.b"])
        XCTAssertEqual(panel.rows.map(\.name), ["Same Name", "Same Name"])
        XCTAssertEqual(panel.rows.map(\.isCurrent), [true, false])
    }

    func testFailureTextNamesTheTargetAndSeparatesUnconfirmedFromFailed() {
        let unconfirmed = InputSourcePanelMapper.map(
            state: InputSourceState.resolved(selectedID: abcRaw.id, rawSources: [abcRaw, pinyinRaw]),
            failure: InputSourceController.SelectionFailure(
                sourceID: pinyinRaw.id,
                reason: .notConfirmed
            ),
            localization: makeLocalization()
        )
        let refused = InputSourcePanelMapper.map(
            state: InputSourceState.resolved(selectedID: abcRaw.id, rawSources: [abcRaw, pinyinRaw]),
            failure: InputSourceController.SelectionFailure(
                sourceID: pinyinRaw.id,
                reason: .systemRefused(osStatus: -50)
            ),
            localization: makeLocalization()
        )

        XCTAssertNotEqual(unconfirmed.failureText, refused.failureText)
        XCTAssertTrue(unconfirmed.failureText?.contains("Example 拼音") == true)
        XCTAssertTrue(refused.failureText?.contains("Example 拼音") == true)
    }

    func testActionRoutingForwardsTheSelectedID() {
        var selected: [String] = []
        let actions = StatusPanelActions(selectInputSource: { selected.append($0) })

        actions.selectInputSource("com.example.pinyin")

        XCTAssertEqual(selected, ["com.example.pinyin"])
    }

    func testConvenienceActionsRouteToTheController() {
        let controller = makeController(current: abcRaw.id, sources: [abcRaw, pinyinRaw])
        controller.start()
        let store = SystemStatusStore(
            batteryMonitor: PanelSourceBatteryMonitor(),
            wifiMonitor: PanelSourceWiFiMonitor(),
            volumeMonitor: PanelSourceVolumeMonitor()
        )
        let actions = StatusPanelActions(
            store: store,
            settings: SettingsStore(defaults: makeSuite().defaults),
            inputSourceController: controller
        )

        actions.selectInputSource(pinyinRaw.id)

        XCTAssertEqual(controller.state.selectedID, pinyinRaw.id)
    }

    private var abcRaw: RawInputSource {
        RawInputSource(
            id: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            languages: ["en"],
            iconImageURL: nil,
            isEnabled: true,
            isSelectCapable: true
        )
    }

    private var pinyinRaw: RawInputSource {
        RawInputSource(
            id: "com.example.pinyin",
            localizedName: "Example 拼音",
            languages: ["zh-Hans"],
            iconImageURL: nil,
            isEnabled: true,
            isSelectCapable: true
        )
    }

    private func makeController(
        current: String?,
        sources: [RawInputSource]
    ) -> InputSourceController {
        let reader = PanelSourceReader(current: current, sources: sources)
        return InputSourceController(
            reader: reader,
            switcher: ReaderMutatingSwitcher(reader: reader),
            notifications: PanelSourceNotifications(),
            confirmationScheduler: PanelSourceConfirmationScheduler()
        )
    }

    private func makeLocalization() -> Localization {
        let suite = makeSuite()
        addTeardownBlock { clear(suite) }
        return Localization(defaults: suite.defaults, preferredLanguages: ["en"])
    }
}

private final class PanelSourceReader: InputSourceReading {
    var current: String?
    var sources: [RawInputSource]

    init(current: String?, sources: [RawInputSource]) {
        self.current = current
        self.sources = sources
    }

    func currentKeyboardInputSourceID() -> String? { current }
    func keyboardInputSources() -> [RawInputSource] { sources }
}

/// Applies the selection to the reader, so the flow exercises the real read
/// path instead of a stub's promise.
private final class ReaderMutatingSwitcher: InputSourceSwitching {
    private let reader: PanelSourceReader

    init(reader: PanelSourceReader) {
        self.reader = reader
    }

    func select(id: String) -> InputSourceSelectionResult {
        reader.current = id
        return .selected
    }
}

@MainActor
private final class PanelSourceNotifications: InputSourceNotificationObserving {
    func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NSObject()
    }

    func remove(_ token: NSObjectProtocol) {}
}

@MainActor
private final class PanelSourceConfirmationScheduler: InputSourceConfirmationScheduling {
    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

@MainActor
private final class PanelSourceBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { continuation in
        continuation.finish()
    }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class PanelSourceWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { continuation in
        continuation.finish()
    }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class PanelSourceVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { continuation in
        continuation.finish()
    }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private func makeSuite() -> (defaults: UserDefaults, name: String) {
    let name = "StatusTrioCoreTests.InputSourceSettings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removeTestSuite(named: name)
    return (defaults, name)
}

private func clear(_ suite: (defaults: UserDefaults, name: String)) {
    suite.defaults.removeTestSuite(named: suite.name)
}
