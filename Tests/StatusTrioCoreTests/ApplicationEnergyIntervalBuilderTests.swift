import XCTest
@testable import StatusTrioCore

final class ApplicationEnergyIntervalBuilderTests: XCTestCase {
    private let browser = EnergyApplication(id: "/Browser.app", name: "Browser")
    private let editor = EnergyApplication(id: "/Editor.app", name: "Editor")

    private func process(_ pid: Int32,
                         _ app: EnergyApplication,
                         cpu: UInt64,
                         energy: UInt64?,
                         start: UInt64 = 1,
                         isApplication: Bool = true) -> ProcessEnergySample {
        ProcessEnergySample(pid: pid, startedAt: start, app: app,
                            cpuNanoseconds: cpu, energyNanojoules: energy,
                            isApplication: isApplication)
    }

    private func client(_ entryID: UInt64,
                        pid: Int32?,
                        gpuTime: UInt64,
                        app: EnergyApplication?,
                        start: UInt64? = 1,
                        queueCount: Int = 1) -> GPUClientSample {
        GPUClientSample(entryID: entryID, pid: pid, startedAt: start,
                        name: app?.name ?? "GPU Client", executablePath: nil,
                        responsiblePID: nil, queueCount: queueCount,
                        accumulatedGPUTime: gpuTime, app: app,
                        isApplication: app != nil)
    }

    private func energy(_ raw: UInt64) -> GPUEnergyReading {
        GPUEnergyReading(rawValue: raw, unit: .nanojoule,
                         joules: Double(raw) / 1_000_000_000, readAt: 0)
    }

    func testFirstSnapshotOnlyEstablishesBaseline() {
        var builder = ApplicationEnergyIntervalBuilder()
        let first = ApplicationEnergySnapshot(readAt: 100, processes: [
            process(1, browser, cpu: 0, energy: 1_000_000_000)
        ])
        XCTAssertTrue(builder.build(current: first).isEmpty)
    }

