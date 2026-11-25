import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class HardwarePanelThrottleTests: XCTestCase {
    private func sample(_ value: Double, at date: Date) -> HardwareMetricSample {
        HardwareMetricSample(value: value, unit: .percent, sampledAt: date,
                             source: .mach, availability: .measured)
    }

    func testPanelAdoptsASlowGroupOnlyWhenItsCadenceElapses() {
        let observable = HardwareMonitorObservable()
        let t0 = Date(timeIntervalSince1970: 1_000)
        observable.panelDisplayCadence = { group in group == .cpuUsage ? 8 : 0 }

        var first = HardwareMetricsSnapshot.empty
        first.samples[.cpuUsage] = sample(10, at: t0)
        observable.update(first, now: t0)
        XCTAssertEqual(observable.snapshot.cpuUsage.value, 10, "live tracks the sample")
        XCTAssertEqual(observable.panelSnapshot.cpuUsage.value, 10, "first frame is immediate")

        var second = first
        second.samples[.cpuUsage] = sample(20, at: t0.addingTimeInterval(2))
        observable.update(second, now: t0.addingTimeInterval(2))
        XCTAssertEqual(observable.snapshot.cpuUsage.value, 20, "icons still get every sample")
        XCTAssertEqual(observable.panelSnapshot.cpuUsage.value, 10, "panel has not reached its cadence")

        var third = second
        third.samples[.cpuUsage] = sample(30, at: t0.addingTimeInterval(9))
        observable.update(third, now: t0.addingTimeInterval(9))
        XCTAssertEqual(observable.snapshot.cpuUsage.value, 30)
        XCTAssertEqual(observable.panelSnapshot.cpuUsage.value, 30, "panel adopts the latest sample when due")
    }

    func testZeroCadenceKeepsThePanelInStepWithLive() {
        let observable = HardwareMonitorObservable()
        let t0 = Date(timeIntervalSince1970: 2_000)
        observable.panelDisplayCadence = { _ in 0 }

        var first = HardwareMetricsSnapshot.empty
        first.samples[.cpuUsage] = sample(10, at: t0)
        observable.update(first, now: t0)

        var second = first
        second.samples[.cpuUsage] = sample(20, at: t0.addingTimeInterval(1))
        observable.update(second, now: t0.addingTimeInterval(1))
        XCTAssertEqual(observable.panelSnapshot.cpuUsage.value, 20)
    }

    func testGroupsThrottleIndependently() {
        let observable = HardwareMonitorObservable()
        let t0 = Date(timeIntervalSince1970: 3_000)
        observable.panelDisplayCadence = { group in group == .cpuUsage ? 8 : 0 }

        var first = HardwareMetricsSnapshot.empty
        first.samples[.cpuUsage] = sample(10, at: t0)
        first.samples[.networkDownload] = sample(1, at: t0)
        observable.update(first, now: t0)

        var second = first
        second.samples[.cpuUsage] = sample(20, at: t0.addingTimeInterval(2))
        second.samples[.networkDownload] = sample(2, at: t0.addingTimeInterval(2))
        observable.update(second, now: t0.addingTimeInterval(2))

        XCTAssertEqual(observable.panelSnapshot.cpuUsage.value, 10, "CPU group is throttled")
        XCTAssertEqual(observable.panelSnapshot.networkDownload.value, 2, "network group is not")
    }
}
