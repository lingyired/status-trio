import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsViewDimensionsAndSections() {
        XCTAssertEqual(SettingsView.Section.allCases.count, 5)
        XCTAssertEqual(SettingsView.sidebarWidth, 190)
        XCTAssertEqual(SettingsView.width, 720)
        XCTAssertEqual(SettingsView.height, 530)
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
            localization: localization
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
