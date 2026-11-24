import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Guards the 2026-11-24 settings copy pass: every changed key must ship in all
/// 12 languages, the short labels that sit in the narrow control column must
/// still measure inside that column with the real system font, and the panes
/// whose copy or groups changed must lay out at the minimum 640 pt window width.
@MainActor
final class SettingsCopyLayoutTests: XCTestCase {
    /// Keys whose copy, grouping or naming changed in this pass. A missing
    /// translation would leave the English fallback in place; this list keeps
    /// the shipped languages honest in addition to the parity test's key check.
    private static let changedKeys: [LocalizationKey] = [
        .settingsRingContentRowDescription,
        .settingsIconSizeDescription,
        .settingsMiddleIconChargingStatusDescription,
        .settingsBottomIndicatorSource,
        .settingsBottomIndicatorMetric,
        .settingsBottomIndicatorMetricDescription,
        .autoLowPowerThreshold,
        .autoLowPowerThresholdDescription,
        .settingsBatterySharedSyncNote,
        .settingsKeepAwakeAutoOff,
        .settingsKeepAwakeAutoOffDescription,
        .settingsKeepAwakeOnlyLid,
        .settingsAudioDisplayRules,
        .settingsAudioOrderDescription,
        .settingsAudioInputOrderDescription,
        .settingsBrightnessBackend,
        .settingsBrightnessDescription,
        .settingsBrightnessGroupBetterDisplay,
        .hardwareMonitorSettingsPanelRefreshDescription,
        .hardwareMonitorSettingsBackgroundDescription,
        .hardwareMonitorSettingsGroupSampling,
        .hardwareMonitorSettingsSplitGapProgress,
        .hardwareMonitorSettingsSplitGapProgressDescription,
        .settingsPanelBackgroundTitle,
        .settingsPopupScrollWheelStep,
        .settingsPopupScrollWheelStepDescription,
        .settingsPopupVolumeScrollNaturalDescription,
        .settingsPanelShowsPanelOnHoverDescription,
        .settingsPanelReturnsToSummaryOnOpenDescription,
        .settingsStatusCheckTitle,
        .settingsRefreshInterval,
        .settingsTransferTitle,
        .settingsBluetoothBatteryLevelsDescription,
        .settingsAppleDevicesAndBatteryDescription,
        .settingsNetworkPermissionNotDeterminedDescription,
        .settingsNetworkPermissionDeniedDescription,
        .settingsNetworkCenterSource,
    ]

    /// Titles rendered in a picker/menu's narrow trailing column. They must stay
    /// short enough to keep the 640 pt pane readable in the longest languages.
    private static let narrowColumnLabels: [LocalizationKey] = [
        .settingsBottomIndicatorMetric,
        .settingsPopupScrollWheelStep,
        .settingsRefreshInterval,
    ]

