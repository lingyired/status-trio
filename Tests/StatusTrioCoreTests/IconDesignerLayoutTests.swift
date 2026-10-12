import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconDesignerLayoutTests: XCTestCase {
    func testIndependentWindowColumnsUsePreviewAndInspectorRatioAtSupportedWidths() {
        for width: CGFloat in [900, 1120, 1440] {
            let columns = IconDesignerLayout.columns(for: width)
            let available = width - 2 * IconDesignerLayout.horizontalPadding - IconDesignerLayout.columnSpacing
            XCTAssertEqual(columns.preview / available, 0.44, accuracy: 0.001)
            XCTAssertEqual(columns.inspector / available, 0.56, accuracy: 0.001)
            XCTAssertEqual(columns.preview + columns.inspector, available, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(columns.preview, 300, "Preview pane must remain usable at width \(width).")
            XCTAssertGreaterThanOrEqual(columns.inspector, 400, "Inspector must remain usable at width \(width).")
            XCTAssertLessThanOrEqual(columns.preview + columns.inspector + IconDesignerLayout.columnSpacing + 2 * IconDesignerLayout.horizontalPadding, width)
        }
    }

    func testHostedMinimumDesignerWindowShowsMenuBarLargeAndDockPreviews() {
        let hosted = makeHostedDesigner(width: 900, height: 680)
        defer { hosted.defaults.removeTestSuite(named: hosted.suiteName) }

        XCTAssertEqual(hosted.view.frame.size, NSSize(width: 900, height: 680))
        XCTAssertGreaterThan(hosted.view.subviews.count, 0,
                             "The full designer must host at the minimum content size with its compact and large previews.")
    }

    func testMainPaneShowsReadOnlyModeAndAlwaysAvailableDataLauncher() throws {
        let session = IconDesignerPreviewSession()
        session.applyQuickFill(.networkError)
        session.mode = .live

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let designer = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift"), encoding: .utf8)
        let panel = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconPreviewDataView.swift"), encoding: .utf8)
        let paneStart = try XCTUnwrap(designer.range(of: "private func previewPane(width: CGFloat) -> some View"))
        let paneEnd = try XCTUnwrap(designer[paneStart.lowerBound...].range(of: "    private var inspector"))
        let previewPane = String(designer[paneStart.lowerBound..<paneEnd.lowerBound])

        XCTAssertTrue(previewPane.contains("previewSession.mode == .simulated ? .iconPreviewModeSimulated : .iconPreviewModeLive"),
                      "The main designer shows the selected preview mode as a read-only label.")
        XCTAssertTrue(previewPane.contains("Button(localization.string(.iconPreviewEditData), action: onEditSamples)"),
                      "The main designer has one always-available entry to edit preview data.")
        XCTAssertFalse(previewPane.contains(".iconPreviewUseSimulatedData"),
                       "Mode changes belong only to the data panel.")
        XCTAssertFalse(previewPane.contains(".iconPreviewUseLiveData"),
                       "Mode changes belong only to the data panel.")
        XCTAssertTrue(panel.contains("Picker(localization.string(.iconPreviewDataMode)"),
                      "The panel must be the sole explicit segmented live/simulated mode control.")
        XCTAssertFalse(panel.contains("Button(localization.string(.iconPreviewUseLiveData))"),
                       "The panel must not duplicate its mode control with a live-data button.")
        XCTAssertFalse(panel.contains("Button(localization.string(.iconPreviewUseSimulatedData))"),
                       "The panel must not duplicate its mode control with a simulated-data button.")
        XCTAssertTrue(panel.contains("get: { session.mode }, set: { session.mode = $0 }"),
                      "Mode changes must happen only through the mode control.")

        session.mode = .simulated
        XCTAssertEqual(session.samples.network.kind, .noInternet,
                       "The noInternet sample must survive a live-mode interval and return to simulated mode.")
        XCTAssertEqual(session.mode, .simulated,
                       "The explicit mode selection must remain independent of the quick fill.")
    }

    func testCompactPreviewUsesSharedMenuBarResolverWithoutExtraExplanation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let designer = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift"), encoding: .utf8)
        let layout = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerLayout.swift"), encoding: .utf8)
        let preview = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift"), encoding: .utf8)

        XCTAssertTrue(layout.contains("menuBarPreviewPointSize: CGFloat = 24"))
        XCTAssertTrue(designer.contains("previewCard(content: .menuBarOnly, iconPointSize: IconDesignerLayout.menuBarPreviewPointSize)"))
        XCTAssertTrue(designer.contains("accessibilityIdentifier(\"iconDesigner.menuBarSizePreview\")"))
        XCTAssertTrue(preview.contains("case .menuBarOnly:") && preview.contains("menuBarPreviewWithLifecycle"))
        XCTAssertTrue(preview.contains("previewSession.mode"))
        XCTAssertTrue(preview.contains("previewSession.samples"))
        XCTAssertTrue(preview.contains("liveChargingPhase"))
        XCTAssertTrue(preview.contains("previewState.playback.phase(at: timeline.date)"))
    }

    func testFallbackSourceIsAlwaysVisibleAndDoesNotMutateConfigurationOnHost() throws {
        let session = IconDesignerPreviewSession()
        session.selectedSlot = .center
        let hosted = makeHostedDesigner(width: 900, height: 680, previewSession: session) { store in
            store.updateIconConfiguration {
                $0.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
            }
        }
        defer { hosted.defaults.removeTestSuite(named: hosted.suiteName) }
        let before = hosted.initialConfiguration
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconSourceEditor.swift"),
            encoding: .utf8)
        XCTAssertFalse(source.contains("isFallbackExpanded"))
        XCTAssertFalse(source.contains("DisclosureGroup"))
        XCTAssertFalse(source.contains("iconDesigner.source.fallbackDisclosure"))
        XCTAssertTrue(source.contains("iconDesigner.source.fallbackPicker"))
        XCTAssertTrue(source.contains("swapPrimaryAndFallback(for: slot"))
        XCTAssertEqual(hosted.store.iconConfiguration, before,
                       "Hosting the always-visible fallback picker must preserve its configured value.")
        XCTAssertEqual(before.composition.center.fallback, .bluetoothAudioOutput,
                       "The host fixture must retain its preconfigured fallback.")
        XCTAssertEqual(
            source.components(separatedBy: ".iconDesignerFallbackSource").count - 1,
            2,
            "Use the localized fallback label for the row and picker accessibility name without a duplicate disclosure heading."
        )
        XCTAssertEqual(hosted.view.frame.size, NSSize(width: 900, height: 680))
    }

    func testHostedDesignerHasOneNativeSlotSelectorThatFitsStandardAndNarrowWidths() throws {
        for width in [CGFloat(900), CGFloat(1120)] {
            let hosted = makeHostedDesigner(width: width, height: 530)
            defer { hosted.defaults.removeTestSuite(named: hosted.suiteName) }
            let nativeControls = descendants(of: hosted.view)
            let slotSelectors = nativeControls.filter {
                String(describing: type(of: $0)) == "SwiftUISegmentedControl"
            }

            XCTAssertEqual(slotSelectors.count, 1, "Expected a single segmented slot selector at width \(width).")
            let selector = try XCTUnwrap(slotSelectors.first)
            let selectorRect = selector.convert(selector.bounds, to: hosted.view)
            let segmentedControl = try XCTUnwrap(selector as? NSSegmentedControl)
            let localization = Localization(defaults: hosted.defaults, preferredLanguages: ["en"])
            let expectedTitles = [
                LocalizationKey.iconDesignerSlotOuterRing,
                .iconDesignerSlotCenter,
                .iconDesignerSlotFooter
            ].map { localization.string($0) }
            XCTAssertEqual(segmentedControl.segmentCount, expectedTitles.count)
            XCTAssertEqual(
                (0..<segmentedControl.segmentCount).map { segmentedControl.label(forSegment: $0) },
                expectedTitles.map(Optional.some),
                "Each native segment must display its localized slot title, not only an icon."
            )
            XCTAssertGreaterThanOrEqual(
                selectorRect.width,
                300,
                "The inspector selector must remain comfortably usable at supported window widths."
            )
            XCTAssertGreaterThan(selectorRect.height, 0)
            XCTAssertGreaterThanOrEqual(selectorRect.minX, hosted.view.bounds.minX)
            XCTAssertLessThanOrEqual(selectorRect.maxX, hosted.view.bounds.maxX)
        }
    }

    func testStandaloneSlotSelectorFitsItsProposedWidth() throws {
        let suite = "StandaloneSlotSelector.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let root = IconSlotPicker(selection: .constant(.outerRing))
            .environmentObject(localization)
            .frame(width: 224)
        let hosted = NSHostingView(rootView: root)
        hosted.frame = NSRect(x: 0, y: 0, width: 224, height: 24)
        hosted.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let control = try XCTUnwrap(descendants(of: hosted).compactMap { $0 as? NSSegmentedControl }.first)
        XCTAssertEqual(control.bounds.width, 224, accuracy: 1)
    }

    func testNativePickerAndSliderRowsKeepControlsInsideCardPaddingAtBothWidths() throws {
        for width in [CGFloat(434), CGFloat(252)] {
            let pickerFrames = LayoutMeasurements()
            let picker = hostMeasuredControlRow(width: width, measurements: pickerFrames) {
                IconDesignerControlRow("Primary source", subtitle: "Compatible with the legacy battery source") {
                    Picker("", selection: .constant(0)) {
                        Text("Automatic").tag(0)
                        Text("System Battery").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .background(measureFrame("picker"))
                }
            }
            picker.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            let pickerFrame = try XCTUnwrap(pickerFrames.frames["picker"])
            XCTAssertGreaterThan(pickerFrame.width, 0)
            XCTAssertGreaterThanOrEqual(pickerFrame.minX, SettingsMetrics.rowPaddingH - 1)
            XCTAssertLessThanOrEqual(pickerFrame.maxX, width - SettingsMetrics.rowPaddingH + 1)

            let sliderFrames = LayoutMeasurements()
            let slider = hostMeasuredControlRow(width: width, measurements: sliderFrames) {
                IconDesignerControlRow("Symbol scale") {
                    HStack(spacing: 8) {
                        Slider(value: .constant(1.25), in: 1...3)
                            .frame(minWidth: 90, maxWidth: 160)
                            .background(measureFrame("slider"))
                        Text("120%")
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
            slider.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            let sliderFrame = try XCTUnwrap(sliderFrames.frames["slider"])
            XCTAssertGreaterThanOrEqual(sliderFrame.width, 80)
            XCTAssertLessThanOrEqual(sliderFrame.width, 160)
            XCTAssertGreaterThanOrEqual(sliderFrame.minX, SettingsMetrics.rowPaddingH - 1)
            XCTAssertLessThanOrEqual(sliderFrame.maxX, width - SettingsMetrics.rowPaddingH + 1)
        }
    }

    func testScaleControlUsesAFullWidthSliderWithinItsCard() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerScaleControl.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity)"))

        for (width, title) in [(CGFloat(434), "Center size"), (CGFloat(252), "Batterietextskalierung") ] {
            let measurements = LayoutMeasurements()
            let hosted = hostMeasuredControlRow(width: width, measurements: measurements) {
                SettingsGroup("Appearance") {
                    IconDesignerScaleControl(
                        title: title,
                        value: .constant(1.2),
                        formattedValue: "120%",
                        range: 1...1.8,
                        step: 0.05,
                        onEditingChanged: { _ in }
                    )
                    .background(measureFrame("scaleControl"))
                }
            }
            hosted.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            let controlFrame = try XCTUnwrap(measurements.frames["scaleControl"])
            XCTAssertGreaterThan(controlFrame.width, width - 40)
            XCTAssertLessThanOrEqual(controlFrame.maxX, width + 1)
        }
    }

    func testDesignerSectionOrderContainsOnlyIconCompositionEditors() {
        XCTAssertEqual(
            IconDesignerLayout.sectionOrder,
            [.slot, .source, .behavior, .appearance, .presets]
        )
    }

    func testLargePreviewUsesTheRealMenuBarRendererAt240To300Points() {
        for width: CGFloat in [320, 380, 500] {
            let size = IconDesignerLayout.largePreviewPointSize(for: width)
            XCTAssertGreaterThanOrEqual(size, 240)
            XCTAssertLessThanOrEqual(size, 300)
        }
    }

    func testPreviewTargetsMapToTheirRealIconSlotsAndHaveComfortableTapSize() {
        XCTAssertEqual(
            Set(IconDesignerPreviewHitRegion.allCases.map(\.slot)),
            Set(IconSlot.allCases)
        )
        XCTAssertGreaterThanOrEqual(IconDesignerLayout.previewHitRegionWidth, 44)
        for iconSize in [16.0, 20.0, 24.0, 32.0] {
            XCTAssertGreaterThanOrEqual(
                IconDesignerLayout.previewHitRegionHeight(forIconSize: iconSize),
                16
            )
        }
    }

    func testDockPreviewUsesFixed128PointTileAndCompactPinnedHeader() {
        XCTAssertEqual(IconDesignerLayout.dockPreviewPointSize, 128)
        XCTAssertLessThan(IconDesignerLayout.maximumPinnedHeaderContentHeight, 100)
    }

    func testDesignerKeepsPreviewFixedAndInspectorInItsOwnScrollView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designer = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift"
        ), encoding: .utf8)
        let preview = try String(contentsOf: root.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift"
        ), encoding: .utf8)

        XCTAssertTrue(designer.contains("previewCard(content: .designerLarge, largePreviewWidth: width)"))
        XCTAssertTrue(designer.contains("private var inspector: some View"))
        XCTAssertTrue(designer.contains("ScrollView {"))
        XCTAssertTrue(designer.contains("IconDesignerLayout.horizontalPadding"))
        XCTAssertTrue(designer.contains("previewCard(content: .dockDetails)"))
        XCTAssertTrue(preview.contains("DockIconPreviewTile("))
        XCTAssertTrue(preview.contains("size: IconDesignerLayout.dockPreviewPointSize"))
        XCTAssertTrue(designer.contains("previewCard(content: .dockDetails)"))
        XCTAssertTrue(preview.contains("IconAnimatedCenterPreview("))
        XCTAssertTrue(preview.contains("iconDesigner.largeRealRendererPreview"))
    }

    func testPreviewDataSourceCardsFillTheSharedWidthBeforeDrawingTheirBackground() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panel = try String(contentsOf: projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconPreviewDataView.swift"
        ), encoding: .utf8)
        let groupStart = try XCTUnwrap(panel.range(of: "private func sampleGroup<Content: View>"))
        let groupEnd = try XCTUnwrap(panel[groupStart.lowerBound...].range(of: "private func sampleBinding<Value>"))
        let group = String(panel[groupStart.lowerBound..<groupEnd.lowerBound])

        XCTAssertTrue(group.contains("VStack(alignment: .leading, spacing: 8)"),
                      "Source titles and both live and simulated content must remain leading aligned.")
        let frame = try XCTUnwrap(group.range(of: ".frame(maxWidth: .infinity, alignment: .leading)"),
                                  "Every source card must fill the shared available width, regardless of its content.")
        let background = try XCTUnwrap(group.range(of: ".background("))
        XCTAssertLessThan(frame.lowerBound, background.lowerBound,
                          "Expand the card before drawing its background so short live/network content cannot shrink it.")
    }

    func testPreviewModeControlsShowTheCorrectSimulationAndEditingActions() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designer = try String(contentsOf: projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift"
        ), encoding: .utf8)
        let panel = try String(contentsOf: projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconPreviewDataView.swift"
        ), encoding: .utf8)
        let modeHeaderStart = try XCTUnwrap(designer.range(of: "private func previewPane(width: CGFloat) -> some View"))
        let modeHeaderEnd = try XCTUnwrap(designer[modeHeaderStart.lowerBound...].range(of: "previewCard(content: .menuBarOnly"))
        let mainModeHeader = String(designer[modeHeaderStart.lowerBound..<modeHeaderEnd.lowerBound])

        XCTAssertFalse(mainModeHeader.contains("scenarioControl"),
                       "The main designer must not duplicate the scenario picker from the simulated-data window.")
        XCTAssertFalse(mainModeHeader.contains("Picker("),
                       "The main designer mode header must contain no scenario picker in live or simulated mode.")
        XCTAssertTrue(mainModeHeader.contains(".iconPreviewModeLive"))
        XCTAssertTrue(mainModeHeader.contains(".iconPreviewModeSimulated"))
        XCTAssertFalse(mainModeHeader.contains(".iconPreviewUseSimulatedData"))
        XCTAssertTrue(mainModeHeader.contains(".iconPreviewEditData"))
        XCTAssertFalse(mainModeHeader.contains(".iconPreviewUseLiveData"))
        XCTAssertEqual(mainModeHeader.components(separatedBy: "Button(").count - 1, 1,
                       "The mode label must be paired with only the always-visible edit-data action.")
        XCTAssertTrue(panel.contains("Menu(localization.string(.iconPreviewQuickFill)"),
                       "Quick-fill presets must be a one-time fill menu, not a mode selector.")
        XCTAssertTrue(panel.contains("session.applyQuickFill(fill)"))
        XCTAssertFalse(panel.contains("IconPreviewScenario.allCases"),
                       "The global scenario picker, including its live item, must be removed.")
        XCTAssertTrue(panel.contains("if session.mode == .simulated"))
        XCTAssertTrue(panel.contains("simulatedControls(for: source)"))
        XCTAssertTrue(panel.contains("liveStatus(for: source)"))
        XCTAssertTrue(panel.contains(".disabled(!session.samples.macBattery.isPresent)"),
                      "A missing Mac battery must disable its sample value controls.")
        XCTAssertTrue(panel.contains(".disabled(!available)"),
                      "Unavailable AirPods ears must retain, but not edit, their sample battery values.")
        XCTAssertTrue(panel.contains(".disabled(!session.samples.systemVolume.isAvailable)"),
                      "Unavailable volume data must disable its sample controls.")
        XCTAssertTrue(panel.contains("bluetoothAvailability: statusStore.bluetoothDevices.availability"),
                      "Live Bluetooth status must honor current permission and availability.")
        XCTAssertTrue(panel.contains("IconPreviewDataLiveStatus.airPodsBattery(from: live)"),
                      "Live AirPods status must use the resolver's freshness/availability gate, never samples.")
        XCTAssertTrue(panel.contains("IconPreviewDataLiveStatus.bluetoothDeviceName("),
                      "Live Bluetooth status must use the tested selected-address/no-fallback policy.")
        XCTAssertTrue(panel.contains("selectedAddress: store.connectedBluetoothIconDeviceAddress"),
                      "The live Bluetooth summary must honor the configured device address.")
    }

    func testLargeDesignerPreviewPassesChargingPhaseOnlyToSharedOuterLayer() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let card = try String(contentsOf: projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift"
        ), encoding: .utf8)
        let animated = try String(contentsOf: projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconAnimatedCenterPreview.swift"
        ), encoding: .utf8)

        XCTAssertTrue(card.contains("chargingPhase: phase"))
        XCTAssertTrue(card.contains("Self.largePreviewChargingPhase("))
        XCTAssertTrue(animated.contains("rendered(IconSceneState(outerRing: scene.outerRing), phase: chargingPhase)"))
        XCTAssertTrue(animated.contains("phase: phase"))
        XCTAssertTrue(animated.contains("rendered(IconSceneState(center: center))"))
        XCTAssertTrue(animated.contains("rendered(IconSceneState(footer: scene.footer))"))
    }

    func testDesignerActionsStayOutsideScrollableInspectorContent() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designer = try String(contentsOf: projectURL.appendingPathComponent(
            "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift"
        ), encoding: .utf8)

        XCTAssertTrue(designer.contains("private var inspectorActions: some View"))
        XCTAssertTrue(designer.contains("IconPresetPicker(store: store, slot: selectedSlot.wrappedValue)"))
        XCTAssertTrue(designer.contains("iconDesigner.inspectorActions"))
        XCTAssertFalse(designer.contains("case .presets:\n            SettingsGroup"))
    }

    private func hostMeasuredControlRow<Content: View>(
        width: CGFloat,
        measurements: LayoutMeasurements,
        @ViewBuilder content: () -> Content
    ) -> NSHostingView<AnyView> {
        let root = content()
            .frame(width: width, alignment: .leading)
            .coordinateSpace(name: "iconDesignerTest")
            .onPreferenceChange(LayoutFramePreferenceKey.self) { measurements.frames = $0 }
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 160)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func measureFrame(_ key: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: LayoutFramePreferenceKey.self,
                value: [key: proxy.frame(in: .named("iconDesignerTest"))]
            )
        }
    }

    private struct HostedDesigner {
        let view: NSHostingView<AnyView>
        let defaults: UserDefaults
        let suiteName: String
        let store: SettingsStore
        let initialConfiguration: IconConfigurationV1
    }

    private func makeHostedDesigner(
        width: CGFloat,
        height: CGFloat,
        previewSession: IconDesignerPreviewSession = IconDesignerPreviewSession(),
        configureStore: (SettingsStore) -> Void = { _ in }
    ) -> HostedDesigner {
        let suiteName = "IconDesignerLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        configureStore(store)
        let initialConfiguration = store.iconConfiguration
        let statusStore = SystemStatusStore(
            batteryMonitor: LayoutBatteryMonitor(),
            wifiMonitor: LayoutWiFiMonitor(),
            volumeMonitor: LayoutVolumeMonitor()
        )
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let root = IconDesignerView(
            store: store,
            statusStore: statusStore,
            previewSession: previewSession
        )
        .environmentObject(localization)
        .environmentObject(ChargingEffectClock())
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        return HostedDesigner(
            view: hosting, defaults: defaults, suiteName: suiteName,
            store: store, initialConfiguration: initialConfiguration
        )
    }

    private func descendants(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants(of:))
    }
}

private struct LayoutFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
private final class LayoutMeasurements: ObservableObject {
    var frames: [String: CGRect] = [:]
}

@MainActor
private final class LayoutBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus> = AsyncStream { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LayoutWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus> = AsyncStream { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class LayoutVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus> = AsyncStream { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
