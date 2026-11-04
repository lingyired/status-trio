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
        // The page now carries a second settings action below the system-power
        // one. Keep the budget tight enough that another whole row still fails.
        let heightBudget: CGFloat = 470
        for language in AppLanguage.allCases {
            let connected = try await render(language: language, available: true, connected: true)
            XCTAssertLessThan(connected.height, heightBudget, language.rawValue)
            let charging = try await render(language: language, available: true, connected: true, charging: true)
            XCTAssertLessThan(charging.height, heightBudget, language.rawValue)
            let missing = try await render(language: language, available: true, connected: true, systemAvailable: false)
            // An unavailable system reading drops the timestamp row, not just
            // shortens a value, so the page must lose at least one row of height.
            XCTAssertGreaterThanOrEqual(connected.height - missing.height, 10,
                                        "\(language.rawValue) kept the system timestamp row")
        }
    }

    func testThreeDigitInputPowerStaysInsideTheFlowCard() async throws {
        let size = try await render(
            language: .english,
            available: true,
            connected: true,
            allPower: true,
            inputWatts: 110.23
        )
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
    }

    func testBreakdownPageFitsPopoverWithFiveBranches() async throws {
        // Five branches are the tallest possible diagram; the page still has to
        // fit the popover without clipping the actions below it.
        let heightBudget: CGFloat = 620
        for language in AppLanguage.allCases {
            let split = try await render(language: language, available: true, connected: true,
                                         allPower: true, breakdown: true)
            XCTAssertLessThan(split.height, heightBudget, language.rawValue)
            let legacy = try await render(language: language, available: true, connected: true,
                                          allPower: true)
            XCTAssertGreaterThan(split.height, legacy.height, language.rawValue)
        }
    }

    func testBatteryDetailsShowChargeToFullAboveTheSettingsActions() async throws {
        let hidden = try await render(language: .english, available: true, connected: true)
        let available = try await render(
            language: .english,
            available: true,
            connected: true,
            chargeToFullNow: .available
        )
        let applying = try await render(
            language: .english,
            available: true,
            connected: true,
            chargeToFullNow: .applying
        )

        XCTAssertEqual(available.width, 330, accuracy: 0.5)
        XCTAssertEqual(applying.width, 330, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            available.height,
            hidden.height + 20,
            "the details page must reserve a row for Charge to Full Now"
        )
        XCTAssertEqual(applying.height, available.height, accuracy: 0.5)
    }

    func testBatteryActionGlyphsShareTheSummaryVisualCenter() async throws {
        let probe = try await renderSummaryActionProbe()
        let actions = probe.trailingGlyphRects(count: 3, minimumX: 200)
        XCTAssertEqual(actions.count, 3, "leaf, chevron, and Settings glyphs must render")
        guard actions.count == 3 else { return }

        let leaf = actions[0]
        let chevron = actions[1]
        let settings = actions[2]
        let contentStart: CGFloat = 14 + 24 + 10
        let contentCenter = try XCTUnwrap(
            probe.glyphCenterY(from: contentStart, to: leaf.minX - 10),
            "the battery title and subtitle must render"
        )
        let leafCenter = try XCTUnwrap(probe.glyphCenterY(in: leaf))
        let chevronCenter = try XCTUnwrap(probe.glyphCenterY(in: chevron))
        let settingsCenter = try XCTUnwrap(probe.glyphCenterY(in: settings))

        for (name, center) in [
            ("leaf", leafCenter),
            ("chevron", chevronCenter),
            ("settings", settingsCenter)
        ] {
            XCTAssertEqual(
                center,
                contentCenter,
                accuracy: 0.25,
                "\(name) center \(center) must match the two-line content center \(contentCenter)"
            )
        }
    }

    func testFullPowerFlowAndApplicationListFitLightAndDarkPanels() async throws {
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            for dark in [false, true] {
                let size = try await render(language: language, available: true, connected: true,
                    charging: true, allPower: true, dark: dark, energyApps: true)
                XCTAssertLessThan(size.height, 650, "\(language.rawValue) dark=\(dark)")
            }
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

    private func renderSummaryActionProbe() async throws -> SummaryActionAlignmentProbe {
        let suite = "StatusTrioCoreTests.BatteryActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let battery = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: true,
            isConnectedToPower: true
        )
        let controller = LowPowerModeController(initialIsLowPowerMode: true)
        let view = BatteryStatusView(
            state: PanelPresentationMapper.battery(battery, localization: localization),
            cautionColor: .yellow,
            onOpenBatteryDetails: {},
            onOpenBatterySettings: {},
            lowPowerMode: controller,
            showsLowPowerToggle: true
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)
        .environment(\.displayScale, 2)

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        // A 1x screen quantizes ink centers to half points, coarser than the
        // quarter-point assertion. Pin the capture density on headless CI too.
        return try XCTUnwrap(SummaryActionAlignmentProbe(hosting, pixelScale: 2))
    }

    /// Lays out the mapped fixture synchronously, then records its fitting size
    /// and an optional snapshot. The injected appearance callback is a no-op.
    @discardableResult
    private func capture<V: View>(_ view: V, named name: String) async throws -> NSSize {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
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
                        systemAvailable: Bool = true, charging: Bool = false,
                        allPower: Bool = false, dark: Bool = false, energyApps: Bool = false,
                        chargeToFullNow: ChargeToFullNowPresentation = .hidden,
                        inputWatts: Double? = nil, breakdown: Bool = false) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BatteryDetails.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = BatteryDetails(
            adapterWatts: connected ? 90 : nil,
            remainingMinutes: available ? 121 : nil,
            cycleCount: 43,
            power: available ? BatteryPowerSample(volts: allPower ? 12.5 : 12.279,
                amps: allPower ? 3.2968 : (connected ? (charging ? 1.528 : 0) : -1.528), updatedAt: observedAt) : nil,
            powerAvailability: collecting ? .collecting : .unavailable,
            systemPower: connected && systemAvailable ? SystemPowerSample(watts: 25.59, readAt: observedAt) : nil,
            inputPower: connected
                ? SystemPowerSample(watts: inputWatts ?? 67, readAt: observedAt) : nil,
            breakdown: breakdown && connected ? BatteryPowerBreakdown(
                source: .adapter,
                sourceWatts: 67,
                display: .init(watts: 8.07, readAt: observedAt),
                usb: .init(watts: 4.5, readAt: observedAt),
                system: .init(watts: 13.22, readAt: observedAt),
                readAt: observedAt) : nil)
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: charging,
                                    isLowPowerMode: false, isConnectedToPower: connected)
        let panelState = PanelDetailMapper.battery(
            status: battery,
            details: fixture,
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: allPower, showsBreakdown: breakdown),
            energyApps: energyApps ? ApplicationEnergyRanking(apps: [
                EnergyApplication(id: "browser", name: "Browser"),
                EnergyApplication(id: "editor", name: "Code Editor"),
                EnergyApplication(id: "video", name: "Video Player"),
                EnergyApplication(id: "chat", name: "Chat"),
                EnergyApplication(id: "music", name: "Music")], phase: .ready) : nil
        )
        let view = BatteryDetailsView(
            state: panelState,
            onBack: {},
            onOpenBatterySettings: {},
            onCopyValue: { _ in },
            onAppear: {},
            chargeToFullNow: chargeToFullNow
        )
            .padding(14)
            .frame(width: 330)
            .background(Color(white: dark ? 0.12 : 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, dark ? .dark : .light)
        let state = connected
            ? (systemAvailable ? (charging ? "system-charging" : "system") : "system-unavailable")
            : (available ? "power" : (collecting ? "collecting" : "unavailable"))
        let size = try await capture(view, named: "battery-\(language.rawValue)-page-\(state)-\(allPower ? "flow" : "default")-\(breakdown ? "breakdown" : "single")-\(dark ? "dark" : "light")")
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
        return size
    }
}
