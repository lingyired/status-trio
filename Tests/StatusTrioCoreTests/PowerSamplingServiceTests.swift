import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class PowerSamplingServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_555_974)

    private func makeService(
        reader: @escaping @Sendable (_ includeAuxiliaryRails: Bool) -> PowerSamplingReading
    ) -> PowerSamplingService {
        PowerSamplingService(reader: reader)
    }

    func testEverySurfaceSharesOneCadenceAndOnlyTheLastDemandStopsIt() {
        let service = makeService { _ in .empty }

        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(PowerSamplingService.interval, .seconds(2))

        service.begin(.icon)
        XCTAssertTrue(service.isRunning)

        service.begin(.panel)
        service.begin(.details)

        // Closing the panel and the details page must not cut the icon's sample.
        service.end(.panel)
        service.end(.details)
        XCTAssertTrue(service.isRunning)

        service.end(.icon)
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.demands.isEmpty)
    }

    func testRepeatedBeginIsIdempotent() {
        let service = makeService { _ in .empty }
        service.begin(.icon)
        service.begin(.icon)
        XCTAssertEqual(service.demands, [.icon])
        service.end(.icon)
        XCTAssertFalse(service.isRunning, "One end must release a demand registered twice")
    }

    func testASuccessfulReadPublishesTheSample() async {
        let sample = SystemPowerSample(watts: 17.5, readAt: now)
        let service = makeService { _ in PowerSamplingReading(system: sample) }

        service.begin(.icon)
        await waitForSample(service)
        XCTAssertEqual(service.systemPower, sample)

        service.end(.icon)
        XCTAssertNil(service.systemPower, "A stopped sampler must not leave a stale value behind")
    }

    func testAnUnreadableSampleIsNeverPublishedAsZero() async {
        let service = makeService { _ in .empty }
        service.begin(.icon)
        // Give the background read a chance to land before asserting.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(service.systemPower)
        service.end(.icon)
    }

    func testPowerInfoBarDemandReadsThenClearsAuxiliaryRails() async {
        let input = SystemPowerSample(watts: 30.2, readAt: now)
        let packed = BatteryPowerSample(volts: 12, amps: 1.0, updatedAt: now)
        let system = SystemPowerSample(watts: 18.0, readAt: now)
        let service = makeService { _ in
            PowerSamplingReading(system: system, input: input, battery: packed)
        }

        service.begin(.panel)
        await waitFor { service.systemPower != nil }
        XCTAssertNil(service.inputPower, "The panel alone must not pay for the auxiliary rails")

        service.begin(.powerInfoBar)
        await waitFor { service.inputPower != nil }
        XCTAssertEqual(service.inputPower, input)
        XCTAssertEqual(service.batteryPower, packed)

        service.end(.powerInfoBar)
        XCTAssertNil(service.inputPower, "Ending the info-bar demand clears its rails")
        XCTAssertNil(service.batteryPower)
        XCTAssertNotNil(service.systemPower, "The panel's whole-machine sample must survive")
        service.end(.panel)
    }

    func testStopAllReleasesEveryDemand() {
        let service = makeService { _ in .empty }
        service.begin(.icon)
        service.begin(.panel)
        service.begin(.details)
        service.stopAll()
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.demands.isEmpty)
    }

    private func waitForSample(_ service: PowerSamplingService) async {
        await waitFor { service.systemPower != nil }
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
