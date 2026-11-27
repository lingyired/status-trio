import XCTest
@testable import StatusTrioCore

final class ApplicationEnergyAttributionTests: XCTestCase {
    func testGPUEnergyUnitConversion() {
        XCTAssertEqual(GPUEnergyUnit.parse("mJ"), .millijoule)
        XCTAssertEqual(GPUEnergyUnit.parse("µJ"), .microjoule)
        XCTAssertEqual(GPUEnergyUnit.parse("uJ"), .microjoule)
        XCTAssertEqual(GPUEnergyUnit.parse("nJ"), .nanojoule)
        XCTAssertNil(GPUEnergyUnit.parse("W"))
        XCTAssertEqual(GPUEnergyUnit.millijoule.joules(for: 1_000), 1, accuracy: 0.000_001)
        XCTAssertEqual(GPUEnergyUnit.microjoule.joules(for: 1_000_000), 1, accuracy: 0.000_001)
        XCTAssertEqual(GPUEnergyUnit.nanojoule.joules(for: 1_000_000_000), 1, accuracy: 0.000_001)
    }

    func testGPUEnergyChannelCombinationRejectsUnknownUnits() throws {
        let valid = [
            GPUEnergyReader.ChannelReading(group: "Energy Model", name: "GPU Energy",
                                           unitLabel: "mJ", value: 1_000)
        ]
        let reading = try XCTUnwrap(GPUEnergyReader.combine(valid, at: 10))
        XCTAssertEqual(reading.joules, 1)
        XCTAssertEqual(reading.unit, .millijoule)

        let unknown = [
            GPUEnergyReader.ChannelReading(group: "Energy Model", name: "GPU Energy",
                                           unitLabel: "W", value: 1_000)
        ]
        XCTAssertNil(GPUEnergyReader.combine(unknown, at: 10))
    }

    func testGPUEnergyChannelIgnoresOtherChannels() {
        let readings = [
            GPUEnergyReader.ChannelReading(group: "Energy Model", name: "CPU Energy",
                                           unitLabel: "mJ", value: 999),
            GPUEnergyReader.ChannelReading(group: "Energy Model", name: "GPU Energy",
                                           unitLabel: "mJ", value: 2_000)
        ]
        XCTAssertEqual(GPUEnergyReader.combine(readings, at: 10)?.joules, 2)
    }

    func testProportionalAttributionAndUnattributedBucket() throws {
        let result = GPUEnergyAttribution.attribute(totalDeltaJoules: 9, clientDeltas: [
            GPUClientIntervalDelta(entryID: 1, pid: 10, gpuTimeDelta: 2_000),
            GPUClientIntervalDelta(entryID: 2, pid: 10, gpuTimeDelta: 1_000),
            GPUClientIntervalDelta(entryID: 3, pid: nil, gpuTimeDelta: 3_000)
        ])
        XCTAssertEqual(try XCTUnwrap(result.allocationByPID[10]), 4.5, accuracy: 0.000_001)
        XCTAssertEqual(result.unassignedJoules, 4.5, accuracy: 0.000_001)
        XCTAssertEqual(result.attributionCoverage, 0.5, accuracy: 0.000_001)
    }

    func testZeroClientTimeLeavesAllEnergyUnattributed() {
        let result = GPUEnergyAttribution.attribute(totalDeltaJoules: 3, clientDeltas: [])
        XCTAssertEqual(result.unassignedJoules, 3, accuracy: 0.000_001)
        XCTAssertTrue(result.allocationByPID.isEmpty)
        XCTAssertEqual(result.attributionCoverage, 0)
    }

    func testCorrectionLearnsBaselineAndCapsWindowServer() {
        var correction = GPUAttributionCorrection(
            configuration: .init(isEnabled: true, minimumBaselineSamples: 3,
                                 windowServerMultiplierLimit: 1.5)
        )
        for _ in 0..<3 {
            correction.observeIdleWindowServer(powerW: 0.2)
        }
        XCTAssertEqual(correction.baselinePowerW ?? 0, 0.2, accuracy: 0.000_001)
        let result = correction.apply(
            allocationByPID: [99: 8, 10: 2],
            gpuTimeDeltaByPID: [99: 8, 10: 2],
            windowServerPID: 99,
            elapsed: 5
        )
        // Baseline cap = 0.2 W * 1.5 * 5 s = 1.5 J; excess is redistributed.
        XCTAssertEqual(result.allocationByPID[99] ?? 0, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(result.allocationByPID[10] ?? 0, 8.5, accuracy: 0.000_001)
        XCTAssertEqual(result.windowServerRawPowerW ?? 0, 1.6, accuracy: 0.000_001)
        XCTAssertEqual(result.windowServerCorrectedPowerW ?? 0, 0.3, accuracy: 0.000_001)
    }

    func testCorrectionDoesNothingBeforeBaseline() {
        var correction = GPUAttributionCorrection(
            configuration: .init(isEnabled: true, minimumBaselineSamples: 3)
        )
        correction.observeIdleWindowServer(powerW: 0.2)
        let result = correction.apply(
            allocationByPID: [99: 10],
            gpuTimeDeltaByPID: [99: 10],
            windowServerPID: 99,
            elapsed: 5
        )
        XCTAssertEqual(result.allocationByPID[99], 10)
        XCTAssertNil(result.windowServerRawPowerW)
    }

    func testDisabledCorrectionIsTransparent() {
        let correction = GPUAttributionCorrection(configuration: .init(isEnabled: false))
        let result = correction.apply(
            allocationByPID: [99: 10],
            gpuTimeDeltaByPID: [99: 10],
            windowServerPID: 99,
            elapsed: 5
        )
        XCTAssertEqual(result.allocationByPID[99], 10)
    }
}
