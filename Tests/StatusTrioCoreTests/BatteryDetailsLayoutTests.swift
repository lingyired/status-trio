import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryDetailsLayoutTests: XCTestCase {
    func testBatteryPageFitsPopoverInEnglishAndChinese() async throws {
        for language in [AppLanguage.english, .simplifiedChinese] {
            let power = try await render(language: language, available: true)
            let unavailable = try await render(language: language, available: false)
            let collecting = try await render(language: language, available: false, collecting: true)
            XCTAssertLessThan(power.height, 380)
            XCTAssertLessThan(unavailable.height, power.height)
            XCTAssertLessThan(collecting.height, power.height)
            _ = try await renderSummary(language: language, isPresent: true)
            _ = try await renderSummary(language: language, isPresent: false)
        }
    }

    func testConnectedPageFitsEveryLanguageWithAndWithoutSystemTelemetry() async throws {
        for language in AppLanguage.allCases {
            let connected = try await render(language: language, available: true, connected: true)
            XCTAssertLessThan(connected.height, 440, language.rawValue)
            let charging = try await render(language: language, available: true, connected: true, charging: true)
            XCTAssertLessThan(charging.height, 440, language.rawValue)
            let missing = try await render(language: language, available: true, connected: true, systemAvailable: false)
            // An unavailable system reading drops the timestamp row, not just
            // shortens a value, so the page must lose at least one row of height.
            XCTAssertGreaterThanOrEqual(connected.height - missing.height, 10,
                                        "\(language.rawValue) kept the system timestamp row")
        }
    }

    private func renderSummary(language: AppLanguage, isPresent: Bool) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BatterySummary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        let battery = BatteryStatus(rawPercentage: isPresent ? 80 : nil, isPresent: isPresent,
                                    isCharging: false, isLowPowerMode: false,
                                    isConnectedToPower: false)
        let view = BatteryStatusView(
            state: PanelPresentationMapper.battery(battery, localization: localization),
            cautionColor: .yellow,
            onOpenBatteryDetails: {},
            onOpenBatterySettings: {}
        )
            .padding(14)
            .frame(width: 330)
            .background(Color(white: 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, .light)
        return try await capture(view, named: "battery-\(language.rawValue)-row-\(isPresent ? "present" : "absent")")
    }

    /// Mounts the view, waits for SwiftUI's appearance task to deliver the
    /// fixture, then records the settled fitting size and an optional snapshot.
    @discardableResult
    private func capture<V: View>(_ view: V, named name: String) async throws -> NSSize {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        // Allow SwiftUI's appearance task and the serial reader to publish the fixture.
        try await Task.sleep(for: .milliseconds(50))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_BATTERY_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
        return size
    }

    private func render(language: AppLanguage, available: Bool,
                        collecting: Bool = false, connected: Bool = false,
                        systemAvailable: Bool = true, charging: Bool = false) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BatteryDetails.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        let fixture = BatteryDetails(
            adapterWatts: connected ? 90 : nil,
            remainingMinutes: available ? 121 : nil,
            cycleCount: 43,
            power: available ? BatteryPowerSample(volts: 12.279, amps: connected ? (charging ? 1.528 : 0) : -1.528, updatedAt: Date()) : nil,
            powerAvailability: collecting ? .collecting : .unavailable,
            systemPower: connected && systemAvailable ? SystemPowerSample(watts: 17.25, readAt: Date()) : nil)
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: connected)
        let panelState = PanelDetailMapper.battery(
            status: battery,
            details: fixture,
            localization: localization
        )
        let view = BatteryDetailsView(
            state: panelState,
            onBack: {},
            onOpenBatterySettings: {},
            onCopyValue: { _ in },
            onAppear: {}
        )
            .padding(14)
            .frame(width: 330)
            .background(Color(white: 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, .light)
        // Allow SwiftUI's appearance task and the serial reader to publish the fixture.
        let state = connected
            ? (systemAvailable ? (charging ? "system-charging" : "system") : "system-unavailable")
            : (available ? "power" : (collecting ? "collecting" : "unavailable"))
        let size = try await capture(view, named: "battery-\(language.rawValue)-page-\(state)")
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
        return size
    }
}
