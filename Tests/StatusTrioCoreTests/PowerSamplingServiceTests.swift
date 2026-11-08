import Combine
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

    func testIconOnlyDemandSamplesEveryFiveSeconds() {
        let service = makeService { _ in .empty }

        service.begin(.icon)
        XCTAssertEqual(service.samplingInterval, .seconds(5))
        XCTAssertEqual(PowerSamplingService.interval, .seconds(2))

        service.begin(.panel)
        XCTAssertEqual(service.samplingInterval, .seconds(2))

        service.end(.panel)
        XCTAssertEqual(
            service.samplingInterval,
            .seconds(5),
            "Closing the panel restores the icon-only cadence"
        )

        service.end(.icon)
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

    func testCompletedFirstReadTracksTheRunningSession() async {
        let service = makeService { _ in
            PowerSamplingReading(system: SystemPowerSample(watts: 17.5, readAt: Date()))
        }
        XCTAssertFalse(service.hasCompletedFirstRead)

        service.begin(.panel)
        await waitForSample(service)
        XCTAssertTrue(service.hasCompletedFirstRead)

        service.end(.panel)
        XCTAssertFalse(
            service.hasCompletedFirstRead,
            "A stopped sampler asks the next open to reserve its skeleton again"
        )
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

    func testEndingAuxiliaryDemandRejectsInFlightRailsButKeepsIconSystemPower() async {
        let initialSystem = SystemPowerSample(watts: 18, readAt: now)
        let nextSystem = SystemPowerSample(watts: 21, readAt: now)
        let input = SystemPowerSample(watts: 30, readAt: now)
        let battery = BatteryPowerSample(volts: 12, amps: 1, updatedAt: now)
        let initialDelivered = expectation(description: "initial icon power delivered")
        let auxiliaryReadStarted = expectation(description: "auxiliary read is in flight")
        let nextSystemDelivered = expectation(description: "in-flight system power remains useful to icon")
        let releaseAuxiliaryRead = DispatchSemaphore(value: 0)
        let service = makeService { includeAuxiliaryRails in
            guard includeAuxiliaryRails else { return PowerSamplingReading(system: initialSystem) }
            auxiliaryReadStarted.fulfill()
            guard releaseAuxiliaryRead.wait(timeout: .now() + 5) == .success else { return .empty }
            return PowerSamplingReading(system: nextSystem, input: input, battery: battery)
        }
        var observations: Set<AnyCancellable> = []
        service.$systemPower.sink { sample in
            if sample == initialSystem { initialDelivered.fulfill() }
            if sample == nextSystem { nextSystemDelivered.fulfill() }
        }.store(in: &observations)
        defer {
            releaseAuxiliaryRead.signal()
            service.stopAll()
            observations.removeAll()
        }
        service.begin(.icon)
        await fulfillment(of: [initialDelivered], timeout: 1)
        service.begin(.powerInfoBar)
        await fulfillment(of: [auxiliaryReadStarted], timeout: 1)

        service.end(.powerInfoBar)
        releaseAuxiliaryRead.signal()
        await fulfillment(of: [nextSystemDelivered], timeout: 1)

        XCTAssertEqual(service.demands, [.icon])
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(service.systemPower, nextSystem)
        XCTAssertNil(service.inputPower, "An ended demand must not be repopulated by its late input rail")
        XCTAssertNil(service.batteryPower, "An ended demand must not be repopulated by its late battery rail")
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

    func testSuspensionStopsTheLoopWithoutForgettingDemands() async {
        let sample = SystemPowerSample(watts: 12, readAt: now)
        let service = makeService { _ in PowerSamplingReading(system: sample) }
        service.begin(.icon)
        await waitForSample(service)

        service.setSuspended(true)
        XCTAssertFalse(service.isRunning, "sleep must stop the SMC loop")
        XCTAssertEqual(service.demands, [.icon], "sleep must not forget the icon's demand")
        XCTAssertNil(service.systemPower, "a suspended sampler leaves no stale reading behind")

        service.setSuspended(false)
        XCTAssertTrue(service.isRunning, "resume restarts the loop for the surviving demand")
        await waitForSample(service)
        XCTAssertEqual(service.systemPower, sample)

        service.end(.icon)
    }

    func testBeginWhileSuspendedRegistersDemandWithoutStartingTheLoop() {
        let service = makeService { _ in .empty }
        service.setSuspended(true)

        service.begin(.icon)
        XCTAssertFalse(service.isRunning, "no surface can show watts while suspended")
        XCTAssertEqual(service.demands, [.icon], "the demand survives until resume")

        service.setSuspended(false)
        XCTAssertTrue(service.isRunning, "resume restarts the loop for the accumulated demand")
        service.end(.icon)
    }

    func testRepeatedSuspensionCallsAreIdempotent() {
        let service = makeService { _ in .empty }
        service.setSuspended(true)
        service.setSuspended(true)
        service.begin(.icon)
        XCTAssertFalse(service.isRunning)

        service.setSuspended(false)
        service.setSuspended(false)
        XCTAssertTrue(service.isRunning)
        service.end(.icon)
        XCTAssertFalse(service.isRunning)
    }

    func testRemovingLastDemandWhileSuspendedDoesNotRestartOnWake() {
        let service = makeService { _ in .empty }
        service.begin(.icon)
        service.setSuspended(true)
        service.end(.icon)

        service.setSuspended(false)

        XCTAssertTrue(service.demands.isEmpty)
        XCTAssertFalse(service.isRunning, "wake must not restore a surface that closed during sleep")
        XCTAssertNil(service.systemPower)
    }

    func testResumeRejectsPreSleepReadAndImmediatelyReadsCurrentDemand() async {
        let stale = SystemPowerSample(watts: 18, readAt: now)
        let fresh = SystemPowerSample(watts: 24, readAt: now.addingTimeInterval(1))
        let started = expectation(description: "pre-sleep read started")
        let delivered = expectation(description: "fresh resume sample delivered")
        let gate = DispatchSemaphore(value: 0)
        let service = makeService { auxiliary in
            if auxiliary {
                started.fulfill()
                gate.wait()
                return PowerSamplingReading(system: stale, input: stale)
            }
            return PowerSamplingReading(system: fresh)
        }
        var samples: [SystemPowerSample] = []
        let subscription = service.$systemPower.compactMap { $0 }.sink { sample in
            samples.append(sample)
            if sample == fresh { delivered.fulfill() }
        }
        defer {
            gate.signal()
            service.stopAll()
            subscription.cancel()
        }

        service.begin(.powerInfoBar)
        await fulfillment(of: [started], timeout: 1)
        service.setSuspended(true)
        service.end(.powerInfoBar)
        service.begin(.icon)
        service.setSuspended(false)
        gate.signal()
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(samples, [fresh], "an in-flight pre-sleep result must never reach a resumed surface")
        XCTAssertNil(service.inputPower)
        XCTAssertEqual(service.demands, [.icon])
        XCTAssertTrue(service.isRunning)
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
