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

    func testRankingUsesIntervalEnergyAndAggregatesApplicationHelpers() throws {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000),
            sample(2, browser, cpu: 0, energy: 10_000_000_000),
            sample(3, editor, cpu: 0, energy: 90_000_000_000)])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 20_000_000, energy: 11_000_000_000),
            sample(2, browser, cpu: 20_000_000, energy: 11_000_000_000),
            sample(3, editor, cpu: 500_000_000, energy: 91_500_000_000)])
        let result = ApplicationEnergyRanking.rank(previous: before, current: after)
        XCTAssertEqual(result.apps.map(\.name), ["Browser", "Editor"])
        XCTAssertEqual(result.basis, .cpuEnergy)
        XCTAssertEqual(try XCTUnwrap(result.values[browser]), 0.4, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.values[editor]), 0.3, accuracy: 0.000_001)
    }

    func testUnavailableEnergyUsesExplicitCPUActivityBasis() throws {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [sample(1, browser, cpu: 0, energy: nil)])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [sample(1, browser, cpu: 500_000_000, energy: nil)])
        let result = ApplicationEnergyRanking.rank(previous: before, current: after)
        XCTAssertEqual(result.apps.map(\.name), ["Browser"])
        XCTAssertEqual(result.basis, .cpuActivity)
        XCTAssertEqual(try XCTUnwrap(result.values[browser]), 0.1, accuracy: 0.000_001)
    }

    func testMilliwattLevelAppsRemainVisible() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 0)])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 0, energy: 25_000_000)]) // 5 mW over 5 s
        XCTAssertEqual(
            ApplicationEnergyRanking.rank(previous: before, current: after).apps.map(\.name),
            ["Browser"]
        )

        let quieter = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 0, energy: 2_500_000)]) // 0.5 mW over 5 s
        XCTAssertTrue(
            ApplicationEnergyRanking.rank(previous: before, current: quieter).apps.isEmpty
        )
    }

    func testPartialEnergyCoverageFallsBackToAComparableActivityRanking() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000),
            sample(2, editor, cpu: 0, energy: nil)])
        let after = ApplicationEnergySnapshot(readAt: 105, processes: [
            sample(1, browser, cpu: 0, energy: 10_000_000_000),
            sample(2, editor, cpu: 1_000_000_000, energy: nil)])
        let result = ApplicationEnergyRanking.rank(previous: before, current: after)
        XCTAssertEqual(result.basis, .cpuActivity)
        XCTAssertEqual(result.apps.map(\.name), ["Editor"])
    }

    func testPIDReuseCounterResetAndLongSamplingGapsDoNotCreateSpikes() {
        let before = ApplicationEnergySnapshot(readAt: 100, processes: [sample(1, browser, cpu: 900, energy: 900)])
        for process in [sample(1, browser, cpu: 1_000_000_000, energy: 1_000_000_000, start: 2),
                        sample(1, browser, cpu: 0, energy: 0)] {
            let result = ApplicationEnergyRanking.rank(previous: before,
                current: ApplicationEnergySnapshot(readAt: 105, processes: [process]))
            XCTAssertTrue(result.apps.isEmpty)
        }
        let stale = ApplicationEnergyRanking.rank(previous: before,
            current: ApplicationEnergySnapshot(readAt: 300, processes: [sample(1, browser, cpu: 1_000_000_000, energy: nil)]))
        XCTAssertTrue(stale.apps.isEmpty)
        XCTAssertEqual(stale.phase, .sampling)
    }

    func testBundleAssociationIncludesHelpersWithoutMatchingSiblingPrefix() {
        XCTAssertEqual(ApplicationEnergyReader.application(for: "/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
            applications: [browser, editor]), browser)
        XCTAssertNil(ApplicationEnergyReader.application(for: "/Browser.application/MacOS/Other", applications: [browser]))
    }
}
