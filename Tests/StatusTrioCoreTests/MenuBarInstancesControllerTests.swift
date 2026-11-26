import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarInstancesControllerTests: XCTestCase {
    @MainActor
    final class FakeHandle: MenuBarStatusItemHandle {
        var length: CGFloat = 0
        var isVisible = true
        var autosaveName: String?
        var hasRemovalBehavior = false
        var image: NSImage?
        var button: NSStatusBarButton? { nil }
    }

    @MainActor
    final class FakeBar: MenuBarStatusBarProviding {
        var made: [FakeHandle] = []
        func makeItem() -> MenuBarStatusItemHandle {
            let handle = FakeHandle()
            made.append(handle)
            return handle
        }
    }

    private var removed: [UUID] = []

    private func makeController() -> (MenuBarInstancesController, FakeBar) {
        let bar = FakeBar()
        removed = []
        let controller = MenuBarInstancesController(statusBar: bar, onUserRemoved: { [weak self] id in
            self?.removed.append(id)
        })
        return (controller, bar)
    }

    private func instance(_ metric: MenuBarMetricID, enabled: Bool = true) -> MenuBarInstance {
        MenuBarInstance(isEnabled: enabled, top: MenuBarLine(segments: [.metric(metric)]))
    }

    func testCreateOneItemPerDisplayableInstance() {
        let (controller, _) = makeController()
        controller.sync(MenuBarInstancesConfiguration(instances: [instance(.cpuUsage), instance(.gpuUsage)]))
        XCTAssertEqual(controller.itemIDs.count, 2)
    }

    func testAutosaveNamePerInstance() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage)
        controller.sync(MenuBarInstancesConfiguration(instances: [a]))
        XCTAssertEqual(controller.item(for: a.id)?.autosaveName, "statusTrio.menuBarInstance.\(a.id.uuidString)")
    }

    func testRemovalBehaviorEnabled() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage)
        controller.sync(MenuBarInstancesConfiguration(instances: [a]))
        XCTAssertTrue(controller.item(for: a.id)?.hasRemovalBehavior ?? false)
    }

    func testLengthMatchesRenderState() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage)
        controller.sync(MenuBarInstancesConfiguration(instances: [a]))
        controller.update(id: a.id, renderState: MenuBarRenderState(image: nil, width: 57))
        XCTAssertEqual(controller.item(for: a.id)?.length, 57)
    }

    func testDisableOnlyHidesNotRemoves() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage, enabled: true)
        controller.sync(MenuBarInstancesConfiguration(instances: [a]))
        var disabled = a
        disabled.isEnabled = false
        controller.sync(MenuBarInstancesConfiguration(instances: [disabled]))
        XCTAssertTrue(controller.itemIDs.contains(a.id))
        XCTAssertEqual(controller.item(for: a.id)?.isVisible, false)
    }

    func testProgrammaticVisibleDoesNotCallOnUserRemoved() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage)
        controller.sync(MenuBarInstancesConfiguration(instances: [a]))
        var disabled = a
        disabled.isEnabled = false
        controller.sync(MenuBarInstancesConfiguration(instances: [disabled]))
        XCTAssertTrue(removed.isEmpty)
    }

    func testExternalVisibleFalseCallsOnUserRemovedOnce() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage)
        controller.sync(MenuBarInstancesConfiguration(instances: [a]))
        controller.notifyExternalVisibilityChange(id: a.id, newVisible: false)
        XCTAssertEqual(removed, [a.id])
    }

    func testDeletingInstanceRemovesItem() {
        let (controller, _) = makeController()
        let a = instance(.cpuUsage)
        let b = instance(.gpuUsage)
        controller.sync(MenuBarInstancesConfiguration(instances: [a, b]))
        controller.sync(MenuBarInstancesConfiguration(instances: [b]))
        XCTAssertFalse(controller.itemIDs.contains(a.id))
        XCTAssertTrue(controller.itemIDs.contains(b.id))
    }
}
