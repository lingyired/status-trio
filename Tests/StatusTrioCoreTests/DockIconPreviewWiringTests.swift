import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconPreviewWiringTests {
    @Test func evaluatingTheTileBodyTwiceRendersOnce() {
        var renderedLengths: [Int] = []
        let cache = DockIconPreviewCache(limit: 4) {
            renderedLengths.append($0)
        }
        let tile = DockIconTile(
            status: .placeholder,
            backgroundStyle: .dark,
            size: 56,
            previewCache: cache
        )

        _ = tile.body
        _ = tile.body

        #expect(renderedLengths == [112])
        #expect(tile.pixelLength == 112)
    }

    /// The icon-size slider writes `store.iconSize` once per step
    /// (`Sources/StatusTrioCore/UI/Settings/AppIconSectionView.swift:106-112`)
    /// and `SettingsView` observes the store
    /// (`Sources/StatusTrioCore/UI/Settings/SettingsView.swift:6`), so one drag
    /// re-evaluates the whole pane ~21 times. The Dock tile does not depend on
    /// the menu bar icon size, so it must render once.
    @Test func aSliderDragRendersThePreviewOnce() throws {
        let harness = try PreviewWiringHarness()
        defer { harness.cleanUp() }
        var renderedLengths: [Int] = []
        let cache = DockIconPreviewCache(limit: 4) {
            renderedLengths.append($0)
        }
        let tile = DockIconPreviewTile(
            store: harness.settings,
            statusStore: harness.statusStore,
            size: 30,
            previewCache: cache
        )
        var images: [NSImage] = []

        for size in stride(
            from: SettingsStore.iconSizeRange.lowerBound,
            through: SettingsStore.iconSizeRange.upperBound,
            by: 1
        ) {
            harness.settings.iconSize = size
            images.append(try #require(tile.previewImage))
        }

        #expect(images.count == 21)
        #expect(renderedLengths == [60])
        #expect(images.allSatisfy { $0 === images[0] })
    }

    @Test func aResolvedDesignerSceneFeedsMenuBarAndDockPreviewKeys() {
        let resolvedScene = IconSceneState()
        let dockTile = DockIconTile(
            status: .placeholder,
            backgroundStyle: .dark,
            size: 44,
            resolvedScene: resolvedScene,
            previewCache: DockIconPreviewCache(limit: 2)
        )
        let menuBar = MenuBarPreviewBar(
            status: .placeholder,
            resolvedScene: resolvedScene
        ) { EmptyView() }

        #expect(dockTile.renderKey.scene == resolvedScene)
        #expect(menuBar.scene == resolvedScene)
    }

    @Test func theTileStillLaysOutAtItsRequestedSize() {
        let tile = DockIconTile(
            status: .placeholder,
            backgroundStyle: .dark,
            size: 56,
            previewCache: DockIconPreviewCache(limit: 2)
        )
        let hostingView = NSHostingView(rootView: tile)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize

        #expect(abs(size.width - 56) <= 0.5)
        #expect(abs(size.height - 56) <= 0.5)
    }

    /// `AppIconController.renderLatestDockIcon` builds the Dock key from
    /// `StatusIconAppearance(settings:)` and `DockIconBackgroundResolver`
    /// (`Sources/StatusTrioCore/App/AppIconController.swift:216-229`). The only
    /// intentional difference between that key and a preview's key is the raster
    /// length, so everything else has to match.
    @Test func thePreviewKeyCarriesTheSameIconInputsAsTheDockKey() throws {
        let harness = try PreviewWiringHarness()
        defer { harness.cleanUp() }
        let store = harness.settings
        store.dockIconBackgroundPreference = .light
        store.volumeDisplayStyle = .arc
        store.ringStrokeStyle = .bold
        store.showsBatteryPercentage = false
        store.usesBatteryStatusColors = false
        store.replacesNetworkIconWithBluetoothAudio = true

        let status = MenuBarStatus(snapshot: harness.statusStore.snapshot)
        let appearance = StatusIconAppearance(settings: store)
        let backgroundStyle = DockIconBackgroundResolver.style(
            for: store.dockIconBackgroundPreference,
            theme: .default,
            isDarkAppearance: false
        )
        let previewLength = DockIconPreviewMetrics.pixelLength(forPointSize: 30)
        let dockKey = DockIconRenderKey(
            scene: makeIconPresentationScene(
                status: status,
                battery: appearance.batteryOptions,
                connection: appearance.connectionOptions,
                volume: appearance.volumeOptions,
                bluetooth: appearance.bluetoothAudioOptions
            ),
            backgroundStyle: backgroundStyle,
            pixelLength: DockIconRenderer.pixelSize
        )
        let dockKeyAtPreviewLength = DockIconRenderKey(
            scene: makeIconPresentationScene(
                status: status,
                battery: appearance.batteryOptions,
                connection: appearance.connectionOptions,
                volume: appearance.volumeOptions,
                bluetooth: appearance.bluetoothAudioOptions
            ),
            backgroundStyle: backgroundStyle,
            pixelLength: previewLength
        )
        let previewKey = DockIconPreviewTile(
            store: store,
            statusStore: harness.statusStore,
            size: 30,
            previewCache: DockIconPreviewCache(limit: 4)
        ).renderKey

        #expect(backgroundStyle == .light)
        #expect(dockKey.pixelLength == DockIconRenderer.pixelSize)
        #expect(previewKey == dockKeyAtPreviewLength)
    }

    /// Mirrors `AppIconControllerTests.menuBarIconSizeDoesNotChangeTheDockIcon`:
    /// the size slider is menu-bar only, so it must not create a new Dock raster.
    @Test func iconSizeDoesNotChangeThePreviewKey() throws {
        let harness = try PreviewWiringHarness()
        defer { harness.cleanUp() }
        let tile = DockIconPreviewTile(
            store: harness.settings,
            statusStore: harness.statusStore,
            size: 30,
            previewCache: DockIconPreviewCache(limit: 4)
        )
        let before = tile.renderKey

        harness.settings.iconSize = SettingsStore.iconSizeRange.upperBound

        #expect(tile.renderKey == before)
    }
}

@MainActor
private struct PreviewWiringHarness {
    let suiteName: String
    let defaults: UserDefaults
    let settings: SettingsStore
    let statusStore: SystemStatusStore

    init() throws {
        let name = "StatusTrioCoreTests.DockIconPreviewWiring.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw PreviewWiringError.missingDefaultsSuite
        }
        defaults.removeTestSuite(named: name)
        suiteName = name
        self.defaults = defaults
        settings = SettingsStore(defaults: defaults)
        statusStore = SystemStatusStore(
            batteryMonitor: PreviewBatteryMonitor(),
            wifiMonitor: PreviewWiFiMonitor(),
            volumeMonitor: PreviewVolumeMonitor()
        )
    }

    func cleanUp() {
        defaults.removeTestSuite(named: suiteName)
    }
}

private enum PreviewWiringError: Error {
    case missingDefaultsSuite
}

@MainActor
private final class PreviewBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class PreviewWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class PreviewVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
