import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsViewDimensionsAndSections() {
        XCTAssertEqual(SettingsView.Section.allCases.count, 7)
        XCTAssertEqual(SettingsView.sidebarWidth, 190)
        XCTAssertEqual(SettingsView.width, 720)
        XCTAssertEqual(SettingsView.height, 530)
    }

    func testSidebarListsEveryStatusElementBeforeTheAppWidePanes() {
        XCTAssertEqual(
            SettingsView.Section.allCases,
            [.appIcon, .battery, .network, .audio, .popover, .general, .about]
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
                rootView: pane.environmentObject(localization)
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

    func testSettingsViewHostingViewRendersWithoutCrashing() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }

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

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testSectionTitlesLocalizedForAllLanguages() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }

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
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
}

private func clear(_ suite: (defaults: UserDefaults, name: String)) {
    suite.defaults.removePersistentDomain(forName: suite.name)
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
    func requestNameAccess() {}
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
