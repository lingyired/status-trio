import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarInstanceDemandCoordinatorTests: XCTestCase {
    final class Recorder {
        var registered: [String: Set<HardwareMetricID>] = [:]
        var unregistered: [String] = []
    }

    private func makeCoordinator() -> (MenuBarInstanceDemandCoordinator, Recorder) {
        let recorder = Recorder()
        let coordinator = MenuBarInstanceDemandCoordinator(
            register: { id, metrics in recorder.registered[id] = metrics },
            unregister: { id in recorder.unregistered.append(id); recorder.registered[id] = nil }
        )
        return (coordinator, recorder)
    }

    private func instance(_ metric: MenuBarMetricID, enabled: Bool = true) -> MenuBarInstance {
        MenuBarInstance(isEnabled: enabled, top: MenuBarLine(segments: [.metric(metric)]))
    }

    func testDisabledInstanceHasNoDemand() {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.setInstances([instance(.cpuUsage, enabled: false)])
        XCTAssertTrue(coordinator.registeredOwners.isEmpty)
        XCTAssertTrue(recorder.registered.isEmpty)
    }

    func testOwnerIDFormat() {
        let (coordinator, _) = makeCoordinator()
        let a = instance(.cpuUsage)
        coordinator.setInstances([a])
        XCTAssertEqual(MenuBarInstanceDemandCoordinator.ownerID(for: a.id), "menuBarInstance:\(a.id.uuidString)")
        XCTAssertNotNil(coordinator.registeredOwners[MenuBarInstanceDemandCoordinator.ownerID(for: a.id)])
    }

    func testSharedMetricRegisteredOnce() {
        let (coordinator, _) = makeCoordinator()
        coordinator.setInstances([instance(.cpuUsage), instance(.cpuUsage)])
        XCTAssertEqual(coordinator.mergedMetrics.filter { $0 == .cpuUsage }.count, 1)
        XCTAssertEqual(coordinator.mergedMetrics, [.cpuUsage])
    }

    func testRemovingInstanceUnregistersOnlyItsOwner() {
        let (coordinator, recorder) = makeCoordinator()
        let a = instance(.cpuUsage)
        let b = instance(.gpuUsage)
        coordinator.setInstances([a, b])
        let aID = MenuBarInstanceDemandCoordinator.ownerID(for: a.id)
        coordinator.setInstances([b])
        XCTAssertEqual(recorder.unregistered, [aID])
        XCTAssertNil(coordinator.registeredOwners[aID])
        XCTAssertNotNil(coordinator.registeredOwners[MenuBarInstanceDemandCoordinator.ownerID(for: b.id)])
    }

    func testDerivedDiskMetricsRegisterEveryCapacitySample() {
        let (coordinator, _) = makeCoordinator()
        let combined = instance(.diskCombinedUsagePercent)
        XCTAssertEqual(coordinator.metricSet(for: combined),
                       [.diskUsedBytes, .diskFreeBytes,
                        .diskExternalTotalBytes, .diskExternalFreeBytes])
    }

    func testWiFiStatusNeedsNoHardwareDemand() {
        let (coordinator, _) = makeCoordinator()
        let wifi = instance(.wifiConnectionStatus)
        XCTAssertTrue(coordinator.metricSet(for: wifi).isEmpty)
    }
}
