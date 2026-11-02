import AppKit
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BrightnessMonitorTests: XCTestCase {
    private final class FakeCatalog: DisplayCatalogProviding {
        var displays: [DisplayDescriptor]
        init(_ displays: [DisplayDescriptor]) { self.displays = displays }
        func currentDisplays() -> [DisplayDescriptor] { displays }
    }

    private final class QuietTransport: DDCFeatureTransport, @unchecked Sendable {
        func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
        func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .reply(DDCVolumeReply(current: 50, maximum: 100)) }
        func read(_ target: DDCDisplayTarget, feature: UInt8) -> DDCVolumeReadResult { read(target) }
        func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { true }
        func write(_ target: DDCDisplayTarget, value: UInt16, feature: UInt8) -> Bool { true }
    }

    private func descriptor(_ id: String) -> DisplayDescriptor {
        DisplayDescriptor(id: id, name: id, isBuiltin: false, displayID: 1)
    }

    func testTopologyChangeRebuildsAndDropsRetainedBackend() {
        let catalog = FakeCatalog([descriptor("A")])
        var made: [DDCBrightnessCoordinator] = []
        let monitor = BrightnessMonitor(
            catalog: catalog,
            makeDDC: { _, onUpdate in
                let coordinator = DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
                made.append(coordinator)
                return coordinator
            }
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(made.count, 1, "Opening the section builds one backend per display")
        let first = made[0]
        let firstGeneration = first.generation

        catalog.displays = [descriptor("A"), descriptor("B")]
        monitor.topologyChanged()

        XCTAssertGreaterThan(first.generation, firstGeneration,
                             "The retained display's old backend must be invalidated on a topology change")
        XCTAssertEqual(made.count, 3, "A hot-plug rebuilds the retained backend and adds the new display")
        monitor.stop()
    }

    func testScreenParameterNotificationTriggersTopologyRebuild() {
        let catalog = FakeCatalog([descriptor("A")])
        let center = NotificationCenter()
        var made: [DDCBrightnessCoordinator] = []
        let monitor = BrightnessMonitor(
            catalog: catalog,
            makeDDC: { _, onUpdate in
                let coordinator = DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
                made.append(coordinator)
                return coordinator
            },
            notificationCenter: center
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(made.count, 1)

        catalog.displays = [descriptor("A"), descriptor("B")]
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let rebuilt = expectation(description: "screen notification rebuilds the brightness list")
        DispatchQueue.main.async { rebuilt.fulfill() }
        wait(for: [rebuilt], timeout: 2)
        XCTAssertEqual(made.count, 3, "The screen-parameters notification must rebuild the list")
        monitor.stop()
    }

}
