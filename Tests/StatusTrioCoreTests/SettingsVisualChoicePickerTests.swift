import AppKit
import XCTest
@testable import StatusTrioCore

/// The middle-icon source chooser and the ring-content chooser share one
/// `SettingsVisualChoicePicker`, so they must keep one card size, spacing and
/// preview environment.
@MainActor
final class SettingsVisualChoicePickerTests: XCTestCase {
    private func store() throws -> SettingsStore {
        let suite = "StatusTrioCoreTests.VisualChoicePicker.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SettingsStore(defaults: defaults)
    }

    /// Both pickers share one card-width token. It is wide enough that the
    /// densest (middle-icon) row still fills the content column by compressing
    /// to its per-card share, yet narrow enough that a two-option row stays
    /// close to that size instead of stretching each card to half the pane.
    func testSharedCardWidthFitsMiddleRowAndDoesNotStretchTwoOptions() {
        let contentWidth = SettingsView.width - SettingsView.sidebarWidth
            - 2 * SettingsMetrics.pageMargin
            - 2 * SettingsMetrics.rowPaddingH
        let spacing = SettingsMetrics.visualChoiceSpacing
        let middleCount = CGFloat(ConnectionCenterSource.allCases.count)
        let middleShare = (contentWidth - spacing * (middleCount - 1)) / middleCount

        XCTAssertGreaterThanOrEqual(
            SettingsMetrics.visualChoiceCardWidth,
            middleShare,
            "the middle row must still fill the content column (its cards compress to this share)"
        )

        let twoCards = SettingsMetrics.visualChoiceCardWidth * 2 + spacing
        XCTAssertLessThan(
            twoCards,
            contentWidth / 2,
            "two ring-content cards must not stretch to half the pane"
        )
    }

    /// Building the AirPods tile swaps only the ring source on top of the live
    /// appearance; it never changes the stored selection. The tile previews the
    /// real AirPods arcs regardless of what the Mac is currently drawing.
    func testAirPodsPreviewConfigurationSwapsOnlyTheRing() throws {
        let store = try store()
        XCTAssertEqual(store.outerRingContent, .systemBattery)

        let systemConfig = RingContentPreviewScene.configuration(for: .systemBattery, store: store)
        let airPodsConfig = RingContentPreviewScene.configuration(for: .airPodsBattery, store: store)

        XCTAssertEqual(systemConfig.composition.outerRing.primary, .systemBattery)
        XCTAssertEqual(airPodsConfig.composition.outerRing.primary, .airPodsBattery)
        XCTAssertEqual(
            store.outerRingContent,
            .systemBattery,
            "building the tile must not change the stored selection"
        )
        // Everything except the ring source is identical, so the two tiles share
        // one presentation environment.
        XCTAssertEqual(systemConfig.appearance, airPodsConfig.appearance)
        XCTAssertEqual(systemConfig.composition.center, airPodsConfig.composition.center)
        XCTAssertEqual(
            systemConfig.behaviors.systemBatteryRing,
            airPodsConfig.behaviors.systemBatteryRing
        )
    }

    func testAirPodsPreviewHonoursTheStoredRingBehaviour() throws {
        let store = try store()

        store.airPodsRingUsesDualRing = false
        store.showsAirPodsTopSymbolInRing = false
        let single = RingContentPreviewScene.configuration(for: .airPodsBattery, store: store)
        XCTAssertEqual(single.behaviors.airPodsRing, .single)
        XCTAssertFalse(single.behaviors.showsAirPodsTopSymbol)

        store.airPodsRingUsesDualRing = true
        store.showsAirPodsTopSymbolInRing = true
        let dual = RingContentPreviewScene.configuration(for: .airPodsBattery, store: store)
        XCTAssertEqual(dual.behaviors.airPodsRing, .dual)
        XCTAssertTrue(dual.behaviors.showsAirPodsTopSymbol)
    }

    /// Both tiles render through the real runtime resolver to a bitmap from the
    /// fixed sample status, with no live monitor involved.
    func testRingPreviewRendersBothSources() throws {
        let store = try store()
        for content in OuterRingContent.allCases {
            let image = RingContentPreviewScene.image(
                for: content,
                store: store,
                isDarkBackground: false
            )
            let unwrapped = try XCTUnwrap(image, "preview for \(content) should render")
            XCTAssertGreaterThan(unwrapped.size.width, 0)
            XCTAssertGreaterThan(unwrapped.size.height, 0)
        }
    }
}
