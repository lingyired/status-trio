import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryDetailsLayoutTests: XCTestCase {
    func testBatteryHealthCardFitsEveryLanguageAndScheme() async throws {
        for language in AppLanguage.allCases {
            for dark in [false, true] {
                let size = try await render(
                    language: language, available: true, connected: true, charging: true,
                    dark: dark)
                XCTAssertEqual(size.width, 330, accuracy: 0.5)
                XCTAssertLessThan(size.height, 590, "\(language.rawValue) dark=\(dark)")
            }
        }
    }

    func testWorstCasePageKeepsControlsOnScreen() async throws {
        // Every optional section at once: full power flow, five energy apps,
        // health card, low-power control, and the Charge to Full Now area.
        for language in [AppLanguage.english, .german, .russian, .arabic] {
            let size = try await render(
                language: language, available: true, connected: true, charging: true,
                allPower: true, energyApps: true,
                chargeToFullNow: .applying, showsLowPowerControl: true)
            XCTAssertEqual(size.width, 330, accuracy: 0.5)
            // 420 pt scroll cap plus the fixed chrome (~300 pt) stays below the
            // 700 pt usable height of the smallest supported 13-inch display.
            XCTAssertLessThanOrEqual(size.height, 700, "\(language.rawValue)")
        }
    }

    func testScrollCapBoundsTallPageWithoutGrowingPopover() async throws {
        let capped = try await render(
            language: .english, available: true, connected: true, charging: true,
            allPower: true, energyApps: true, maxContentHeight: 300)
        let roomy = try await render(
            language: .english, available: true, connected: true, charging: true,
            allPower: true, energyApps: true, maxContentHeight: 900)
        XCTAssertLessThan(capped.height, roomy.height,
                          "a smaller cap must scroll, not grow the page")
        XCTAssertLessThanOrEqual(capped.height, 620)
    }

    func testContentHeightLimitLeavesRoomForFixedChrome() {
        for visibleHeight: CGFloat in [700, 800, 900, 1200] {
            let limit = BatteryDetailsLayoutPolicy.contentHeightLimit(visibleHeight: visibleHeight)
            XCTAssertGreaterThanOrEqual(limit, BatteryDetailsLayoutPolicy.minimumContentHeight)
            XCTAssertLessThanOrEqual(
                limit + BatteryDetailsLayoutPolicy.fixedChromeHeight,
                max(visibleHeight, BatteryDetailsLayoutPolicy.minimumContentHeight
                    + BatteryDetailsLayoutPolicy.fixedChromeHeight))
        }
        XCTAssertEqual(
            BatteryDetailsLayoutPolicy.contentHeightLimit(visibleHeight: 900), 600, accuracy: 0.5)
        XCTAssertEqual(
            BatteryDetailsLayoutPolicy.contentHeightLimit(visibleHeight: 700), 400, accuracy: 0.5)
        XCTAssertEqual(
            BatteryDetailsLayoutPolicy.contentHeightLimit(visibleHeight: 500),
            BatteryDetailsLayoutPolicy.minimumContentHeight, accuracy: 0.5)
    }

    func testBatteryHealthCardStaysCompactWhenEveryValueIsUnavailable() async throws {
        // A Mac that exposes no capacity or temperature still shows the card
        // with an explanation, so this page must not grow past the same budget.
        for language in AppLanguage.allCases {
            let size = try await render(
                language: language, available: true, connected: true, health: nil)
            XCTAssertEqual(size.width, 330, accuracy: 0.5)
            XCTAssertLessThan(size.height, 600, language.rawValue)
        }
    }

    func testBatteryPageFitsPopoverInEnglishAndChinese() async throws {
        for language in [AppLanguage.english, .simplifiedChinese] {
            let power = try await render(language: language, available: true)
            let unavailable = try await render(language: language, available: false)
            let collecting = try await render(language: language, available: false, collecting: true)
            // Budget includes the compact health card that now sits under the
            // power flow on every battery page.
            XCTAssertLessThan(power.height, 480)
            XCTAssertLessThan(unavailable.height, power.height)
            XCTAssertLessThan(collecting.height, power.height)
            _ = try await renderSummary(language: language, isPresent: true)
            _ = try await renderSummary(language: language, isPresent: false)
        }
    }

    func testConnectedPageFitsEveryLanguageWithAndWithoutSystemTelemetry() async throws {
        // The page now carries a second settings action below the system-power
        // one, plus the compact health card. Keep the budget tight enough that
        // another whole row still fails.
        let heightBudget: CGFloat = 640
        for language in AppLanguage.allCases {
            let connected = try await render(language: language, available: true, connected: true,
                                             maxContentHeight: 900)
            XCTAssertLessThan(connected.height, heightBudget, language.rawValue)
            let charging = try await render(language: language, available: true, connected: true,
                                            charging: true, maxContentHeight: 900)
            XCTAssertLessThan(charging.height, heightBudget, language.rawValue)
            let missing = try await render(language: language, available: true, connected: true,
                                           systemAvailable: false, maxContentHeight: 900)
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
                // Worst case: every power option enabled, five energy apps,
                // and the health card. Still below the smallest supported
                // 13-inch display's usable popover height.
                XCTAssertLessThan(size.height, 790, "\(language.rawValue) dark=\(dark)")
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
                        inputWatts: Double? = nil,
                        health: BatteryHealthSnapshot? = .layoutFixture,
                        maxContentHeight: CGFloat = 420,
                        showsLowPowerControl: Bool = false) async throws -> NSSize {
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
            health: health)
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: charging,
                                    isLowPowerMode: false, isConnectedToPower: connected)
        let panelState = PanelDetailMapper.battery(
            status: battery,
            details: fixture,
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: allPower),
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
            lowPowerMode: showsLowPowerControl
                ? LowPowerModeController(initialIsLowPowerMode: true) : nil,
            showsLowPowerControl: showsLowPowerControl,
            chargeToFullNow: chargeToFullNow,
            maxContentHeight: maxContentHeight
        )
            .padding(14)
            .frame(width: 330)
            .background(Color(white: dark ? 0.12 : 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, dark ? .dark : .light)
        let state = connected
            ? (systemAvailable ? (charging ? "system-charging" : "system") : "system-unavailable")
            : (available ? "power" : (collecting ? "collecting" : "unavailable"))
        let size = try await capture(view, named: "battery-\(language.rawValue)-page-\(state)-\(allPower ? "flow" : "default")-\(dark ? "dark" : "light")")
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
        return size
    }
}

private extension BatteryHealthSnapshot {
    /// Stable layout fixture; values are examples, not a measured machine.
    static let layoutFixture = BatteryHealthSnapshot(
        designCapacityMAh: 8_579,
        maximumCapacityMAh: 8_413,
        healthPercent: 98.065,
        temperatureCelsius: 36.4,
        chargeTime: .estimated(minutes: 80)
    )
}
