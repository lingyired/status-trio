import XCTest
@testable import StatusTrioCore

private final class FakeHIDTransport: HIDTemperatureTransport {
    var serviceList: [HIDServiceDescriptor]
    var values: [Int: Double]
    var openResult = true
    var openCount = 0
    var closeCount = 0
    var discoverCount = 0
    var readIndices: [Int] = []

    init(services: [HIDServiceDescriptor], values: [Int: Double] = [:]) {
        self.serviceList = services
        self.values = values
    }

    func open() -> Bool {
        openCount += 1
        return openResult
    }

    func discoverServices() -> [HIDServiceDescriptor]? {
        discoverCount += 1
        return serviceList
    }

    func readTemperature(of service: HIDServiceDescriptor) -> Double? {
        readIndices.append(service.index)
        return values[service.index]
    }

    func close() {
        closeCount += 1
    }
}

final class SensorHIDReaderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func descriptors(_ names: [String]) -> [HIDServiceDescriptor] {
        names.enumerated().map { HIDServiceDescriptor(index: $0.offset, name: $0.element) }
    }

    func testAveragesOnlyCPUSensors() {
        let transport = FakeHIDTransport(
            services: descriptors([
                "pACC MTR Temp Sensor",
                "eACC MTR Temp Sensor",
                "PMU tdie1",
                "GPU MTR Temp Sensor"
            ]),
            values: [0: 60, 1: 70, 2: 99, 3: 50])
        let reader = SensorHIDReader(transport: transport)
        let result = reader.read(targets: [.cpu], at: start)
        XCTAssertEqual(result[.cpu], TemperatureMeasurement(value: 65, count: 2))
        XCTAssertNil(result[.gpu])
        XCTAssertEqual(transport.readIndices, [0, 1], "CPU-only must not read GPU or PMU events")
    }

    func testGPUOnlyReadsGPUSensorsOnly() {
        let transport = FakeHIDTransport(
            services: descriptors([
                "pACC MTR Temp Sensor",
                "GPU MTR Temp Sensor"
            ]),
            values: [0: 60, 1: 52])
        let reader = SensorHIDReader(transport: transport)
        let result = reader.read(targets: [.gpu], at: start)
        XCTAssertEqual(result[.gpu], TemperatureMeasurement(value: 52, count: 1))
        XCTAssertNil(result[.cpu])
        XCTAssertEqual(transport.readIndices, [1])
    }

    func testRejectsInvalidAndOutOfRangeValues() {
        let transport = FakeHIDTransport(
            services: descriptors([
                "pACC MTR Temp Sensor",
                "pACC MTR Temp Sensor",
                "eACC MTR Temp Sensor",
                "eACC MTR Temp Sensor"
            ]),
            values: [0: .nan, 1: 60, 2: 400, 3: 70])
        let reader = SensorHIDReader(transport: transport)
        let result = reader.read(targets: [.cpu], at: start)
        XCTAssertEqual(result[.cpu], TemperatureMeasurement(value: 65, count: 2))
    }

    func testNoMatchingSensorsReturnsEmpty() {
        let transport = FakeHIDTransport(
            services: descriptors(["PMU tdie1", "gas gauge battery", "NAND CH0 temp"]),
            values: [0: 50, 1: 25, 2: 30])
        let reader = SensorHIDReader(transport: transport)
        XCTAssertTrue(reader.read(targets: [.cpu, .gpu], at: start).isEmpty)
        XCTAssertTrue(transport.readIndices.isEmpty)
    }

    func testClientCreatedOnceAndServicesCachedWithinInterval() {
        let transport = FakeHIDTransport(services: descriptors(["pACC MTR Temp Sensor"]), values: [0: 60])
        let reader = SensorHIDReader(transport: transport)
        _ = reader.read(targets: [.cpu], at: start)
        _ = reader.read(targets: [.cpu], at: start.addingTimeInterval(4))
        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(transport.discoverCount, 1)
    }

    func testRediscoveryAfterSixtySeconds() {
        let transport = FakeHIDTransport(services: descriptors(["pACC MTR Temp Sensor"]), values: [0: 60])
        let reader = SensorHIDReader(transport: transport)
        _ = reader.read(targets: [.cpu], at: start)
        _ = reader.read(targets: [.cpu], at: start.addingTimeInterval(61))
        XCTAssertEqual(transport.discoverCount, 2)
    }

    func testMissingEventShortensRediscoveryToFiveSeconds() {
        let transport = FakeHIDTransport(services: descriptors(["pACC MTR Temp Sensor"]))
        let reader = SensorHIDReader(transport: transport)
        _ = reader.read(targets: [.cpu], at: start)
        XCTAssertEqual(transport.discoverCount, 1)
        _ = reader.read(targets: [.cpu], at: start.addingTimeInterval(4))
        XCTAssertEqual(transport.discoverCount, 1, "still inside the shortened window")
        _ = reader.read(targets: [.cpu], at: start.addingTimeInterval(6))
        XCTAssertEqual(transport.discoverCount, 2)
    }

    func testReleaseClosesAndAllowsReopen() {
        let transport = FakeHIDTransport(services: descriptors(["pACC MTR Temp Sensor"]), values: [0: 60])
        let reader = SensorHIDReader(transport: transport)
        _ = reader.read(targets: [.cpu], at: start)
        reader.release()
        XCTAssertEqual(transport.closeCount, 1)
        _ = reader.read(targets: [.cpu], at: start.addingTimeInterval(1))
        XCTAssertEqual(transport.openCount, 2)
    }

    func testOpenFailureReturnsEmptyWithoutDiscovery() {
        let transport = FakeHIDTransport(services: descriptors(["pACC MTR Temp Sensor"]), values: [0: 60])
        transport.openResult = false
        let reader = SensorHIDReader(transport: transport)
        XCTAssertTrue(reader.read(targets: [.cpu], at: start).isEmpty)
        XCTAssertEqual(transport.discoverCount, 0)
    }

    func testSensorNameClassification() {
        XCTAssertTrue(SensorHIDReader.isCPUSensor("pACC MTR Temp Sensor"))
        XCTAssertTrue(SensorHIDReader.isCPUSensor("eACC MTR Temp Sensor"))
        XCTAssertFalse(SensorHIDReader.isCPUSensor("GPU MTR Temp Sensor"))
        XCTAssertFalse(SensorHIDReader.isCPUSensor("PMU tdie1"))
        XCTAssertTrue(SensorHIDReader.isGPUSensor("GPU MTR Temp Sensor"))
        XCTAssertFalse(SensorHIDReader.isGPUSensor("pACC MTR Temp Sensor"))
        XCTAssertFalse(SensorHIDReader.isGPUSensor("SOC MTR Temp Sensor"))
    }
}
