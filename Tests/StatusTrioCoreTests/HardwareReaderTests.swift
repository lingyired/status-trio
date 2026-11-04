import XCTest
@testable import StatusTrioCore

final class HardwareReaderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testCPUUsesPerCoreDeltasAndTickWeightedTotal() throws {
        var reader = CPUReader()
        XCTAssertNil(reader.sample([ticks(100, 100), ticks(500, 500)], at: start))
        let reading = try XCTUnwrap(reader.sample([ticks(190, 110), ticks(510, 590)], at: start.addingTimeInterval(2)))
        XCTAssertEqual(reading.usage, 50, accuracy: 0.0001)
        XCTAssertEqual(reading.perCoreUsage, [90, 10])
        // Unequal tick windows: 90/100 + 10/900 => 100/1000, not mean(90%,1.11%).
        let weighted = try XCTUnwrap(reader.sample([ticks(280, 120), ticks(520, 1_480)], at: start.addingTimeInterval(4)))
        XCTAssertEqual(weighted.usage, 10, accuracy: 0.0001)
    }

    func testCPUWrapIsAppliedPerCounterBeforeAggregation() throws {
        var reader = CPUReader()
        XCTAssertNil(reader.sample([ticks(UInt32.max - 9, 200)], at: start))
        let reading = try XCTUnwrap(reader.sample([ticks(10, 220)], at: start.addingTimeInterval(2)))
        XCTAssertEqual(reading.usage, 50, accuracy: 0.0001) // user wraps by 20; idle adds 20
    }

    func testCPURebaselinesOnResetSleepCoreChangesAndZeroDelta() {
        var reader = CPUReader()
        XCTAssertNil(reader.sample([ticks(1_000, 1_000)], at: start))
        XCTAssertNil(reader.sample([ticks(1, 1)], at: start.addingTimeInterval(2)), "counter reset is not a wrap")
        XCTAssertEqual(reader.sample([ticks(11, 11)], at: start.addingTimeInterval(4))?.usage, 50)
        XCTAssertNil(reader.sample([ticks(21, 21)], at: start.addingTimeInterval(100)))
        XCTAssertNil(reader.sample([ticks(22, 22), ticks(22, 22)], at: start.addingTimeInterval(102)))
        XCTAssertNil(reader.sample([ticks(22, 22), ticks(22, 22)], at: start.addingTimeInterval(104)))
        reader.reset()
        XCTAssertNil(reader.sample([ticks(40, 40), ticks(40, 40)], at: start.addingTimeInterval(106)))
    }

    func testGPUValidatesPreferredFieldThenSelectsBusiestOnlineDevice() throws {
        let candidates = [
            GPUDeviceReading(deviceName: "sleeping", statistics: ["Device Utilization %": 99], isOnline: false),
            GPUDeviceReading(deviceName: "integrated", statistics: ["Device Utilization %": 0, "GPU Activity(%)": 80]),
            GPUDeviceReading(deviceName: "discrete", statistics: ["Device Utilization %": 42, "GPU Activity(%)": 10]),
            GPUDeviceReading(deviceName: "invalid", statistics: ["Device Utilization %": .infinity])
        ]
        let reading = try XCTUnwrap(GPUReader.select(candidates, at: start))
        XCTAssertEqual(reading.usage, 42)
        XCTAssertEqual(reading.deviceName, "discrete")
        XCTAssertNil(GPUReader.select([GPUDeviceReading(deviceName: nil, statistics: [:])], at: start))
        XCTAssertEqual(GPUReader.select([GPUDeviceReading(deviceName: nil, statistics: ["Device Utilization %": .nan, "GPU Activity(%)": 8])], at: start)?.usage, 8)
        XCTAssertNil(GPUReader.select([GPUDeviceReading(deviceName: nil, statistics: ["Device Utilization %": 101, "GPU Activity(%)": -1])], at: start))
    }

    func testSMCGoldenPayloadsAndReadOnlyWireProtocol() throws {
        var commands: [UInt8] = []
        let value = SMCReadOnlyClient.readValue(key: 0x46304163, exchange: { request in // F0Ac
            XCTAssertEqual(Array(request.prefix(4)), [0x63, 0x41, 0x30, 0x46])
            commands.append(request[42])
            if request[42] == 9 { return self.info(type: [0x20, 0x74, 0x6c, 0x66], size: 4) }
            XCTAssertEqual(request[42], 5)
            XCTAssertEqual(Array(request[28..<32]), [4, 0, 0, 0])
            return self.value([0x2d, 0xdc, 0x3b, 0x45])
        })
        XCTAssertEqual(try XCTUnwrap(value), 3005.760986, accuracy: 0.00001)
        XCTAssertEqual(commands, [9, 5])
        XCTAssertEqual(decode([0x00, 0x28, 0xa7, 0x45], type: [0x20, 0x74, 0x6c, 0x66]), 5349)
        XCTAssertEqual(try XCTUnwrap(decode([0xa4, 0x76, 0x7e, 0x42], type: [0x20, 0x74, 0x6c, 0x66])), 63.61586, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(decode([0x8f, 0x9a, 0x6b, 0x42], type: [0x20, 0x74, 0x6c, 0x66])), 58.900936, accuracy: 0.00001)
        XCTAssertEqual(decode([0x2e, 0xe0], type: [0x32, 0x65, 0x70, 0x66]), 3000)
        XCTAssertEqual(decode([0x3f, 0x80], type: [0x38, 0x37, 0x70, 0x73]), 63.5)
        XCTAssertEqual(decode([2], type: [0x20, 0x38, 0x69, 0x75]), 2)
        XCTAssertEqual(decode([0x14, 0xe5], type: [0x36, 0x31, 0x69, 0x75]), 5349, "generic ui16 is big endian, not battery milli-units")
    }

    func testSMCRejectsMissingMalformedAndNonfiniteValues() {
        XCTAssertNil(SMCReadOnlyClient.readValue(key: 0x54653035, exchange: { _ in nil }))
        for response in [[], Array(repeating: UInt8(0), count: 79), info(type: [0, 0, 0, 0], size: 4), info(type: [0x20, 0x74, 0x6c, 0x66], size: 33)] {
            XCTAssertNil(SMCReadOnlyClient.readValue(key: 0x54653035, exchange: { _ in response }))
        }
        XCTAssertNil(decode([0, 0, 0x80, 0x7f], type: [0x20, 0x74, 0x6c, 0x66]))
        XCTAssertNil(decode([0, 0, 0xc0, 0x7f], type: [0x20, 0x74, 0x6c, 0x66]))
    }

    func testSharedDecoderKeepsBatteryLittleEndianMilliUnitsApartFromGenericIntegers() {
        let battery = SMCReadOnlyClient.Value(type: 0x75693136, size: 2, payload: [0x03, 0xe8])
        XCTAssertEqual(SMCReadOnlyClient.decode(battery, integerEncoding: .batteryLittleEndianMilliUnits), 59.395)
        XCTAssertEqual(SMCReadOnlyClient.decode(battery), 1_000, "generic ui16 stays big endian")
    }

    func testFanCountMustBeAWholePlausibleNumber() {
        let fractional = SensorSMCReader.read(platform: .intel, includeTemperature: false, includeFans: true, at: start) {
            $0 == "FNum" ? 2.5 : nil
        }
        XCTAssertNil(fractional.fanCount)
        XCTAssertTrue(fractional.fans.isEmpty)
    }

    func testTemperatureMappingKeepsGPUOutOfCPUAverageAndPreservesFanMaxima() throws {
        var keys: [String] = []
        let reading = SensorSMCReader.read(platform: .appleSilicon("Apple M3 Max"), includeTemperature: true, includeGPUTemperature: true, includeFans: true, at: start) { key in
            keys.append(key)
            return ["Te05": 60, "Tf04": 80, "Tf14": 100, "FNum": 2,
                    "F0Ac": 3_000, "F0Mn": 1_000, "F0Mx": 5_349,
                    "F1Ac": 3_500, "F1Mn": 1_000, "F1Mx": 6_000][key]
        }
        XCTAssertEqual(reading.cpuTemperature, 70)
        XCTAssertEqual(reading.cpuTemperatureSource, .average(2))
        XCTAssertEqual(reading.gpuTemperature, 100)
        XCTAssertEqual(reading.fanCount, 2)
        XCTAssertEqual(reading.fans.map(\.rpm), [3_000, 3_500])
        XCTAssertEqual(reading.fans.map(\.maxRPM), [5_349, 6_000])
        XCTAssertFalse(keys.contains("F0Md"))
        XCTAssertFalse(keys.contains("PSTR"))
    }

    func testCPUTemperatureDemandDoesNotReadGPUKeysByDefault() {
        var keys: [String] = []
        let reading = SensorSMCReader.read(platform: .appleSilicon("Apple M3 Max"), includeTemperature: true, includeFans: false, at: start) { key in
            keys.append(key)
            return key == "Te05" ? 60 : nil
        }
        XCTAssertEqual(reading.cpuTemperature, 60)
        XCTAssertNil(reading.gpuTemperature)
        XCTAssertEqual(keys.count, 16, "Only the 16 mapped CPU sensors are probed")
        XCTAssertFalse(keys.contains("Tf14"))
        XCTAssertFalse(keys.contains("Tf18"))
    }

    func testGPUTemperatureCanBeReadWithoutAnyCPUOrFanKeys() {
        var keys: [String] = []
        let reading = SensorSMCReader.read(platform: .appleSilicon("Apple M3 Max"), includeTemperature: false, includeGPUTemperature: true, includeFans: false, at: start) { key in
            keys.append(key)
            return key == "Tf14" ? 55 : nil
        }
        XCTAssertNil(reading.cpuTemperature)
        XCTAssertEqual(reading.gpuTemperature, 55)
        XCTAssertEqual(keys.count, 8)
        XCTAssertFalse(keys.contains("Te05"))
        XCTAssertFalse(keys.contains("Tf04"))
        XCTAssertFalse(keys.contains("FNum"))
    }

    func testUnknownChipDoesNotGuessTemperatureKeysAndFanlessIsExplicit() {
        var keys: [String] = []
        let reading = SensorSMCReader.read(platform: .appleSilicon("Apple M99"), includeTemperature: true, includeFans: true, at: start) { key in
            keys.append(key)
            return key == "FNum" ? 0 : 50
        }
        XCTAssertNil(reading.cpuTemperature)
        XCTAssertEqual(reading.fanCount, 0)
        XCTAssertTrue(reading.fans.isEmpty)
        XCTAssertEqual(keys, ["FNum"])
    }

    func testSensorDemandAndInvalidSamplesNeverCreateFakeZeros() {
        var keys: [String] = []
        let noDemand = SensorSMCReader.read(platform: .intel, includeTemperature: false, includeFans: false, at: start) { key in keys.append(key); return 0 }
        XCTAssertTrue(keys.isEmpty)
        XCTAssertNil(noDemand.cpuTemperature)
        let bad = SensorSMCReader.read(platform: .intel, includeTemperature: true, includeFans: true, at: start) { key in
            ["TC0D": -10, "TC0P": 200, "FNum": 1, "F0Ac": 0, "F0Mx": 0][key]
        }
        XCTAssertNil(bad.cpuTemperature)
        XCTAssertEqual(bad.fans.first?.rpm, 0, "a stopped fan is a valid zero")
        XCTAssertNil(bad.fans.first?.maxRPM)
    }

    func testLiveSensorPipelineMatchesThisMacWhenSMCIsAvailable() throws {
        let reading = SensorSMCReader().read(includeTemperature: true, includeFans: true)
        guard reading.cpuTemperature != nil || reading.fanCount != nil else {
            throw XCTSkip("SMC temperature/fan keys unavailable on this host")
        }
        if let temperature = reading.cpuTemperature {
            XCTAssertTrue((0...150).contains(temperature))
        }
        XCTAssertEqual(reading.cpuTemperatureCount > 0, reading.cpuTemperature != nil)
        if let fanCount = reading.fanCount {
            XCTAssertEqual(reading.fans.count, fanCount)
        }
        for fan in reading.fans {
            if let rpm = fan.rpm { XCTAssertTrue((0...30_000).contains(rpm)) }
            if let max = fan.maxRPM { XCTAssertTrue((0...30_000).contains(max)) }
        }
    }

    private func ticks(_ user: UInt32, _ idle: UInt32) -> CPUTicks {
        CPUTicks(user: user, system: 0, idle: idle, nice: 0)
    }
    private func info(type: [UInt8], size: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 80)
        bytes[28] = size
        bytes.replaceSubrange(32..<36, with: type)
        return bytes
    }
    private func value(_ payload: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 80)
        bytes.replaceSubrange(48..<(48 + payload.count), with: payload)
        return bytes
    }
    private func decode(_ payload: [UInt8], type: [UInt8]) -> Double? {
        SMCReadOnlyClient.readValue(key: 0x54653035, exchange: { request in
            request[42] == 9 ? self.info(type: type, size: UInt8(payload.count)) : self.value(payload)
        })
    }
}