    func testCPUEnergyDeltaConvertsNanojoulesAndAggregatesHelpers() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(readAt: 100, processes: [
            process(1, browser, cpu: 0, energy: 1_000_000_000),
            process(2, browser, cpu: 0, energy: 2_000_000_000)
        ]))
        let intervals = builder.build(current: ApplicationEnergySnapshot(readAt: 105, processes: [
            process(1, browser, cpu: 100_000_000, energy: 3_000_000_000),
            process(2, browser, cpu: 200_000_000, energy: 5_000_000_000)
        ]))
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertEqual(interval.duration, 5, accuracy: 0.001)
        XCTAssertTrue(interval.coverage.contains(.cpuEnergy))
        let row = try XCTUnwrap(interval.apps.first)
        XCTAssertEqual(try XCTUnwrap(row.cpuEnergyJoules), 5, accuracy: 0.000_001)
    }

    func testPIDReuseAndCounterRollbackDoNotProduceSpikes() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(readAt: 100, processes: [
            process(1, browser, cpu: 100, energy: 10_000_000_000, start: 1)
        ]))
        // Same PID, different start time: new process incarnation.
        let reused = builder.build(current: ApplicationEnergySnapshot(readAt: 105, processes: [
            process(1, browser, cpu: 500, energy: 99_000_000_000, start: 2)
        ]))
        XCTAssertTrue(reused.isEmpty)

        var rollbackBuilder = ApplicationEnergyIntervalBuilder()
        _ = rollbackBuilder.build(current: ApplicationEnergySnapshot(readAt: 200, processes: [
            process(1, browser, cpu: 10_000, energy: 10_000_000_000)
        ]))
        let rollback = rollbackBuilder.build(current: ApplicationEnergySnapshot(readAt: 205, processes: [
            process(1, browser, cpu: 1_000, energy: 1_000_000_000)
        ]))
        XCTAssertTrue(rollback.isEmpty || rollback.first?.apps.isEmpty == true)
    }

    func testEnergyReadFailureFallsBackToCPUActivityWithoutZeroEnergy() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(readAt: 100, processes: [
            process(1, browser, cpu: 0, energy: nil)
        ]))
        let intervals = builder.build(current: ApplicationEnergySnapshot(readAt: 105, processes: [
            process(1, browser, cpu: 2_500_000_000, energy: nil)
        ]))
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertFalse(interval.coverage.contains(.cpuEnergy))
        XCTAssertTrue(interval.coverage.contains(.cpuActivity))
        let row = try XCTUnwrap(interval.apps.first)
        XCTAssertNil(row.cpuEnergyJoules)
        XCTAssertEqual(try XCTUnwrap(row.cpuActivityFraction), 0.5, accuracy: 0.000_001)
    }

    func testPartiallyMissingEnergyMarksPartialCoverage() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(readAt: 100, processes: [
            process(1, browser, cpu: 0, energy: 1_000_000_000),
            process(2, editor, cpu: 0, energy: nil)
        ]))
        let intervals = builder.build(current: ApplicationEnergySnapshot(readAt: 105, processes: [
            process(1, browser, cpu: 1_000, energy: 2_000_000_000),
            process(2, editor, cpu: 1_000, energy: nil)
        ]))
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertTrue(interval.partialSources.contains(.cpuEnergy))
    }

    func testGPUEnergyIsProportionallyAttributedToClients() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        let first = ApplicationEnergySnapshot(
            readAt: 100,
            processes: [],
            gpuClients: [
                client(1, pid: 10, gpuTime: 1_000, app: browser),
                client(2, pid: 20, gpuTime: 1_000, app: editor)
            ],
            gpuEnergy: energy(1_000_000_000),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        )
        _ = builder.build(current: first)
        let second = ApplicationEnergySnapshot(
            readAt: 105,
            processes: [],
            gpuClients: [
                client(1, pid: 10, gpuTime: 2_000, app: browser),
                client(2, pid: 20, gpuTime: 2_000, app: editor)
            ],
            gpuEnergy: GPUEnergyReading(rawValue: 2_000_000_000, unit: .nanojoule,
                                        joules: 2, readAt: 105),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        )
        let intervals = builder.build(current: second)
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertTrue(interval.coverage.contains(.gpuEnergy))
        let browserRow = try XCTUnwrap(interval.apps.first { $0.app == browser })
        let editorRow = try XCTUnwrap(interval.apps.first { $0.app == editor })
        XCTAssertEqual(try XCTUnwrap(browserRow.gpuEnergyJoules), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(editorRow.gpuEnergyJoules), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(interval.unassignedGPUJoules, 0, accuracy: 0.000_001)
    }

    func testUnknownGPUClientEnergyStaysUnassigned() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(
            readAt: 100,
            processes: [],
            gpuClients: [
                client(1, pid: 10, gpuTime: 1_000, app: browser),
                client(2, pid: nil, gpuTime: 1_000, app: nil, start: nil)
            ],
            gpuEnergy: energy(1_000_000_000),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        ))
        let intervals = builder.build(current: ApplicationEnergySnapshot(
            readAt: 105,
            processes: [],
            gpuClients: [
                client(1, pid: 10, gpuTime: 2_000, app: browser),
                client(2, pid: nil, gpuTime: 2_000, app: nil, start: nil)
            ],
            gpuEnergy: GPUEnergyReading(rawValue: 2_000_000_000, unit: .nanojoule,
                                        joules: 2, readAt: 105),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        ))
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertEqual(interval.unassignedGPUJoules, 0.5, accuracy: 0.000_001)
        let row = try XCTUnwrap(interval.apps.first)
        XCTAssertEqual(try XCTUnwrap(row.gpuEnergyJoules), 0.5, accuracy: 0.000_001)
    }

    func testFrozenGPUEnergyIsNotReportedAsZero() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        var snapshot = ApplicationEnergySnapshot(
            readAt: 100,
            processes: [],
            gpuClients: [client(1, pid: 10, gpuTime: 1_000, app: browser)],
            gpuEnergy: energy(1_000_000_000),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        )
        _ = builder.build(current: snapshot)
        for index in 1...2 {
            snapshot = ApplicationEnergySnapshot(
                readAt: 100 + Double(index) * 5,
                processes: [],
                gpuClients: [client(1, pid: 10, gpuTime: UInt64(1_000 + index * 1_000), app: browser)],
                gpuEnergy: GPUEnergyReading(rawValue: 1_000_000_000, unit: .nanojoule,
                                            joules: 1, readAt: 100 + Double(index) * 5),
                capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
            )
            let intervals = builder.build(current: snapshot)
            let interval = try XCTUnwrap(intervals.first)
            if index >= 2 {
                XCTAssertFalse(interval.coverage.contains(.gpuEnergy))
                XCTAssertTrue(interval.partialSources.contains(.gpuEnergy))
            }
        }
    }

    func testIdleGPUWithUnchangedEnergyIsNotFrozen() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        let clientSample = client(1, pid: 10, gpuTime: 1_000, app: browser)
        _ = builder.build(current: ApplicationEnergySnapshot(
            readAt: 100, processes: [], gpuClients: [clientSample],
            gpuEnergy: energy(1_000_000_000),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        ))
        let intervals = builder.build(current: ApplicationEnergySnapshot(
            readAt: 105, processes: [], gpuClients: [clientSample],
            gpuEnergy: GPUEnergyReading(rawValue: 1_000_000_000, unit: .nanojoule,
                                        joules: 1, readAt: 105),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        ))
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertTrue(interval.coverage.contains(.gpuEnergy))
        XCTAssertFalse(interval.partialSources.contains(.gpuEnergy))
    }

    func testGPUTimingMismatchSkipsAttribution() throws {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(
            readAt: 100, processes: [], gpuClients: [client(1, pid: 10, gpuTime: 1_000, app: browser)],
            gpuEnergy: GPUEnergyReading(rawValue: 1_000_000_000, unit: .nanojoule, joules: 1, readAt: 100),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        ))
        let intervals = builder.build(current: ApplicationEnergySnapshot(
            readAt: 105, processes: [],
            gpuClients: [client(1, pid: 10, gpuTime: 2_000, app: browser)],
            gpuEnergy: GPUEnergyReading(rawValue: 2_000_000_000, unit: .nanojoule, joules: 2, readAt: 110),
            capabilities: [.gpuClients, .gpuEnergy, .gpuEnergyRuntime]
        ))
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertFalse(interval.coverage.contains(.gpuEnergy))
        XCTAssertTrue(interval.partialSources.contains(.gpuEnergy))
    }

    func testLongGapDropsDelta() {
        var builder = ApplicationEnergyIntervalBuilder()
        _ = builder.build(current: ApplicationEnergySnapshot(readAt: 100, processes: [
            process(1, browser, cpu: 0, energy: 1_000_000_000)
        ]))
        let intervals = builder.build(current: ApplicationEnergySnapshot(readAt: 120, processes: [
            process(1, browser, cpu: 1_000_000_000, energy: 20_000_000_000)
        ]))
        XCTAssertTrue(intervals.isEmpty)
    }
}
