import AppKit
import Carbon
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsViewDimensionsAndSections() {
        XCTAssertEqual(SettingsView.Section.allCases.count, 9)
        XCTAssertEqual(SettingsView.sidebarWidth, 196)
        XCTAssertEqual(SettingsView.width, 720)
        XCTAssertEqual(SettingsView.height, 530)
    }

    func testSidebarListsEveryStatusElementBeforeTheAppWidePanes() {
        XCTAssertEqual(
            SettingsView.Section.allCases,
            [.appIcon, .battery, .network, .bluetooth, .audio, .brightness, .popover, .general, .about]
        )
        XCTAssertEqual(SettingsView.Section.allCases.first, .appIcon)
        // The brightness hub sits directly after the audio pane.
        XCTAssertEqual(
            SettingsView.Section.allCases.firstIndex(of: .brightness),
            SettingsView.Section.allCases.firstIndex(of: .audio).map { $0 + 1 }
        )
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
            ("popover", AnyView(PopoverSectionView(
                store: store,
                statusStore: statusStore
            ))),
            ("brightness", AnyView(BrightnessSectionView(
                store: store,
                statusStore: statusStore
            )))
        ]

        for (name, pane) in panes {
            let hostingView = NSHostingView(
                rootView: pane
                    .environmentObject(localization)
                    .environmentObject(ChargingEffectClock())
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

    /// The network pane surfaces the Wi-Fi location permission only when name
    /// access is missing, matching the Bluetooth permission banner. `.notDetermined`
    /// offers to raise the prompt; `.denied`/`.restricted` send the user to
    /// Privacy & Security; a granted app shows no notice. This pins that the
    /// pane really pays attention to `snapshot.wifi.nameAccess`.
    func testNetworkPermissionNoticeTracksWiFiNameAccess() throws {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)

        @MainActor
        func renderedHeight(nameAccess: WiFiNameAccess) -> CGFloat {
            let statusStore = makeStatusStore(nameAccess: nameAccess)
            let pane = NetworkSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: .constant(true)
            )
            .environmentObject(localization)
            .environmentObject(ChargingEffectClock())

            let hosting = NSHostingView(rootView: pane)
            hosting.frame = NSRect(
                x: 0, y: 0,
                width: SettingsView.width - SettingsView.sidebarWidth,
                height: SettingsView.height
            )
            hosting.layoutSubtreeIfNeeded()
            return hosting.fittingSize.height
        }

        // The permission notice row only renders when name access is missing, so
        // each ungranted state grows the pane taller than the granted baseline.
        let grantedHeight = renderedHeight(nameAccess: .authorized)
        for state in [WiFiNameAccess.notDetermined, .denied, .restricted] {
            let height = renderedHeight(nameAccess: state)
            XCTAssertGreaterThan(
                height, grantedHeight,
                "\(state): the permission notice should add height over the granted baseline (\(grantedHeight))"
            )
        }
    }
    /// The order list is only reachable when the pane can read paired devices.
    /// The pane used to read `statusStore.bluetoothDevices.devices` without
    /// observing the controller and without activating it, so a fresh launch
    /// that opened Settings rendered "No paired devices available" while
    /// devices were paired. This renders the order list with a non-empty
    /// controller and pins that its non-empty branch really draws.
    func testBluetoothOrderListRendersPairedDevicesFromTheActivatedController() async {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true),
            BluetoothDevice(id: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: false),
            BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "MX Master 3", kind: .peripheral(.mouse), isConnected: false)
        ]
        let controller = SettingsBluetoothTestFactory.makeController(devices: devices)
        controller.activate()
        await waitForDevices(controller)

        XCTAssertEqual(
            controller.devices.count,
            devices.count,
            "the fixture controller must publish its paired devices before the pane renders"
        )

        let emptyStoreController = SettingsBluetoothTestFactory.makeController(devices: [])
        let populated = renderBluetoothPane(
            store: SettingsStore(defaults: suite.defaults),
            storeController: emptyStoreController,
            observedController: controller,
            localization: Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        )
        let empty = renderBluetoothPane(
            store: SettingsStore(defaults: suite.defaults),
            storeController: emptyStoreController,
            observedController: SettingsBluetoothTestFactory.makeController(devices: []),
            localization: Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        )

        XCTAssertGreaterThan(
            populated.height,
            empty.height + 40,
            "the order list must render three device rows, not the empty-state branch "
                + "(populated \(populated.height), empty \(empty.height))"
        )
        controller.deactivate()
    }

    /// The picker under the replace-network-icon toggle: off hides it, on
    /// draws the audio-device row and every classified paired device, and
    /// picking a device records its address and resolved symbol in the store.
    /// The middle-icon source lives in App Icon; selecting Bluetooth reveals
    /// its device row, and picking a device records address and symbol together.
    func testMiddleIconSourcePickerRendersBluetoothOptionsAndPicksADevice() async {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true),
            BluetoothDevice(id: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: false),
            BluetoothDevice(
                id: "AA:BB:CC:DD:EE:FF",
                name: "Ghost",
                kind: .unknown,
                isConnected: false,
                isUnpairedGhost: true
            )
        ]
        let controller = SettingsBluetoothTestFactory.makeController(devices: devices)
        controller.activate()
        await waitForDevices(controller)
        defer { controller.deactivate() }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)

        store.connectionCenterSource = .network
        let withoutDeviceOptions = renderAppIconPane(
            store: store,
            statusStore: makeStatusStore(bluetoothDevices: controller),
            localization: localization,
            subtopic: .appIconMiddleIcon
        )
        store.connectionCenterSource = .bluetoothDevice
        let withDeviceOptions = renderAppIconPane(
            store: store,
            statusStore: makeStatusStore(bluetoothDevices: controller),
            localization: localization,
            subtopic: .appIconMiddleIcon
        )

        XCTAssertGreaterThan(
            withDeviceOptions.height,
            withoutDeviceOptions.height + 30,
            "selecting Bluetooth must render the device row "
                + "(with \(withDeviceOptions.height), without \(withoutDeviceOptions.height))"
        )

        store.setBluetoothNetworkIconDevice(address: "d36d6c40a32e", symbolName: "keyboard")
        XCTAssertEqual(store.bluetoothNetworkIconDeviceAddress, "d36d6c40a32e")
        XCTAssertEqual(store.bluetoothNetworkIconSymbolName, "keyboard")
        XCTAssertEqual(store.bluetoothAudioIconOptions.networkIconSymbolOverride, "keyboard")
    }

    func testSettingsViewHostingViewRendersWithoutCrashing() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removeTestSuite(named: name) }

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

        let hostingView = NSHostingView(rootView: view.environmentObject(ChargingEffectClock()))
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testGeneralPaneRendersTheShortcutRecorderAndClearAction() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.statusPanelShortcut = StatusPanelShortcut(
            keyCode: 36,
            modifiers: UInt32(cmdKey)
        )
        let localization = Localization(
            defaults: suite.defaults,
            preferredLanguages: ["en"]
        )
        let backend = ShortcutSettingsBackend()
        let shortcutController = GlobalShortcutController(
            settings: settings,
            backend: backend,
            action: {}
        )
        shortcutController.start()
        defer { shortcutController.stop() }

        let view = GeneralSectionView(
            store: settings,
            localization: localization,
            globalShortcutController: shortcutController
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: SettingsView.width - SettingsView.sidebarWidth,
            height: SettingsView.height
        )
        hostingView.layoutSubtreeIfNeeded()

        let views = hostingView.descendantsForTesting()
        let recorder = try XCTUnwrap(
            views.compactMap { $0 as? ShortcutRecorderButton }.first
        )
        XCTAssertEqual(recorder.title, "⌘↩")

        let clearButton = try XCTUnwrap(
            views
                .compactMap { $0 as? NSButton }
                .first {
                    $0.title == localization.string(.settingsShortcutClear)
                        || $0.accessibilityLabel()
                            == localization.string(.settingsShortcutClear)
                },
            views.compactMap { view -> String? in
                guard let button = view as? NSButton else { return nil }
                return "\(button.title) / \(button.accessibilityLabel() ?? "nil")"
            }.joined(separator: "\n")
        )
        clearButton.performClick(nil)
        XCTAssertNil(settings.statusPanelShortcut)
    }

    func testSectionTitlesLocalizedForAllLanguages() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removeTestSuite(named: name) }

        for lang in AppLanguage.allCases {
            let localization = Localization(defaults: defaults, preferredLanguages: [lang.rawValue])
            for section in SettingsView.Section.allCases {
                let title = section.title(localization)
                XCTAssertFalse(title.isEmpty, "Section \(section) title should not be empty for \(lang)")
            }
        }
    }

    // MARK: - Two-level navigation

    /// Only the four complex categories expand into leaf subtopics, each in a
    /// fixed order with exactly one default. The five simple categories stay
    /// single-pane so the sidebar never grows an empty disclosure.
    func testOnlyComplexCategoriesExposeOrderedSubtopics() {
        let expected: [SettingsView.Section: [SettingsSubtopic]] = [
            .appIcon: [.appIconAppearance, .appIconRing, .appIconMiddleIcon, .appIconBottomIndicator],
        ]

        for section in SettingsView.Section.allCases {
            let subtopics = SettingsSubtopic.allCases.filter { $0.section == section }
            if let expected = expected[section] {
                XCTAssertEqual(subtopics, expected, "Unexpected subtopics for \(section)")
                XCTAssertEqual(
                    subtopics.filter { $0.isDefault }.count,
                    1,
                    "\(section) must have exactly one default subtopic"
                )
                XCTAssertEqual(
                    subtopics.first,
                    subtopics.first(where: { $0.isDefault }),
                    "\(section) should open to its default subtopic first"
                )
            } else {
                XCTAssertTrue(subtopics.isEmpty, "\(section) must stay single-pane")
            }
        }
    }

    /// Every leaf title must resolve in every shipped language, mirroring the
    /// category titles. The titles reuse existing group keys, so this also
    /// guards against a subtopic pointing at a missing localization key.
    func testSubtopicTitlesLocalizedForAllLanguages() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removeTestSuite(named: name) }

        for lang in AppLanguage.allCases {
            let localization = Localization(defaults: defaults, preferredLanguages: [lang.rawValue])
            for subtopic in SettingsSubtopic.allCases {
                let title = subtopic.title(localization)
                XCTAssertFalse(
                    title.isEmpty,
                    "Subtopic \(subtopic) title should not be empty for \(lang)"
                )
            }
        }
    }

    /// Each leaf renders on its own without crashing, so a page split cannot
    /// produce an empty or broken pane.
    func testEverySubtopicPaneRendersWithoutCrashing() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)
        let statusStore = makeStatusStore()
        let isDark = Binding.constant(true)

        for subtopic in SettingsSubtopic.allCases {
            let pane: AnyView
            switch subtopic.section {
            case .appIcon:
                pane = AnyView(AppIconSectionView(
                    store: store,
                    statusStore: statusStore,
                    previewIsDark: isDark,
                    onShowIconGuide: {},
                    subtopic: subtopic
                ))
            case .battery:
                pane = AnyView(BatterySectionView(
                    store: store,
                    statusStore: statusStore,
                    previewIsDark: isDark,
                    subtopic: subtopic
                ))
            case .audio:
                pane = AnyView(AudioSectionView(
                    store: store,
                    statusStore: statusStore,
                    previewIsDark: isDark,
                    subtopic: subtopic
                ))
            case .bluetooth:
                pane = AnyView(BluetoothSectionView(
                    store: store,
                    statusStore: statusStore,
                    bluetoothDevices: statusStore.bluetoothDevices,
                    appleDeviceDiscovery: statusStore.appleDeviceDiscovery,
                    previewIsDark: isDark,
                    subtopic: subtopic
                ))
            default:
                pane = AnyView(EmptyView())
            }

            let hostingView = NSHostingView(
                rootView: pane
                    .environmentObject(localization)
                    .environmentObject(ChargingEffectClock())
            )
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: SettingsView.width - SettingsView.sidebarWidth,
                height: SettingsView.height
            )
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertNotNil(hostingView.subviews, "\(subtopic) pane should host")
        }
    }

    /// The sidebar and detail keep a two-level structure: one expandable
    /// category at a time, leaf selection only, and each complex pane receives
    /// its subtopic. This guards the navigation shape against drifting back to
    /// a flat list or to an un-routed full pane.
    func testSidebarAndDetailRouteTwoLevelNavigation() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")

        let view = try String(
            contentsOf: base.appendingPathComponent("SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(view.contains("expandedSection"))
        XCTAssertTrue(view.contains("selectSubtopic("))
        XCTAssertTrue(view.contains("subtopicRow("))
        XCTAssertTrue(view.contains("subtopicIfSelectionMatches"))

        for section in ["appIcon", "battery", "audio", "bluetooth"] {
            XCTAssertTrue(
                view.contains("subtopic: subtopicIfSelectionMatches(.\(section))"),
                "\(section) detail must receive its routed subtopic"
            )
        }
        // The refactor must not replace the window's two-column layout with a
        // third column or a nested split view.
        XCTAssertFalse(view.contains("NavigationSplitView"))
    }

    /// Plan B sidebar: every category carries one monochrome glyph, leaves are
    /// text only, expandable parents expose a chevron, and the selection stays
    /// restrained (light accent in the key window, unemphasized when inactive).
    func testSidebarUsesColoredTilesAndTextOnlyLeaves() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")

        let view = try String(
            contentsOf: base.appendingPathComponent("SettingsView.swift"),
            encoding: .utf8
        )
        let chrome = try String(
            contentsOf: base.appendingPathComponent("SettingsChrome.swift"),
            encoding: .utf8
        )

        // A category renders the coloured System-Settings-style tile.
        XCTAssertTrue(view.contains("SettingsIcon("))
        XCTAssertTrue(view.contains("tint: section.tint"))
        XCTAssertFalse(view.contains("SettingsSidebarGlyph(glyph: section.glyph)"))

        // Expandable parents carry a state chevron that rotates while expanding.
        XCTAssertTrue(view.contains("chevron.right"))
        XCTAssertTrue(view.contains("rotationEffect(.degrees(isExpanded ? 90 : 0))"))

        // Selection is semantic and weakened when the window is not key.
        XCTAssertTrue(view.contains("controlActiveState"))
        XCTAssertTrue(view.contains("unemphasizedSelectedContentBackgroundColor"))
        XCTAssertTrue(view.contains("activeSelectionOpacity"))

        // The leaf row is text only: no glyph and no image inside it.
        let leafStart = try XCTUnwrap(view.range(of: "private func subtopicRow"))
        let detailStart = try XCTUnwrap(view.range(of: "// MARK: - Detail"))
        let leafBody = view[leafStart.lowerBound..<detailStart.lowerBound]
        XCTAssertFalse(leafBody.contains("SettingsSidebarGlyph"))
        XCTAssertFalse(leafBody.contains("SettingsIcon"))
        XCTAssertFalse(leafBody.contains("Image(systemName"))

        // The About row shows a short single-line version, not the codename
        // block that used to wrap and truncate.
        XCTAssertTrue(view.contains("versionShortString"))
        // The codename still lives in the About tooltip and identity pane; it
        // must not be rendered as a wrapped sidebar line.
        XCTAssertTrue(view.contains("aboutSidebarDetail("))

        // Visual numbers live in one place, not scattered through the view.
        XCTAssertTrue(chrome.contains("enum SettingsSidebarMetrics"))
        XCTAssertTrue(view.contains("SettingsSidebarMetrics.subtopicIndent"))
        XCTAssertTrue(view.contains("SettingsSidebarMetrics.categoryRowHeight"))
    }

    /// Each feature pane offers a quick "show this module in the status panel"
    /// toggle, like the Bluetooth pane's existing one.
    func testEachFeaturePaneHasQuickStatusPanelToggle() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")
        let expected: [(String, String)] = [
            ("BatterySectionView.swift", "settingsPanelShowBattery"),
            ("NetworkSectionView.swift", "settingsPanelShowNetwork"),
            ("AudioSectionView.swift", "settingsPanelShowAudio"),
            ("BrightnessSectionView.swift", "settingsPanelShowBrightness"),
        ]
        for (file, key) in expected {
            let source = try String(
                contentsOf: base.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains(key), "\(file) should offer \(key)")
            XCTAssertTrue(source.contains("setPopupSection"), "\(file) toggle must route through the store")
        }
    }

    /// Every icon-affecting feature pane shows the same live status-icon preview
    /// bar, so the top of the pane is consistent across categories.
    func testIconAffectingPanesShowLivePreviewBar() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")
        for file in [
            "AppIconSectionView.swift", "BatterySectionView.swift",
            "NetworkSectionView.swift", "BluetoothSectionView.swift",
            "AudioSectionView.swift",
        ] {
            let source = try String(
                contentsOf: base.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertTrue(
                source.contains("StatusIconPreviewCard"),
                "\(file) should pin the live preview bar"
            )
        }
    }

    /// The visual parameters stay within the Compact Native Sidebar values
    /// requested for this design, and the sidebar width is 196 pt.
    func testSidebarMetricsMatchTheRequestedDesign() {
        XCTAssertEqual(SettingsView.sidebarWidth, 196)
        XCTAssertEqual(SettingsSidebarMetrics.categoryRowHeight, 32)
        XCTAssertEqual(SettingsSidebarMetrics.subtopicRowHeight, 26)
        XCTAssertTrue((16...18).contains(SettingsSidebarMetrics.iconPointSize))
        XCTAssertTrue((16...18).contains(SettingsSidebarMetrics.iconSlotWidth))
        XCTAssertEqual(SettingsSidebarMetrics.categoryFontSize, 13)
        XCTAssertEqual(SettingsSidebarMetrics.subtopicFontSize, 12)
        XCTAssertTrue((2...4).contains(SettingsSidebarMetrics.categoryGroupSpacing))
        // Leaf text must line up on the same vertical column as the parent text.
        let categoryTextX = SettingsSidebarMetrics.horizontalPadding
            + SettingsSidebarMetrics.rowHorizontalPadding
            + SettingsSidebarMetrics.tileSize
            + SettingsSidebarMetrics.iconTextSpacing
        let leafTextX = SettingsSidebarMetrics.horizontalPadding
            + SettingsSidebarMetrics.subtopicIndent
            + SettingsSidebarMetrics.subtopicRowHorizontalPadding
        XCTAssertEqual(leafTextX, categoryTextX)
        XCTAssertEqual(SettingsSidebarMetrics.subtopicCornerRadius, 6)
        XCTAssertEqual(SettingsSidebarMetrics.categoryCornerRadius, 6)
        XCTAssertTrue((0.16...0.18).contains(SettingsSidebarMetrics.expandAnimationDuration))
    }

    /// The sidebar keeps its app-wide panes pinned below a divider, scrolls only
    /// the functional group, and reveals the active row.
    func testSidebarPinsAppWideGroupAndRevealsSelection() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")

        let view = try String(
            contentsOf: base.appendingPathComponent("SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(view.contains("scrollableSections"))
        XCTAssertTrue(view.contains("pinnedSections"))
        XCTAssertTrue(view.contains("ScrollViewReader"))
        XCTAssertTrue(view.contains("revealSelection"))
        XCTAssertTrue(view.contains(".onChange(of: navigation.selectedSubtopic)"))
        XCTAssertTrue(view.contains("separatorColor"))
    }


    /// The Bluetooth settings-demand token is owned by the category container,
    /// never by the content builder. Bluetooth is a single pane now, so there
    /// is no leaf switch — but the pane body must still not start or stop the
    /// demand itself, so the listener is not rebuilt.
    func testBluetoothSettingsDemandStaysOnTheCategoryContainer() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")

        let bluetooth = try String(
            contentsOf: base.appendingPathComponent("BluetoothSectionView.swift"),
            encoding: .utf8
        )

        func occurrences(of needle: String) -> Int {
            bluetooth.components(separatedBy: needle).count - 1
        }

        XCTAssertEqual(occurrences(of: "beginBluetoothSettingsDemand("), 1)
        // One balanced end in `onAppear` (defensive re-entry) and one in
        // `onDisappear`.
        XCTAssertEqual(occurrences(of: "endBluetoothSettingsDemand("), 2)

        // The container owns the lifecycle; the content builder must not.
        XCTAssertFalse(bluetooth.contains("bluetoothSubpage"))
        let contentRange = try XCTUnwrap(bluetooth.range(of: "private var fullBluetoothContent"))
        let tail = bluetooth[contentRange.lowerBound...]
        let groupRange = try XCTUnwrap(tail.range(of: "private var deviceListGroup"))
        let contentBody = tail[..<groupRange.lowerBound]
        XCTAssertFalse(contentBody.contains("beginBluetoothSettingsDemand("))
        XCTAssertFalse(contentBody.contains("onAppear"))
        XCTAssertFalse(contentBody.contains("onDisappear"))
    }

    /// #245/#256: the volume-scroll switch and its effect scope stay on the
    /// Audio pane, while the shared scroll direction (used by volume, brightness
    /// and input sliders) lives on the status-panel pane. Guard the split at the
    /// source so neither half drifts back into the other page.
    func testScrollSettingsAreSplitBetweenPanelAndAudioPanes() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings")

        let audio = try String(
            contentsOf: base.appendingPathComponent("AudioSectionView.swift"),
            encoding: .utf8
        )
        let popover = try String(
            contentsOf: base.appendingPathComponent("PopoverSectionView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(audio.contains("volumeScrollGroup"))
        XCTAssertTrue(audio.contains("settingsAudioVolumeScrollGroup"))
        XCTAssertTrue(audio.contains("scrollScopeLabel"))
        XCTAssertTrue(audio.contains("popupScrollAdjustsVolume"))
        XCTAssertTrue(audio.contains("popupVolumeScrollScope"))
        XCTAssertFalse(audio.contains("popupVolumeNaturalScrolling"))
        XCTAssertFalse(audio.contains("settingsPopupVolumeScrollNatural"))

        XCTAssertTrue(popover.contains("scrollDirectionGroup"))
        XCTAssertTrue(popover.contains("settingsPopupVolumeScrollDirection"))
        XCTAssertTrue(popover.contains("settingsPopupVolumeScrollNatural"))
        XCTAssertTrue(popover.contains("popupVolumeNaturalScrolling"))

        // Audio is a single pane now: the volume-scroll group sits on the same
        // page as the device groups, so no leaf switch exists any more.
        XCTAssertFalse(audio.contains("audioSubpage"))
        let audioBodyStart = try XCTUnwrap(audio.range(of: "private var fullAudioContent"))
        let audioBody = audio[audioBodyStart.lowerBound...]
        XCTAssertTrue(audioBody.contains("volumeScrollGroup"))
        XCTAssertTrue(audioBody.contains("displayRulesGroup"))
        XCTAssertTrue(audioBody.contains("deviceOrderGroup"))
        XCTAssertTrue(audioBody.contains("inputDeviceOrderGroup"))
        XCTAssertTrue(audioBody.contains("externalVolumeGroup"))
        XCTAssertFalse(
            popover.contains("popupScrollAdjustsVolume"),
            "the panel pane must not own the volume-scroll switch"
        )
        XCTAssertFalse(popover.contains("popupVolumeScrollScope"))
        XCTAssertFalse(popover.contains("scrollScopeLabel"))
    }

    /// The compatibility note tells users whose display DDC Status Trio cannot
    /// speak to use BetterDisplay, and links to its site. Pin the URL and the
    /// fact that the note actually reaches the page.
    func testBrightnessPaneLinksToTheBetterDisplaySite() throws {
        XCTAssertEqual(
            BrightnessSectionView.betterDisplayWebsiteURL?.absoluteString,
            "https://betterdisplay.pro"
        )

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/BrightnessSectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("settingsBrightnessCompatibilityDescription"))
        XCTAssertTrue(source.contains("settingsBrightnessCompatibilityLink"))
        XCTAssertTrue(source.contains("compatibilityGroup"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.open"))
    }
}

@MainActor
private func makeSuite() -> (defaults: UserDefaults, name: String) {
    let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removeTestSuite(named: name)
    return (defaults, name)
}

private func clear(_ suite: (defaults: UserDefaults, name: String)) {
    suite.defaults.removeTestSuite(named: suite.name)
}

private extension NSView {
    func descendantsForTesting() -> [NSView] {
        subviews + subviews.flatMap { $0.descendantsForTesting() }
    }
}

@MainActor
private final class ShortcutSettingsBackend: GlobalShortcutRegistering {
    private var tokens: Set<UUID> = []

    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID {
        let token = UUID()
        tokens.insert(token)
        return token
    }

    func unregister(_ token: UUID) {
        tokens.remove(token)
    }

    func stop() {
        tokens.removeAll()
    }
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
private func makeStatusStore(nameAccess: WiFiNameAccess) -> SystemStatusStore {
    SystemStatusStore(
        batteryMonitor: DummyBatteryMonitor(),
        wifiMonitor: DummyWiFiMonitor(),
        volumeMonitor: DummyVolumeMonitor(),
        initialSnapshot: StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50, nameAccess: nameAccess),
            volume: .placeholder
        )
    )
}

