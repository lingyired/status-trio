import XCTest
@testable import StatusTrioCore

final class ApplicationEnergyWindowTests: XCTestCase {
    private let browser = EnergyApplication(id: "/Browser.app", name: "Browser")
    private let editor = EnergyApplication(id: "/Editor.app", name: "Editor")

    private func interval(_ start: TimeInterval,
                          _ duration: TimeInterval,
                          app: EnergyApplication,
                          cpuJoules: Double? = nil,
                          gpuJoules: Double? = nil,
                          activity: Double? = nil,
                          coverage: ApplicationEnergyCoverage = [.cpuEnergy]) -> ApplicationEnergyInterval {
        var rowCoverage: ApplicationEnergyCoverage = []
        if cpuJoules != nil { rowCoverage.insert(.cpuEnergy) }
        if gpuJoules != nil { rowCoverage.insert(.gpuEnergy) }
        if activity != nil { rowCoverage.insert(.cpuActivity) }
        return ApplicationEnergyInterval(
            start: start,
            duration: duration,
            coverage: coverage,
            apps: [ApplicationEnergyAppInterval(
                app: app,
                isApplication: true,
                cpuEnergyJoules: cpuJoules,
                gpuEnergyJoules: gpuJoules,
                cpuActivityFraction: activity,
                coverage: rowCoverage
            )]
        )
    }

    func testTwelveFiveSecondSamplesFormSixtySecondAverage() throws {
        var window = ApplicationEnergyWindow(configuration: .init())
        for index in 0..<12 {
            window.append(contentsOf: [interval(Double(index) * 5, 5, app: browser, cpuJoules: 10)])
        }
        let ranking = window.ranking()
        XCTAssertEqual(ranking.effectiveDuration, 60, accuracy: 0.001)
        XCTAssertTrue(ranking.isWindowComplete)
        XCTAssertEqual(ranking.phase, .ready)
        XCTAssertEqual(try XCTUnwrap(ranking.values[browser]), 2, accuracy: 0.000_001)
    }

    func testOldestIntervalIsSlicedAtWindowBoundary() throws {
        var window = ApplicationEnergyWindow(configuration: .init(capacity: 15))
        window.append(contentsOf: [interval(0, 10, app: browser, cpuJoules: 10)])
        window.append(contentsOf: [interval(10, 10, app: browser, cpuJoules: 10)])
        let ranking = window.ranking()
        XCTAssertEqual(ranking.effectiveDuration, 15, accuracy: 0.001)
        // First interval is only half inside the window: 5 + 10 = 15 J / 15 s.
        XCTAssertEqual(try XCTUnwrap(ranking.values[browser]), 1, accuracy: 0.000_001)
        XCTAssertEqual(window.intervals.reduce(0) { $0 + ($1.apps.first?.cpuEnergyJoules ?? 0) },
                       15, accuracy: 0.000_001)
    }

