import XCTest
@testable import StatusTrioCore

/// Covers the persistence and placeholder plumbing that stops the status panel
/// from jumping when it reopens: the layout snapshot model, its bounded
/// `UserDefaults` store, the volume row-height policy, and the mapper giving the
/// volume state a skeleton instead of an empty list.
final class PanelListLayoutSnapshotTests: XCTestCase {
    func testSanitizedClampsHeightsAndCapsRowCount() {
        let snapshot = PanelListLayoutSnapshot(
            rowHeights: [.nan, -3, 500] + Array(repeating: 30, count: 30),
            hasExpansionButton: true,
            showsDeviceList: true
        )

        let sanitized = snapshot.sanitized()

        XCTAssertEqual(sanitized.rowHeights.count, PanelListLayoutSnapshot.maximumRowCount)
        XCTAssertEqual(Array(sanitized.rowHeights.prefix(3)), [0, 0, 400])
        XCTAssertTrue(sanitized.hasExpansionButton)
        XCTAssertTrue(sanitized.showsDeviceList)
    }

    func testSanitizedDropsExpansionWhenThereAreNoRows() {
        let snapshot = PanelListLayoutSnapshot(
            rowHeights: [],
            hasExpansionButton: true,
            showsDeviceList: true
        )

        let sanitized = snapshot.sanitized()

        XCTAssertTrue(sanitized.rowHeights.isEmpty)
        XCTAssertFalse(sanitized.hasExpansionButton)
    }

    func testStoreRoundTripsAndClears() throws {
        let suiteName = "PanelListLayoutSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let store = PanelListLayoutSnapshotStore(defaults: defaults)

        XCTAssertNil(store.snapshot(for: .volume))

        let snapshot = PanelListLayoutSnapshot(
            rowHeights: [30, 52, 30],
            hasExpansionButton: true,
            showsDeviceList: true
        )
        store.save(snapshot, for: .volume)
        XCTAssertEqual(store.snapshot(for: .volume), snapshot)

        store.save(nil, for: .volume)
        XCTAssertNil(store.snapshot(for: .volume))
    }

    func testStoreTreatsAnEmptySnapshotAsAbsent() throws {
        let suiteName = "PanelListLayoutSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let store = PanelListLayoutSnapshotStore(defaults: defaults)

        store.save(
            PanelListLayoutSnapshot(rowHeights: [], hasExpansionButton: false, showsDeviceList: false),
            for: .bluetooth
        )

        XCTAssertNil(store.snapshot(for: .bluetooth))
    }

    func testKeysDoNotCollide() throws {
        let suiteName = "PanelListLayoutSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let store = PanelListLayoutSnapshotStore(defaults: defaults)

        let bluetooth = PanelListLayoutSnapshot(rowHeights: [24, 36], hasExpansionButton: true, showsDeviceList: true)
        let volume = PanelListLayoutSnapshot(rowHeights: [30], hasExpansionButton: false, showsDeviceList: true)
        store.save(bluetooth, for: .bluetooth)
        store.save(volume, for: .volume)

        XCTAssertEqual(store.snapshot(for: .bluetooth), bluetooth)
        XCTAssertEqual(store.snapshot(for: .volume), volume)
    }

    func testVolumeMetricsDistinguishListeningControlRows() {
        let plain = PanelAudioDeviceRow(
            key: PanelAudioDeviceID(id: 1, uid: "a"),
            name: "Speakers",
            symbol: .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil),
            selected: true,
            enabled: true,
            accessibilityLabel: "Speakers"
        )
        let controllable = PanelAudioDeviceRow(
            key: PanelAudioDeviceID(id: 2, uid: "b"),
            name: "AirPods",
            symbol: .symbol(name: "airpods", variableValue: nil, fallback: nil),
            selected: false,
            enabled: true,
            accessibilityLabel: "AirPods",
            listeningModeAddress: "aa:bb:cc:dd:ee:ff",
            listeningMode: BluetoothListeningModePresentation(
                availableModes: [.noiseCancellation, .transparency],
                selectedMode: .noiseCancellation
            )
        )

        XCTAssertEqual(VolumeDeviceRowMetrics.estimatedHeight(for: plain), VolumeDeviceRowMetrics.singleLineHeight)
        XCTAssertEqual(
            VolumeDeviceRowMetrics.estimatedHeight(for: controllable),
            VolumeDeviceRowMetrics.singleLineHeight + VolumeDeviceRowMetrics.listeningModeExtraHeight
        )
        XCTAssertEqual(
            VolumeDeviceRowMetrics.rowHeights(for: [plain, controllable]),
            [
                Double(VolumeDeviceRowMetrics.singleLineHeight),
                Double(VolumeDeviceRowMetrics.singleLineHeight + VolumeDeviceRowMetrics.listeningModeExtraHeight),
            ]
        )
    }
}

@MainActor
final class VolumePanelPlaceholderTests: XCTestCase {
    private func makeLocalization() throws -> Localization {
        let suiteName = "VolumePanelPlaceholderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    func testPlaceholderForcesTheListAndCarriesTheSkeleton() throws {
        let localization = try makeLocalization()
        let placeholder = PanelListLayoutSnapshot(
            rowHeights: [30, 30],
            hasExpansionButton: false,
            showsDeviceList: true
        )

        let state = AudioPanelMapper.volume(
            .placeholder,
            controllerAvailable: true,
            deviceListPlaceholder: placeholder,
            localization: localization
        )

        XCTAssertTrue(state.rows.isEmpty)
        XCTAssertTrue(state.showsDeviceList)
        XCTAssertEqual(state.deviceListPlaceholder, placeholder)
    }

    func testWithoutPlaceholderAnEmptyListStaysHidden() throws {
        let localization = try makeLocalization()

        let state = AudioPanelMapper.volume(
            .placeholder,
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertFalse(state.showsDeviceList)
        XCTAssertNil(state.deviceListPlaceholder)
    }
}