@MainActor
private func makeStatusStore(bluetoothDevices: BluetoothDeviceController) -> SystemStatusStore {
    SystemStatusStore(
        batteryMonitor: DummyBatteryMonitor(),
        wifiMonitor: DummyWiFiMonitor(),
        volumeMonitor: DummyVolumeMonitor(),
        bluetoothDevices: bluetoothDevices
    )
}

/// A `BluetoothDeviceController` whose paired-device read answers with the
/// fixture and whose monitor already holds the grant, so `activate()` starts
/// the monitor without a permission prompt, exactly as the granted app does.
@MainActor
private enum SettingsBluetoothTestFactory {
    static func makeController(devices: [BluetoothDevice]) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: SettingsBluetoothDeviceReaderStub(result: .success(devices)),
            stateMonitor: SettingsBluetoothStateMonitorStub(),
            batteryReader: SettingsBluetoothBatteryReaderStub(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
    }
}

/// Renders the Bluetooth settings pane into a hosting view and returns the size
/// its own content needs at the pane's real width.
///
/// `storeController` and `observedController` are deliberately two different
/// controllers: the pane renders the one it observes, while the store keeps an
/// empty one, so a pane that fell back to `statusStore.bluetoothDevices` would
/// still draw the empty branch.
@MainActor
private func renderAppIconPane(
    store: SettingsStore,
    statusStore: SystemStatusStore,
    localization: Localization,
    subtopic: SettingsSubtopic? = nil
) -> NSSize {
    let pane = AppIconSectionView(
        store: store,
        statusStore: statusStore,
        previewIsDark: .constant(true),
        onShowIconGuide: {},
        subtopic: subtopic
    )
    .environmentObject(localization)
    .environmentObject(ChargingEffectClock())

    let hosting = NSHostingView(rootView: pane)
    hosting.frame = NSRect(
        x: 0,
        y: 0,
        width: SettingsView.width - SettingsView.sidebarWidth,
        height: SettingsView.height
    )
    hosting.layoutSubtreeIfNeeded()
    return hosting.fittingSize
}

