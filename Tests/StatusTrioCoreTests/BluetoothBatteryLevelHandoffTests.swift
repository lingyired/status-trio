import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Two surfaces share one "read battery levels" flag, and SwiftUI runs the
/// outgoing surface's `onDisappear` *after* the incoming one's `onAppear`, so a
/// surface that released the flag on disappear switched off the read the other
/// one had just asked for.
///
/// The panel's inline list replaced the Bluetooth detail page, so the second
/// surface here is a stand-in: what these tests pin is the claim mechanism's
/// behaviour under that hook ordering, not the page that used to exercise it.
@MainActor
final class BluetoothBatteryLevelHandoffTests: XCTestCase {
    func testASecondSurfaceKeepsReadingLevelsAfterTheSummaryLeaves() async {
        let batteryReader = HandoffBatteryReader()
        let controller = BluetoothDeviceController(
            worker: HandoffDeviceReader(),
            stateMonitor: HandoffStateMonitor(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let model = HandoffModel()
        controller.activate()
        await settle()

        let hosting = NSHostingView(rootView: HandoffRoot(
            controller: controller,
            localization: makeLocalization(),
            model: model
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 200)
        hosting.layoutSubtreeIfNeeded()
        await settle()
        XCTAssertTrue(controller.isBatteryLevelsRequested, "the summary needs the AirPods level")

        // Tap the Bluetooth row. The state change happens inside the view, which
        // is what makes SwiftUI run the outgoing summary's hook last.
        model.showsDetail = true
        await settle()

        XCTAssertTrue(
            controller.isBatteryLevelsRequested,
            "the outgoing summary must not release the read the detail page asked for"
        )
        XCTAssertEqual(
            controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.summary,
            "L 81% · R 79%",
            "the detail page must receive the levels it reads"
        )

        // Going back to the summary: whichever order SwiftUI runs the two
        // hooks in, the summary keeps its own claim, so the read stays on.
        model.showsDetail = false
        await settle()
        XCTAssertTrue(controller.isBatteryLevelsRequested)

        // Closing the popover releases every claim.
        controller.deactivate()
        XCTAssertFalse(controller.isBatteryLevelsRequested)
    }

    /// The setting can change while the summary stays on screen, and then the
    /// row's `onDisappear` never runs. The claim has to be dropped where the
    /// change arrives: otherwise the read keeps running and the level the user
    /// just switched off stays on screen until they visit another page and come
    /// back.
    func testTurningTheSettingOffReleasesTheSummaryClaimImmediately() async {
        let batteryReader = HandoffBatteryReader()
        let controller = BluetoothDeviceController(
            worker: HandoffDeviceReader(),
            stateMonitor: HandoffStateMonitor(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let model = HandoffModel()
        controller.activate()
        await settle()

        let hosting = NSHostingView(rootView: HandoffRoot(
            controller: controller,
            localization: makeLocalization(),
            model: model
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 200)
        hosting.layoutSubtreeIfNeeded()
        await settle()
        XCTAssertTrue(controller.isBatteryLevelsRequested, "the summary claims while the setting is on")

        model.showsBatteryLevels = false
        await settle()

        XCTAssertFalse(
            controller.isBatteryLevelsRequested,
            "the row kept reading after the setting was switched off"
        )
        XCTAssertTrue(
            controller.batteryLevels.isEmpty,
            "levels outlived the claim that asked for them"
        )

        // Back on: the row claims again, so the level returns without a detour
        // through the detail page.
        model.showsBatteryLevels = true
        await settle()

        XCTAssertTrue(controller.isBatteryLevelsRequested, "the row never claimed the read again")
        XCTAssertFalse(controller.batteryLevels.isEmpty, "the level never came back")
    }

    /// The regression test above only means something because the outgoing
    /// summary's hook really does run last. This pins that ordering, so it can
    /// never silently stop covering the bug.
    func testSwiftUIRunsTheOutgoingSummaryHookLast() async {
        let order = HandoffOrderRecorder()
        let model = HandoffModel()
        let hosting = NSHostingView(rootView: HandoffOrderProbe(order: order, model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        hosting.layoutSubtreeIfNeeded()
        await settle()

        model.showsDetail = true
        await settle()

        let entries = order.entries
        guard let detailAppear = entries.firstIndex(of: "detail.appear"),
              let summaryDisappear = entries.firstIndex(of: "summary.disappear") else {
            XCTFail("expected both hooks to run, got \(entries)")
            return
        }
        XCTAssertLessThan(
            detailAppear, summaryDisappear,
            "the outgoing summary runs last, which is why it cannot own the flag"
        )
    }

    private func makeLocalization() -> Localization {
        let suite = "StatusTrioCoreTests.BluetoothHandoff.\(UUID().uuidString)"
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }
}

@MainActor
final class HandoffModel: ObservableObject {
    @Published var showsDetail = false
    /// The setting the summary and the detail page both read. It lives here so a
    /// test can flip it while the summary stays on screen.
    @Published var showsBatteryLevels = true
}

/// Holds both panels, so switching between them is one SwiftUI update rather
/// than a root-view replacement.
private struct HandoffRoot: View {
    let controller: BluetoothDeviceController
    let localization: Localization
    @ObservedObject var model: HandoffModel

    var body: some View {
        Group {
            if model.showsDetail {
                HandoffSecondSurface(controller: controller)
                    .id("detail")
            } else {
                BluetoothStatusView(
                    controller: controller,
                    mobileBatteryController: MobileBatteryController(),
                    showsBatteryLevels: model.showsBatteryLevels,
                    // These tests pin the pre-list summary shape and the level
                    // claim it makes, so the list is explicitly off. Leaving it
                    // on (the `.standard` default) would render the device list
                    // under the row and stop the summary from being the shape
                    // these assertions were written for.
                    listOptions: BluetoothDeviceListOptions(
                        showsList: false,
                        maxVisibleDevices: 5,
                        order: []
                    ),
                    onRequestAuthorization: {}, onOpenBluetoothSettings: {},
                    onOpenBluetoothPermissionSettings: {}
                )
                .id("summary")
            }
        }
        .environmentObject(localization)
    }
}

/// Stands in for the surface that used to sit beside the summary. It claims the
/// same token the detail page claimed, so the ordering regression these tests
/// exist for is still exercised now that the page itself is gone.
private struct HandoffSecondSurface: View {
    let controller: BluetoothDeviceController

    var body: some View {
        Text("detail")
            .onAppear { controller.requestBatteryLevels("bluetooth.detail") }
            .onDisappear { controller.releaseBatteryLevels("bluetooth.detail") }
    }
}

@MainActor
private final class HandoffOrderRecorder {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}

private struct HandoffOrderProbe: View {
    let order: HandoffOrderRecorder
    @ObservedObject var model: HandoffModel

    var body: some View {
        Group {
            if model.showsDetail {
                Text("detail")
                    .id("detail")
                    .onAppear { order.record("detail.appear") }
                    .onDisappear { order.record("detail.disappear") }
            } else {
                Text("summary")
                    .id("summary")
                    .onAppear { order.record("summary.appear") }
                    .onDisappear { order.record("summary.disappear") }
            }
        }
    }
}

private final class HandoffDeviceReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
    }
}

@MainActor
private final class HandoffStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class HandoffBatteryReader: BluetoothBatteryReading {
    private(set) var readCount = 0

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        readCount += 1
        completion([
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F", main: nil, left: 81, right: 79, caseLevel: nil)
        ])
    }
}