    func testIrregularIntervalsUseActualDuration() throws {
        var window = ApplicationEnergyWindow(configuration: .init())
        window.append(contentsOf: [interval(0, 2, app: browser, cpuJoules: 2)])
        window.append(contentsOf: [interval(2, 8, app: browser, cpuJoules: 8)])
        let ranking = window.ranking()
        XCTAssertEqual(ranking.effectiveDuration, 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ranking.values[browser]), 1, accuracy: 0.000_001)
    }

    func testFifteenSecondThresholdAndWindowBuildingState() throws {
        var window = ApplicationEnergyWindow(configuration: .init())
        window.append(contentsOf: [interval(0, 10, app: browser, cpuJoules: 1)])
        XCTAssertEqual(window.ranking().phase, .sampling)
        XCTAssertEqual(window.ranking().effectiveDuration, 10, accuracy: 0.001)
        window.append(contentsOf: [interval(10, 5, app: browser, cpuJoules: 1)])
        let ready = window.ranking()
        XCTAssertEqual(ready.phase, .ready)
        XCTAssertFalse(ready.isWindowComplete)
        XCTAssertEqual(ready.effectiveDuration, 15, accuracy: 0.001)
        window.append(contentsOf: [interval(15, 45, app: browser, cpuJoules: 9)])
        XCTAssertTrue(window.ranking().isWindowComplete)
    }

    func testExitedAppKeepsMeasuredIntervalUntilItAgesOut() throws {
        var window = ApplicationEnergyWindow(configuration: .init())
        window.append(contentsOf: [interval(0, 5, app: browser, cpuJoules: 5)])
        for index in 1..<12 {
            window.append(contentsOf: [interval(Double(index) * 5, 5, app: editor, cpuJoules: 5)])
        }
        let ranking = window.ranking()
        XCTAssertNotNil(ranking.values[browser], "Exited app stays in the rolling window")
        window.append(contentsOf: [interval(60, 5, app: editor, cpuJoules: 5)])
        XCTAssertNil(window.ranking().values[browser])
    }

    func testGapLargerThanToleranceResetsWindow() {
        var window = ApplicationEnergyWindow(configuration: .init())
        window.append(contentsOf: [interval(0, 5, app: browser, cpuJoules: 5)])
        window.append(contentsOf: [interval(25, 5, app: browser, cpuJoules: 5)])
        XCTAssertEqual(window.ranking().effectiveDuration, 5, accuracy: 0.001)
    }

    func testTopFiveAndStableTieBreak() {
        let apps = (0..<7).map { EnergyApplication(id: "/App\($0).app", name: "App\($0)") }
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        window.append(contentsOf: apps.map { interval(0, 5, app: $0, cpuJoules: 5) })
        let ranking = window.ranking()
        XCTAssertEqual(ranking.apps.count, 5)
        XCTAssertEqual(ranking.apps.map(\.id), ["/App0.app", "/App1.app", "/App2.app", "/App3.app", "/App4.app"])
    }

    func testNoiseThresholdProducesEmptyState() {
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        window.append(contentsOf: [interval(0, 15, app: browser, cpuJoules: 0.000_001)])
        XCTAssertEqual(window.ranking().phase, .empty)
    }

    func testNoSourcesProducesUnavailableState() {
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        window.append(contentsOf: [ApplicationEnergyInterval(start: 0, duration: 5,
                                                            coverage: [], apps: [])])
        XCTAssertEqual(window.ranking().phase, .unavailable)
    }

    func testCPUActivityUsesFullWindowDurationAsDenominator() throws {
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        window.append(contentsOf: [interval(0, 60, app: browser, activity: 1, coverage: [.cpuActivity])])
        let ranking = window.ranking()
        XCTAssertEqual(ranking.basis, .cpuActivity)
        XCTAssertEqual(try XCTUnwrap(ranking.values[browser]), 1, accuracy: 0.000_001)
    }

    func testMixedCoverageIsPartial() {
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        window.append(contentsOf: [interval(0, 5, app: browser, cpuJoules: 5, coverage: [.cpuEnergy])])
        window.append(contentsOf: [interval(5, 5, app: browser, cpuJoules: 5, coverage: [.cpuEnergy, .gpuEnergy])])
        XCTAssertEqual(window.ranking().phase, .partial)
    }

    func testCPUAndGPUBasisAddsBothSources() throws {
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        window.append(contentsOf: [interval(0, 5, app: browser, cpuJoules: 5, gpuJoules: 5,
                                          coverage: [.cpuEnergy, .gpuEnergy])])
        let ranking = window.ranking()
        XCTAssertEqual(ranking.basis, .cpuAndGPU)
        XCTAssertEqual(try XCTUnwrap(ranking.values[browser]), 2, accuracy: 0.000_001)
    }

    func testGPUOnlyRowKeepsGPUValueAndCoverage() throws {
        var window = ApplicationEnergyWindow(configuration: .init(minimumDuration: 1))
        let system = EnergyApplication(id: "process:42:1", name: "WindowServer")
        window.append(contentsOf: [ApplicationEnergyInterval(
            start: 0,
            duration: 5,
            coverage: [.gpuEnergy],
            apps: [ApplicationEnergyAppInterval(app: system,
                                                isApplication: false,
                                                cpuEnergyJoules: nil,
                                                gpuEnergyJoules: 5,
                                                cpuActivityFraction: nil,
                                                coverage: [.gpuEnergy])]
        )])
        let ranking = window.ranking()
        XCTAssertEqual(ranking.basis, .gpuEnergy)
        XCTAssertEqual(ranking.apps, [system])
        XCTAssertEqual(try XCTUnwrap(ranking.values[system]), 1, accuracy: 0.000_001)
        XCTAssertEqual(ranking.coverage(for: system), .gpuEnergy)
        XCTAssertFalse(ranking.isApplication(system))
    }
}