@MainActor
private func renderBluetoothPane(
    store: SettingsStore,
    storeController: BluetoothDeviceController,
    observedController: BluetoothDeviceController,
    localization: Localization,
    subtopic: SettingsSubtopic? = nil
) -> NSSize {
    let statusStore = SystemStatusStore(
        batteryMonitor: DummyBatteryMonitor(),
        wifiMonitor: DummyWiFiMonitor(),
        volumeMonitor: DummyVolumeMonitor(),
        bluetoothDevices: storeController
    )
    let pane = BluetoothSectionView(
        store: store,
        statusStore: statusStore,
        bluetoothDevices: observedController,
        appleDeviceDiscovery: statusStore.appleDeviceDiscovery,
        previewIsDark: .constant(true),
        subtopic: subtopic
    )
    .environmentObject(localization)
    .environmentObject(ChargingEffectClock())

    let hosting = NSHostingView(rootView: pane)
    hosting.frame = NSRect(
        x: 0,
        y: 0,
        width: SettingsView.width - SettingsView.sidebarWidth,
        height: SettingsView.height
    )
    hosting.layoutSubtreeIfNeeded()
    return hosting.fittingSize
}

@MainActor
private func waitForDevices(_ controller: BluetoothDeviceController) async {
    for _ in 0..<1_000 {
        if !controller.devices.isEmpty { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

private final class SettingsBluetoothDeviceReaderStub: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(result)
    }
}

private final class SettingsBluetoothBatteryReaderStub: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class SettingsBluetoothStateMonitorStub: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(authorization, .poweredOn)
    }

    func stop() {}
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
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
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