    func testChangedCopyShipsInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(
                Localization.resourceBundle(for: language),
                "missing bundle for \(language.rawValue)"
            )
            for key in Self.changedKeys {
                let value = bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) has no copy for \(key.rawValue)")
                XCTAssertNotEqual(
                    value,
                    key.rawValue,
                    "\(language.rawValue) falls back to the raw key for \(key.rawValue)"
                )
            }
        }
    }

    func testShortLabelsFitTheNarrowControlColumnInEveryLanguage() throws {
        // These labels share the trailing picker/menu column of a 640 pt pane.
        // Keep them short enough to read inside that menu without truncation.
        let budget: CGFloat = 150
        let font = NSFont.systemFont(ofSize: 13)
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            for key in Self.narrowColumnLabels {
                let text = bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(
                    width,
                    budget,
                    "\(language.rawValue) \(key.rawValue) measures \(width) pt: \(text)"
                )
            }
        }
    }

    func testChangedPanesLayOutAtTheMinimumWindowWidth() {
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
                appleDeviceDiscovery: statusStore.appleDeviceDiscovery,
                previewIsDark: isDark
            ))),
            ("audio", AnyView(AudioSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("monitor", AnyView(HardwareMonitorSectionView(store: store))),
            ("panel", AnyView(PopoverSectionView(store: store, statusStore: statusStore))),
            ("general", AnyView(GeneralSectionView(store: store, localization: localization))),
            ("keepAwake", AnyView(KeepAwakeSectionView(store: store))),
            ("brightness", AnyView(BrightnessSectionView(store: store, statusStore: statusStore))),
        ]

        // The 640 pt window leaves a 444 pt detail column. Measure with that
        // real width proposal instead of an unconstrained fitting width, which
        // would report the sum of every unwrapped ideal line.
        let contentWidth = SettingsView.minimumWidth - SettingsView.sidebarWidth
        XCTAssertEqual(contentWidth, 444, accuracy: 0.5)

        for (name, pane) in panes {
            let hosting = NSHostingController(
                rootView: pane
                    .environmentObject(localization)
                    .environmentObject(ChargingEffectClock())
            )
            let measured = hosting.sizeThatFits(
                in: NSSize(width: contentWidth, height: 2_000)
            )
            XCTAssertLessThanOrEqual(
                measured.width,
                contentWidth + 1,
                "\(name) pane needs more than the 444 pt detail column"
            )
            XCTAssertGreaterThan(measured.height, 0, "\(name) pane has no height")
        }
    }

    /// The changed descriptions on the panes that overflowed (monitor, panel)
    /// plus the longest new copy. Each one is laid out with the production
    /// `SettingsRow` at the real 444 pt detail width: the row must stay inside
    /// that width and grow to the height the same text needs without
    /// truncation. Arabic exercises the right-to-left layout.
    func testChangedDescriptionsWrapInsideTheDetailColumnInEveryLanguage() throws {
        let detailWidth = SettingsView.minimumWidth - SettingsView.sidebarWidth
        XCTAssertEqual(detailWidth, 444, accuracy: 0.5)
        let rowWidth = detailWidth - SettingsMetrics.pageMargin * 2
        // Row padding, the icon tile, the three 12 pt HStack gaps, the
        // Spacer's 12 pt minimum and the fixed-width switch leave this much
        // room for the text column.
        let trailingWidth: CGFloat = 38
        let textWidth = rowWidth
            - SettingsMetrics.rowPaddingH * 2
            - SettingsMetrics.iconSize
            - 12 * 3
            - 12
            - trailingWidth
        XCTAssertGreaterThan(textWidth, 0)

        let probes: [(LocalizationKey, LocalizationKey)] = [
            (.hardwareMonitorSettingsBackground, .hardwareMonitorSettingsBackgroundDescription),
            (.hardwareMonitorSettingsPanelRefresh, .hardwareMonitorSettingsPanelRefreshDescription),
            (.settingsPopupVolumeScrollNatural, .settingsPopupVolumeScrollNaturalDescription),
            (.settingsPopupScrollWheelStep, .settingsPopupScrollWheelStepDescription),
            (.settingsAudioOrderTitle, .settingsAudioOrderDescription),
            (.settingsBrightnessGroupTitle, .settingsBrightnessDescription),
            (.settingsStatusCheckTitle, .settingsRefreshIntervalDescription),
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(
                Localization.resourceBundle(for: language),
                "missing bundle for \(language.rawValue)"
            )
            let layoutDirection: LayoutDirection =
                language == .arabic ? .rightToLeft : .leftToRight
            for (titleKey, descriptionKey) in probes {
                let title = bundle.localizedString(
                    forKey: titleKey.rawValue,
                    value: nil,
                    table: nil
                )
                let description = bundle.localizedString(
                    forKey: descriptionKey.rawValue,
                    value: nil,
                    table: nil
                )
                let row = SettingsRow(
                    "gearshape.fill",
                    title: title,
                    subtitle: description
                ) {
                    Toggle("", isOn: .constant(true))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .frame(width: trailingWidth)
                }
                .environment(\.layoutDirection, layoutDirection)

                let measured = NSHostingController(rootView: row)
                    .sizeThatFits(in: NSSize(width: rowWidth, height: 10_000))
                XCTAssertLessThanOrEqual(
                    measured.width,
                    rowWidth + 1,
                    "\(language.rawValue) \(descriptionKey.rawValue) asks for \(measured.width) pt and overflows the \(rowWidth) pt row"
                )

                let expected = expectedRowHeight(
                    title: title,
                    description: description,
                    width: textWidth,
                    layoutDirection: layoutDirection
                )
                XCTAssertGreaterThanOrEqual(
                    measured.height + 1,
                    expected,
                    "\(language.rawValue) \(descriptionKey.rawValue) renders \(measured.height) pt but its full text needs \(expected) pt, so the description truncates"
                )
            }
        }
    }

    /// The row height the copy needs when it wraps instead of truncating. The
    /// same `Text` views and fonts as `SettingsRow`, measured at the row's own
    /// text column width.
    private func expectedRowHeight(
        title: String,
        description: String,
        width: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGFloat {
        let titleHeight = NSHostingController(
            rootView: Text(title)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, layoutDirection)
        )
        .sizeThatFits(in: NSSize(width: width, height: 10_000))
        .height
        let descriptionHeight = NSHostingController(
            rootView: Text(description)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, layoutDirection)
        )
        .sizeThatFits(in: NSSize(width: width, height: 10_000))
        .height
        return titleHeight + 2 + descriptionHeight + SettingsMetrics.rowPaddingV * 2
    }

    /// The panel's Appearance card now owns the slider colour/thickness rows
    /// that used to sit on the General page. Lock the split at the source so a
    /// later merge cannot reintroduce a duplicate control on General.
    func testSliderAppearanceLivesOnThePanelPage() throws {
        let settingsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")

        let panel = try String(
            contentsOf: settingsDirectory.appendingPathComponent("PopoverSectionView.swift"),
            encoding: .utf8
        )
        let general = try String(
            contentsOf: settingsDirectory.appendingPathComponent("GeneralSectionView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(panel.contains("settingsPanelLevelSliderColor"))
        XCTAssertTrue(panel.contains("settingsPanelLevelSliderThickness"))
        XCTAssertFalse(general.contains("settingsPanelLevelSliderColor"))
        XCTAssertFalse(general.contains("settingsPanelLevelSliderThickness"))
    }

    // MARK: - Helpers

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.SettingsCopyLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removeTestSuite(named: suite.name)
    }

    private func makeStatusStore() -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: SettingsCopyBatteryMonitor(),
            wifiMonitor: SettingsCopyWiFiMonitor(),
            volumeMonitor: SettingsCopyVolumeMonitor()
        )
    }
}

@MainActor
private final class SettingsCopyBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class SettingsCopyWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class SettingsCopyVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
