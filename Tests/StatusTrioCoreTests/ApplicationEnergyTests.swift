import XCTest
@testable import StatusTrioCore

final class ApplicationEnergyTests: XCTestCase {
    private let browser = EnergyApplication(id: "/Browser.app", name: "Browser")
    private let editor = EnergyApplication(id: "/Editor.app", name: "Editor")

    private func sample(_ pid: Int32, _ app: EnergyApplication, cpu: UInt64,
                        energy: UInt64?, start: UInt64 = 1) -> ProcessEnergySample {
        ProcessEnergySample(pid: pid, startedAt: start, app: app,
                            cpuNanoseconds: cpu, energyNanojoules: energy)
    }

    private func ranking(previous: ApplicationEnergySnapshot,
                         current: ApplicationEnergySnapshot) -> ApplicationEnergyRanking {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: previous)
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 0))
        window.append(contentsOf: builder.build(current: current))
        return window.ranking()
    }

    func testRankingUsesIntervalEnergyAndAggregatesApplicationHelpers() throws {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000),
            sample(2, browser, cpu: 0, energy: 10_000_000_000),
            sample(3, editor, cpu: 0, energy: 90_000_000_000)])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 20_000_000, energy: 11_000_000_000),
            sample(2, browser, cpu: 20_000_000, energy: 11_000_000_000),
            sample(3, editor, cpu: 500_000_000, energy: 91_500_000_000)])
        let result = ranking(previous: before, current: after)
        XCTAssertEqual(result.apps.map(\.name), ["Browser", "Editor"])
        XCTAssertEqual(result.basis, .cpuEnergy)
        XCTAssertEqual(try XCTUnwrap(result.values[browser]), 0.4, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.values[editor]), 0.3, accuracy: 0.000_001)
    }

    func testUnavailableEnergyUsesExplicitCPUActivityBasis() throws {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: nil)
        ])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 500_000_000, energy: nil)
        ])
        let result = ranking(previous: before, current: after)
        XCTAssertEqual(result.basis, .cpuActivity)
        XCTAssertEqual(try XCTUnwrap(result.values[browser]), 0.1, accuracy: 0.000_001)
    }

    func testPartialEnergyCoverageStaysCPUEnergyAndMarksPartial() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000),
            sample(2, browser, cpu: 0, energy: nil)
        ])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 20_000_000, energy: 11_000_000_000),
            sample(2, browser, cpu: 100_000_000, energy: nil)
        ])
        let result = ranking(previous: before, current: after)
        XCTAssertEqual(result.basis, .cpuEnergy)
        XCTAssertEqual(result.phase, .partial)
        XCTAssertNotNil(result.values[browser])
    }

    func testSmallValuesAreFilteredAsNoise() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000)
        ])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 1_000_000, energy: 10_000_100_000)
        ])
        let result = ranking(previous: before, current: after)
        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertEqual(result.phase, .empty)
    }

    func testPIDReuseAndCounterResetDoNotCreateSpikes() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 1_000_000, energy: 10_000_000_000, start: 1)
        ])
        let reused = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 500_000_000, energy: 99_000_000_000, start: 2)
        ])
        let result = ranking(previous: before, current: reused)
        XCTAssertTrue(result.apps.isEmpty)

        let reset = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 100, energy: 1_000, start: 1)
        ])
        XCTAssertTrue(ranking(previous: before, current: reset).apps.isEmpty)
    }

    func testLongGapDoesNotCrossSleepBoundary() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000)
        ])
        let after = ApplicationEnergySnapshot(readAt: 130, processes: [
            sample(1, browser, cpu: 5_000_000_000, energy: 50_000_000_000)
        ])
        let result = ranking(previous: before, current: after)
        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertEqual(result.phase, .sampling)
    }

    func testApplicationPathAssociationPrefersOuterBundleAndAvoidsSiblings() {
        let apps = [
            EnergyApplication(id: "/Applications/Alpha.app", name: "Alpha"),
            EnergyApplication(id: "/Applications/Alpha Helper.app", name: "Alpha Helper")
        ]
        XCTAssertEqual(ApplicationEnergyReader.application(
            for: "/Applications/Alpha.app/Contents/MacOS/Alpha", applications: apps
        )?.name, "Alpha")
        XCTAssertEqual(ApplicationEnergyReader.application(
            for: "/Applications/Alpha Helper.app/Contents/MacOS/Alpha Helper", applications: apps
        )?.name, "Alpha Helper")
        XCTAssertNil(ApplicationEnergyReader.application(
            for: "/Applications/AlphaSibling.app/Contents/MacOS/Alpha", applications: apps
        ))
    }
}
