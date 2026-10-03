import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The Bluetooth row mixes device names and AirPods levels in one line inside
/// a 330-point popover, so its longest states have to be rendered, not assumed.
@MainActor
final class BluetoothSummaryLayoutTests: XCTestCase {
    func testSummaryStatesFitThePopover() async throws {
        let states: [(name: String, authorization: BluetoothAuthorizationStatus, devices: [BluetoothDevice])] = [
            ("permission", .notDetermined, []),
            ("airpods", .allowed, [
                BluetoothDevice(id: "AA", name: "AirPods Pro", kind: .audio, isConnected: true)
            ]),
            ("mixed", .allowed, [
                BluetoothDevice(id: "AA", name: "AirPods Pro", kind: .audio, isConnected: true),
                BluetoothDevice(id: "BB", name: "MX Master 3", kind: .peripheral(.mouse), isConnected: true),
                BluetoothDevice(id: "CC", name: "Magic Keyboard", kind: .peripheral(.keyboard), isConnected: true)
            ]),
            ("none", .allowed, [])
        ]

        let airPodsLevels: [String: BluetoothBatteryLevel] = [
            BluetoothBatteryReader.normalizedAddress("AA"): BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60)
        ]
        // The longest state the row can draw now that every connected device
        // reports the level the report carries for it: the line has to truncate
        // rather than grow the two-line layout.
        let mixedLevels: [String: BluetoothBatteryLevel] = [
            BluetoothBatteryReader.normalizedAddress("AA"): BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60),
            BluetoothBatteryReader.normalizedAddress("BB"): BluetoothBatteryLevel(
                deviceAddress: "BB", main: 45, left: nil, right: nil, caseLevel: nil),
            BluetoothBatteryReader.normalizedAddress("CC"): BluetoothBatteryLevel(
                deviceAddress: "CC", main: 90, left: nil, right: nil, caseLevel: nil)
        ]
        let levelsByState: [String: [String: BluetoothBatteryLevel]] = [
            "airpods": airPodsLevels,
            "mixed": mixedLevels
        ]

        for state in states {
            for language in [AppLanguage.english, .simplifiedChinese] {
                let size = try await render(
                    language: language,
                    authorization: state.authorization,
                    devices: state.devices,
                    batteryLevels: levelsByState[state.name] ?? [:],
                    listOptions: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: []),
                    named: "bluetooth-\(language.rawValue)-\(state.name)"
                )
                XCTAssertEqual(size.width, 330, accuracy: 0.5)
                // One summary row: the two-line layout must not grow.
                XCTAssertLessThan(size.height, 120)
            }
        }
    }

    /// A component-battery device moves its levels onto a second line, while an
    /// ordinary whole-device level stays inline. The charging case is still drawn
    /// as a single glyph, so the second line is one caption line tall and no
    /// more: the level-bearing list comes out exactly the one extra line taller
    /// than the same list with nothing to draw, and the inline mouse row adds
    /// nothing. A level that wrapped into two visual lines — a raw word, or a
    /// glyph that broke the line — would push the delta well past one line.
    func testComponentDeviceAddsOneLineWhileInlineDeviceStaysPut() async throws {
        let devices = [
            BluetoothDevice(id: "AA", name: "AirPods Pro", kind: .audio, isConnected: true),
            BluetoothDevice(id: "BB", name: "MX Master 3", kind: .peripheral(.mouse), isConnected: true)
        ]
        let levels: [String: BluetoothBatteryLevel] = [
            BluetoothBatteryReader.normalizedAddress("AA"): BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60),
            BluetoothBatteryReader.normalizedAddress("BB"): BluetoothBatteryLevel(
                deviceAddress: "BB", main: 45, left: nil, right: nil, caseLevel: nil)
        ]
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])

        let levelsShown = try await render(
            language: .english,
            authorization: .allowed,
            devices: devices,
            batteryLevels: levels,
            listOptions: options,
            named: "bluetooth-list-levels"
        )
        let levelsHidden = try await render(
            language: .english,
            authorization: .allowed,
            devices: devices,
            listOptions: options,
            named: "bluetooth-list-no-levels"
        )

        XCTAssertEqual(levelsShown.width, 330, accuracy: 0.5)
        // Only the component row grows the list; the inline row keeps its height.
        XCTAssertGreaterThan(
            levelsShown.height,
            levelsHidden.height,
            "a component device's levels have to take their own line"
        )
        // One extra caption line — the delta `BluetoothDeviceRowMetrics` models as
        // componentHeight - inlineHeight — and not the runaway of a wrapped run.
        XCTAssertEqual(
            levelsShown.height - levelsHidden.height,
            BluetoothDeviceRowMetrics.componentHeight - BluetoothDeviceRowMetrics.inlineHeight,
            accuracy: 1,
            "the second line is exactly one line tall; the level must not wrap"
        )
    }

    /// With the list on, the row grows by the visible device rows and the
    /// expansion control — in both a narrow-glyph and a wide-glyph language.
    func testDeviceListGrowsTheRowWithoutWideningIt() async throws {
        let devices = (1...6).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Device \(index)",
                kind: .audio,
                isConnected: index <= 2
            )
        }
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        for language in [AppLanguage.english, .simplifiedChinese] {
            let withList = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: options,
                named: "bluetooth-list-\(language.rawValue)"
            )
            let withoutList = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 3, order: []),
                named: "bluetooth-nolist-\(language.rawValue)"
            )
            // A zero limit hides every device row while keeping the expansion
            // control, so this render isolates the rows from the control: the
            // height difference above it can only come from the rows themselves.
            let expandOnly = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 0, order: []),
                named: "bluetooth-list-expandonly-\(language.rawValue)"
            )

            XCTAssertEqual(withList.width, 330, accuracy: 0.5)
            XCTAssertGreaterThan(
                withList.height,
                withoutList.height,
                "the list must add the device rows in \(language.rawValue)"
            )
            XCTAssertGreaterThan(
                withList.height,
                expandOnly.height + 20,
                "the device rows themselves must add height in \(language.rawValue): "
                    + "the expansion control alone is not the list"
            )
        }
    }

    /// No paired devices means no list: the row keeps its own message and its
    /// original height.
    func testEmptyDeviceListDoesNotChangeTheRow() async throws {        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        let withSettingOn = try await render(
            language: .english,
            authorization: .allowed,
            devices: [],
            listOptions: options,
            named: "bluetooth-list-empty"
        )

        XCTAssertEqual(withSettingOn.width, 330, accuracy: 0.5)
        XCTAssertLessThan(withSettingOn.height, 120)
    }

    func testNearbyGroupRequiresBothBatterySettingsAndRendersAsItsOwnGroup() async throws {
        let nearby = [
            NearbyBluetoothBatteryDevice(
                id: UUID(),
                name: "Temperature Sensor",
                batteryLevel: 0,
                model: nil,
                manufacturer: nil,
                lastUpdated: Date()
            )
        ]
        let paired = [
            BluetoothDevice(
                id: "AA:00:00:00:00:01",
                name: "Temperature Sensor",
                kind: .unknown,
                isConnected: false
            )
        ]
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])

        let (baselineHosting, baselineController) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: [],
            batteryLevels: [:],
            listOptions: options
        )
        defer { baselineController.deactivate() }

        let (nearbyHosting, nearbyController) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: [],
            batteryLevels: [:],
            listOptions: options,
            nearbyDevices: nearby,
            showsNearbyBatteryDevices: true
        )
        defer { nearbyController.deactivate() }

        let (pairedHosting, pairedController) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: paired,
            batteryLevels: [:],
            listOptions: options
        )
        defer { pairedController.deactivate() }

        let (bothGroupsHosting, bothGroupsController) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: paired,
            batteryLevels: [:],
            listOptions: options,
            nearbyDevices: nearby,
            showsNearbyBatteryDevices: true
        )
        defer { bothGroupsController.deactivate() }

        let (disabledHosting, disabledController) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: [],
            batteryLevels: [:],
            listOptions: options,
            nearbyDevices: nearby,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: true
        )
        defer { disabledController.deactivate() }

        XCTAssertGreaterThan(nearbyHosting.fittingSize.height, baselineHosting.fittingSize.height)
        XCTAssertGreaterThan(
            bothGroupsHosting.fittingSize.height,
            pairedHosting.fittingSize.height,
            "a same-named nearby device must remain in its own group beside the paired row"
        )
        XCTAssertEqual(
            disabledHosting.fittingSize.height,
            baselineHosting.fittingSize.height,
            accuracy: 1,
            "Nearby rows depend on both opt-in and the main Bluetooth battery-level setting"
        )
    }

    func testLongNearbyListScrollsInsideItsBound() async throws {
        let nearby = (1...12).map { index in
            NearbyBluetoothBatteryDevice(
                id: UUID(),
                name: "BLE Sensor \(index)",
                batteryLevel: index * 7,
                model: nil,
                manufacturer: nil,
                lastUpdated: Date()
            )
        }
        let (hosting, controller) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: [],
            batteryLevels: [:],
            listOptions: .standard,
            nearbyDevices: nearby,
            showsNearbyBatteryDevices: true
        )
        defer { controller.deactivate() }

        let scrolling = try XCTUnwrap(
            firstScrollView(in: hosting),
            "Nearby results must scroll instead of growing the popover without a bound"
        )
        XCTAssertLessThanOrEqual(
            scrolling.frame.height,
            NearbyBluetoothBatteryRows.maximumRowsHeight + 1
        )
    }

    /// The panel has no scroll view of its own, so the rows take a bound: a list
    /// too long for the panel scrolls inside it instead of growing the popover
    /// past the screen, and a list that fits does not scroll at all.
    ///
    /// Whether the scroll view *overflows* is not visible from here — the harness
    /// lays out a hosting view with no window, so the content rect it reports is
    /// already clipped to the bound. What is checked instead is the bound itself:
    /// a scroll view exists, it stops at the list's own height, and the panel
    /// grows nothing like the 27 extra rows it is showing.
    func testALongDeviceListScrollsInsideThePanel() async throws {
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 30, order: [])
        let longDevices = (1...30).map(summaryDevice)
        let shortDevices = (1...3).map(summaryDevice)

        let longSize = try await render(
            language: .english,
            authorization: .allowed,
            devices: longDevices,
            listOptions: options,
            named: "bluetooth-long-list"
        )
        let shortSize = try await render(
            language: .english,
            authorization: .allowed,
            devices: shortDevices,
            listOptions: options,
            named: "bluetooth-short-list"
        )
        XCTAssertGreaterThan(
            longSize.height,
            shortSize.height,
            "the rows beyond the short list still have to render"
        )
        XCTAssertLessThan(
            longSize.height,
            430,
            "the panel has to stay within its bound however many devices it lists"
        )

        let (hosting, controller) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: longDevices,
            batteryLevels: [:],
            listOptions: options
        )
        defer { controller.deactivate() }
        hosting.layoutSubtreeIfNeeded()

        let scrolling = try XCTUnwrap(
            firstScrollView(in: hosting),
            "the rows have to be scrollable: the popover cannot grow to fit them"
        )
        XCTAssertLessThanOrEqual(
            scrolling.frame.height,
            BluetoothDeviceList.maximumRowsHeight + 1,
            "the rows have to stop at the list's own bound"
        )
    }

    /// A list that fits must not create a scroll view at all. Its scroller is
    /// what flashed while a collapse animated, on a Mac with six devices that
    /// never needed scrolling: the animated frame shrinks through the moment the
    /// content is still taller than it. Below the bound there is no scroll view,
    /// so there is nothing to flash.
    func testAListThatFitsCreatesNoScrollView() async throws {
        for visible in [5, 6, 12] {
            let (hosting, controller) = try await makeHosting(
                language: .english,
                authorization: .allowed,
                devices: (1...visible).map(summaryDevice),
                batteryLevels: [:],
                listOptions: BluetoothDeviceListOptions(
                    showsList: true,
                    maxVisibleDevices: visible,
                    order: []
                )
            )
            defer { controller.deactivate() }
            hosting.layoutSubtreeIfNeeded()

            XCTAssertNil(
                firstScrollView(in: hosting),
                "\(visible) rows fit inside the bound, so nothing should scroll"
            )
        }

        // One row past it, and the rows do scroll.
        let (hosting, controller) = try await makeHosting(
            language: .english,
            authorization: .allowed,
            devices: (1...13).map(summaryDevice),
            batteryLevels: [:],
            listOptions: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 13, order: [])
        )
        defer { controller.deactivate() }
        hosting.layoutSubtreeIfNeeded()

        XCTAssertNotNil(
            firstScrollView(in: hosting),
            "13 rows pass the bound, so they have to scroll"
        )
    }

    private func summaryDevice(_ index: Int) -> BluetoothDevice {        BluetoothDevice(
            id: String(format: "AA:00:00:00:00:%02X", index),
            name: "Device \(index)",
            kind: .audio,
            isConnected: true
        )
    }

    /// The first `NSScrollView` under a rendered view, which is how SwiftUI backs
    /// a `ScrollView`.
    private func firstScrollView(in view: NSView) -> NSScrollView? {
        var pending = view.subviews
        while let next = pending.popLast() {
            if let scrollView = next as? NSScrollView { return scrollView }
            pending.append(contentsOf: next.subviews)
        }
        return nil
    }

    /// The list row must truncate a long device name, not wrap it: the popover
    /// has a fixed width, so a wrapped row would double its height and push the
    /// panel taller. The old assertions could not catch that — the view is
    /// built with `.frame(width: 330)`, so `fittingSize.width` is always 330 and
    /// the height assertions are direction-only. Rendering the same list with a
    /// short and a very long name makes the no-wrap requirement falsifiable: a
    /// wrapped row cannot keep the same height.
    func testLongDeviceNameTruncatesInsteadOfWrapping() async throws {
        let shortNames = (1...3).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Device \(index)",
                kind: .audio,
                isConnected: index == 1
            )
        }
        let longNames = (1...3).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Supercalifragilistic AirPods Max Pro Ultra Wireless Headphones \(index)",
                kind: .audio,
                isConnected: index == 1
            )
        }
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        for language in [AppLanguage.english, .simplifiedChinese] {
            let short = try await render(
                language: language,
                authorization: .allowed,
                devices: shortNames,
                listOptions: options,
                named: "bluetooth-short-names-\(language.rawValue)"
            )
            let long = try await render(
                language: language,
                authorization: .allowed,
                devices: longNames,
                listOptions: options,
                named: "bluetooth-long-names-\(language.rawValue)"
            )

            XCTAssertEqual(short.width, 330, accuracy: 0.5)
            XCTAssertEqual(long.width, 330, accuracy: 0.5)
            XCTAssertEqual(
                short.height,
                long.height,
                accuracy: 1,
                "a long device name must truncate, not wrap, in \(language.rawValue): "
                    + "short \(short.height), long \(long.height)"
            )
        }
    }

    /// Exactly as many devices as the limit: everything fits, so the Expand
    /// control must not appear. The check compares the render against the same
    /// two rows with the expansion control forced on (a zero limit keeps the
    /// control and drops the rows), which is only valid if the control really
    /// adds height — so that side is pinned here too.
    func testListAtTheLimitRendersWithoutAnExpansionControl() async throws {
        let devices = (1...2).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Device \(index)",
                kind: .audio,
                isConnected: true
            )
        }
        let moreDevices = (1...5).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Device \(index)",
                kind: .audio,
                isConnected: true
            )
        }

        for language in [AppLanguage.english, .simplifiedChinese] {
            let atLimit = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 2, order: []),
                named: "bluetooth-at-limit-\(language.rawValue)"
            )
            let overTheLimit = try await render(
                language: language,
                authorization: .allowed,
                devices: moreDevices,
                listOptions: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 2, order: []),
                named: "bluetooth-over-limit-\(language.rawValue)"
            )
            let controlOnly = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 0, order: []),
                named: "bluetooth-at-limit-control-only-\(language.rawValue)"
            )

            XCTAssertEqual(atLimit.width, 330, accuracy: 0.5)
            XCTAssertGreaterThan(
                overTheLimit.height,
                atLimit.height,
                "both renders show the same two rows, so the extra height can only be the "
                    + "expansion control, which must appear when the list overflows the limit "
                    + "and must be absent when it does not, in \(language.rawValue)"
            )
            // The same check from the other side: `maxVisibleDevices == 0` over
            // these two devices shows no rows at all, so this height is the
            // ordinary row plus the expansion control alone. The two fitting
            // rows are taller than that, which is what proves no control leaked
            // into the at-limit render.
            XCTAssertGreaterThan(
                atLimit.height,
                controlOnly.height,
                "two fitting rows must stay taller than the rows-free expansion control "
                    + "in \(language.rawValue)"
            )
        }
    }

    /// The device rows must line up under the section's own icon: the row's icon
    /// column has to match the summary row's, or every device glyph sits a few
    /// points left of the Bluetooth glyph and every name left of the title. This
    /// measures the rendered text leading of the title against the first row's,
    /// which is the property the eye checks.
    func testDeviceRowsLineUpWithTheSectionTitle() async throws {
        let devices = [
            BluetoothDevice(
                id: "AA:00:00:00:00:01",
                name: "Device 1",
                kind: .audio,
                isConnected: true
            )
        ]

        for language in [AppLanguage.english, .simplifiedChinese] {
            let leadings = try await textLineLeadings(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(
                    showsList: true,
                    maxVisibleDevices: 5,
                    order: []
                )
            )

            let title = try XCTUnwrap(leadings.first, "the title line must render")
            let firstRow = try XCTUnwrap(
                leadings.dropFirst().first,
                "the first device row must render"
            )
            XCTAssertEqual(
                firstRow,
                title,
                accuracy: 1.5,
                "a device row's name must start where the section title starts in \(language.rawValue)"
            )
        }
    }

    private func render(
        language: AppLanguage,
        authorization: BluetoothAuthorizationStatus,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        listOptions: BluetoothDeviceListOptions = .standard,
        named name: String
    ) async throws -> NSSize {
        let (hosting, controller) = try await makeHosting(
            language: language,
            authorization: authorization,
            devices: devices,
            batteryLevels: batteryLevels,
            listOptions: listOptions
        )
        defer { controller.deactivate() }

        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_BLUETOOTH_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
        return hosting.fittingSize
    }

    /// Builds the panel's Bluetooth row with its layout settled, so a test can
    /// measure what actually rendered instead of what the code intended.
    private func makeHosting(
        language: AppLanguage,
        authorization: BluetoothAuthorizationStatus,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        listOptions: BluetoothDeviceListOptions,
        nearbyDevices: [NearbyBluetoothBatteryDevice] = [],
        showsBatteryLevels: Bool = true,
        showsNearbyBatteryDevices: Bool = false
    ) async throws -> (NSView, BluetoothDeviceController) {
        let suite = "StatusTrioCoreTests.BluetoothSummary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))

        let notifications = NotificationCenter()
        let nearbyScanner = SummaryNearbyBatteryScanner()
        let controller = BluetoothDeviceController(
            worker: SummaryBluetoothDeviceReader(result: .success(devices)),
            stateMonitor: SummaryBluetoothStateMonitor(
                authorization: authorization,
                managerState: authorization == .allowed ? .poweredOn : .unknown
            ),
            batteryReader: SummaryBluetoothBatteryReader(result: batteryLevels),
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications,
            nearbyBatteryScanner: nearbyScanner
        )
        if authorization == .allowed {
            controller.activate()
        } else {
            controller.prepareForPresentation()
        }
        if !nearbyDevices.isEmpty {
            controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        }

        let view = BluetoothStatusView(
            controller: controller,
            mobileBatteryController: MobileBatteryController(),
            showsBatteryLevels: showsBatteryLevels,
            showsNearbyBatteryDevices: showsNearbyBatteryDevices,
            listOptions: listOptions,
            onRequestAuthorization: {},
            onOpenBluetoothSettings: {},
            onOpenBluetoothPermissionSettings: {}
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        // Let the controller publish the fixture and the row settle.
        try await Task.sleep(for: .milliseconds(50))
        nearbyScanner.publish(nearbyDevices)
        try await Task.sleep(for: .milliseconds(50))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return (hosting, controller)
    }

    /// Where each rendered text line starts, in points, skipping the section's
    /// icon column: index 0 is the title line and the rest are the device rows.
    /// This is how a test sees the alignment the eye sees.
    private func textLineLeadings(
        language: AppLanguage,
        authorization: BluetoothAuthorizationStatus,
        devices: [BluetoothDevice],
        listOptions: BluetoothDeviceListOptions
    ) async throws -> [CGFloat] {
        let (hosting, controller) = try await makeHosting(
            language: language,
            authorization: authorization,
            devices: devices,
            batteryLevels: [:],
            listOptions: listOptions
        )
        defer { controller.deactivate() }

        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
        // Past the icon column (the harness pads the panel by 14 points), so the
        // scan only ever measures text.
        let textStart = Int((14 + BluetoothPanelMetrics.iconColumnWidth) * scale) + 1

        func isDark(_ x: Int, _ y: Int) -> Bool {
            guard let color = bitmap.colorAt(x: x, y: y) else { return false }
            let luminance = 0.299 * color.redComponent
                + 0.587 * color.greenComponent
                + 0.114 * color.blueComponent
            return luminance < 0.55
        }

        var bands: [[(y: Int, leftmost: Int)]] = []
        var lineIsOpen = false
        for y in 0..<bitmap.pixelsHigh {
            var hasText = false
            var probe = textStart
            while probe < bitmap.pixelsWide {
                if isDark(probe, y) {
                    hasText = true
                    break
                }
                probe += 4
            }

            guard hasText else {
                lineIsOpen = false
                continue
            }

            var leftmost = textStart
            while leftmost < bitmap.pixelsWide, !isDark(leftmost, y) {
                leftmost += 1
            }
            if lineIsOpen {
                bands[bands.count - 1].append((y, leftmost))
            } else {
                bands.append([(y, leftmost)])
                lineIsOpen = true
            }
        }

        // The line's leading edge is the band's leftmost pixel, not its top row's:
        // the top row only catches the tallest glyphs, whose own leading edge sits
        // well inside the line. Bands of a row or two are antialiasing slivers,
        // not text lines.
        return bands
            .filter { $0.count >= 4 }
            .map { band in
                let leftmost = band.map(\.leftmost).min() ?? textStart
                return CGFloat(leftmost) / scale
            }
    }
}

private final class SummaryBluetoothDeviceReader: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(result)
    }
}

private final class SummaryBluetoothBatteryReader: BluetoothBatteryReading {
    private let result: [String: BluetoothBatteryLevel]

    init(result: [String: BluetoothBatteryLevel]) {
        self.result = result
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion(result)
    }
}

@MainActor
private final class SummaryNearbyBatteryScanner: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    private(set) var isRunning = false
    private(set) var isScanning = false

    func start() { isRunning = true }
    func refresh() {}
    func stop() {
        isRunning = false
        isScanning = false
    }

    func publish(_ devices: [NearbyBluetoothBatteryDevice]) {
        onDevicesChanged?(devices)
    }
}

@MainActor
private final class SummaryBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus
    private let managerState: BluetoothManagerState

    init(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        self.authorization = authorization
        self.managerState = managerState
    }

    func start() {
        onStateChange?(authorization, managerState)
    }

    func stop() {}
}
