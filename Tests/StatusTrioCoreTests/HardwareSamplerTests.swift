import XCTest
@testable import StatusTrioCore

final class HardwareSamplerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000)

    func testMissingReadingsProduceExplicitStatesForEveryRequestedID() {
        let ids: Set<HardwareMetricID> = [.cpuUsage, .gpuUsage, .cpuTemperature, .gpuTemperature, .fanRPM(index: 0)]
        let first = HardwareSampler.map(ids: ids, cpu: nil, gpu: nil, sensors: nil, isFirstCPURead: true, at: date)
        XCTAssertEqual(Set(first.samples.keys), ids)
        XCTAssertEqual(first[.cpuUsage].availability, .collecting)
        for id in ids.subtracting([.cpuUsage]) {
            XCTAssertEqual(first[id].availability, .temporarilyUnavailable)
            XCTAssertNil(first[id].value)
        }
        XCTAssertNil(first.fanCount)
        XCTAssertFalse(first[.fanRPM(index: 0)].metadata.isFanless)
        let next = HardwareSampler.map(ids: [.cpuUsage], cpu: nil, gpu: nil, sensors: nil, isFirstCPURead: false, at: date)
        XCTAssertEqual(next[.cpuUsage].availability, .temporarilyUnavailable)
    }

    func testUnknownFanCountIsNotFanlessAndZeroCountIs() {
        let counts: [Int?] = [nil, 0]
        for count in counts {
            let snapshot = HardwareSampler.map(ids: [.fanRPM(index: 0)], cpu: nil, gpu: nil,
                                               sensors: sensors(fanCount: count), isFirstCPURead: false, at: date)
            let fan = snapshot[.fanRPM(index: 0)]
            XCTAssertNil(fan.value)
            XCTAssertEqual(fan.availability, count == 0 ? .unsupported : .temporarilyUnavailable)
            XCTAssertEqual(fan.metadata.isFanless, count == 0)
            XCTAssertEqual(snapshot.fanCount, count)
        }
    }

    func testFanDemandReturnsEveryFanWithItsOwnLimitsAndPreservesStoppedFan() {
        let raw = sensors(fanCount: 2, fans: [
            FanReading(index: 0, rpm: 0, minRPM: 1_000, maxRPM: 5_349),
            FanReading(index: 1, rpm: 3_500, minRPM: 1_200, maxRPM: 6_000)
        ])
        let snapshot = HardwareSampler.map(ids: [.fanRPM(index: 0)], cpu: nil, gpu: nil,
                                           sensors: raw, isFirstCPURead: false, at: date)
        XCTAssertEqual(Set(snapshot.samples.keys), [.fanRPM(index: 0), .fanRPM(index: 1)])
        XCTAssertEqual(snapshot[.fanRPM(index: 0)].value, 0)
        XCTAssertEqual(snapshot[.fanRPM(index: 0)].availability, .measured)
        XCTAssertEqual(snapshot[.fanRPM(index: 0)].metadata.maximum, 5_349)
        XCTAssertEqual(snapshot[.fanRPM(index: 1)].metadata.minimum, 1_200)
        XCTAssertEqual(snapshot[.fanRPM(index: 1)].metadata.maximum, 6_000)
        XCTAssertEqual(snapshot[.fanRPM(index: 1)].value, 3_500)
    }

    func testFanReadFailureAndOutOfRangeRequestedIndexGetExplicitStates() {
        let snapshot = HardwareSampler.map(ids: [.fanRPM(index: 0), .fanRPM(index: 3)], cpu: nil, gpu: nil,
                                           sensors: sensors(fanCount: 2, fans: [FanReading(index: 0, rpm: nil, minRPM: nil, maxRPM: nil)]),
                                           isFirstCPURead: false, at: date)
        XCTAssertEqual(snapshot[.fanRPM(index: 0)].availability, .temporarilyUnavailable)
        XCTAssertEqual(snapshot[.fanRPM(index: 1)].availability, .temporarilyUnavailable)
        XCTAssertEqual(snapshot[.fanRPM(index: 3)].availability, .unsupported)
        XCTAssertFalse(snapshot[.fanRPM(index: 3)].metadata.isFanless)
    }

    func testGPUTemperatureMapsIndependentlyWithoutLeakingUnrequestedCPU() {
        let snapshot = HardwareSampler.map(ids: [.gpuTemperature], cpu: nil, gpu: nil,
                                           sensors: sensors(cpu: 70, gpu: 55), isFirstCPURead: false, at: date)
        XCTAssertEqual(Set(snapshot.samples.keys), [.gpuTemperature])
        XCTAssertEqual(snapshot[.gpuTemperature].value, 55)
        XCTAssertEqual(snapshot[.gpuTemperature].unit, .celsius)
        XCTAssertEqual(snapshot[.gpuTemperature].source, .smc)
    }

    func testCPUOnlyDoesNotCallGPUOrSMCAndIgnoresOtherInjectedReadings() {
        var cpuCalls = 0
        let snapshot = HardwareSampler.collect(ids: [.cpuUsage], isFirstCPURead: true, at: date,
                                               cpuProvider: { _ in cpuCalls += 1; return CPUReading(usage: 25, perCoreUsage: [25], sampledAt: self.date) },
                                               gpuProvider: { _ in XCTFail("CPUOnly must not read GPU"); return nil },
                                               memoryProvider: { _ in XCTFail("CPUOnly must not read memory"); return nil },
                                               sensorProvider: { _, _, _, _, _ in XCTFail("CPUOnly must not read SMC"); return self.sensors() })
        XCTAssertEqual(cpuCalls, 1)
        XCTAssertEqual(Set(snapshot.samples.keys), [.cpuUsage])
        XCTAssertEqual(snapshot[.cpuUsage].value, 25)
        XCTAssertEqual(snapshot[.cpuUsage].availability, .measured)
    }

    func testTemperatureOnlyDoesNotReadGPUUsageAndRequestsSMCTemperatureOnly() {
        for id in [HardwareMetricID.cpuTemperature, .gpuTemperature] {
            var sensorCalls = 0
            let snapshot = HardwareSampler.collect(ids: [id], isFirstCPURead: true, at: date,
                                                   cpuProvider: { _ in XCTFail("temperature must not read CPU usage"); return nil },
                                                   gpuProvider: { _ in XCTFail("temperature must not read GPU usage"); return nil },
                                                   memoryProvider: { _ in XCTFail("temperature must not read memory"); return nil },
                                                   sensorProvider: { temperature, gpuTemperature, batteryTemperature, fans, _ in
                sensorCalls += 1
                XCTAssertEqual(temperature, id == .cpuTemperature)
                XCTAssertEqual(gpuTemperature, id == .gpuTemperature)
                XCTAssertEqual(batteryTemperature, id == .batteryTemperature)
                XCTAssertFalse(fans)
                return self.sensors(cpu: 60, gpu: 50, battery: 32)
            })
            XCTAssertEqual(sensorCalls, 1)
            XCTAssertEqual(Set(snapshot.samples.keys), [id])
            XCTAssertEqual(snapshot[id].value, id == .cpuTemperature ? 60 : 50)
        }
    }

    func testZeroGPUUsageIsMeasuredAndTemperatureMetadataIsPreserved() {
        let snapshot = HardwareSampler.map(ids: [.gpuUsage, .cpuTemperature], cpu: nil,
                                           gpu: GPUReading(usage: 0, deviceName: "AGX", sampledAt: date),
                                           sensors: sensors(cpu: 70), isFirstCPURead: false, at: date)
        XCTAssertEqual(snapshot[.gpuUsage].value, 0)
        XCTAssertEqual(snapshot[.gpuUsage].availability, .measured)
        XCTAssertEqual(snapshot[.cpuTemperature].metadata.sourceCount, 2)
        XCTAssertEqual(snapshot[.cpuTemperature].sensorLabel, "CPU average")
    }

    func testMemoryAndBatteryTemperatureMapToTheirOwnMetrics() {
        let memory = MemoryReader.Reading(percent: 38.5, usedBytes: 50_000, totalBytes: 131_072, sampledAt: date)
        let snapshot = HardwareSampler.map(ids: [.memoryUsage, .batteryTemperature], cpu: nil, gpu: nil,
                                           memory: memory, sensors: sensors(battery: 32.3),
                                           isFirstCPURead: false, at: date)
        XCTAssertEqual(Set(snapshot.samples.keys), [.memoryUsage, .batteryTemperature])
        XCTAssertEqual(snapshot[.memoryUsage].value, 38.5)
        XCTAssertEqual(snapshot[.memoryUsage].unit, .percent)
        XCTAssertEqual(snapshot[.memoryUsage].availability, .measured)
        XCTAssertEqual(snapshot[.batteryTemperature].value ?? 0, 32.3, accuracy: 0.001)
        XCTAssertEqual(snapshot[.batteryTemperature].unit, .celsius)
    }

    func testMemoryOnlyDoesNotTouchCPUOrSMC() {
        let snapshot = HardwareSampler.collect(ids: [.memoryUsage], isFirstCPURead: true, at: date,
                                               cpuProvider: { _ in XCTFail("memory must not read CPU"); return nil },
                                               gpuProvider: { _ in XCTFail("memory must not read GPU"); return nil },
                                               memoryProvider: { _ in MemoryReader.Reading(percent: 20, usedBytes: 1, totalBytes: 10, sampledAt: self.date) },
                                               sensorProvider: { _, _, _, _, _ in XCTFail("memory must not read SMC"); return self.sensors() })
        XCTAssertEqual(snapshot[.memoryUsage].value, 20)
    }

    private func sensors(cpu: Double? = nil, gpu: Double? = nil, battery: Double? = nil,
                         fanCount: Int? = nil, fans: [FanReading] = []) -> SensorReading {
        SensorReading(cpuTemperature: cpu, cpuTemperatureSource: cpu == nil ? nil : .average(2),
                      gpuTemperature: gpu, batteryTemperature: battery,
                      fans: fans, fanCount: fanCount, sampledAt: date)
    }
}
