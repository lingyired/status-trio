import Foundation
import IOKit.ps
import XCTest
@testable import StatusTrioCore

final class BatteryHealthParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_555_974)
    private func state(connected: Bool = false, charging: Bool = false) -> BatteryPowerState {
        BatteryPowerState(BatteryStatus(rawPercentage: 80, isPresent: true,
                                       isCharging: charging, isLowPowerMode: false,
                                       isConnectedToPower: connected))
    }
    private var registry: [String: Any] {
        ["Voltage": 12_763, "Amperage": -1_705, "UpdateTime": now.timeIntervalSince1970,
         "ExternalConnected": false, "IsCharging": false, "CycleCount": 52]
    }

    // MARK: - Capacity pairing

    func testNestedBatteryDataCapacitiesWinAndUseTheSameDictionary() throws {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "AppleRawMaxCapacity": 9_999, "DesignCapacity": 9_999,
            "BatteryData": [
                "AppleRawMaxCapacity": 8_413,
                "FullChargeCapacity": 8_413,
                "NominalChargeCapacity": 8_657,
                "DesignCapacity": 8_579,
                "MaxCapacity": 100
            ]
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertEqual(capacity.maximumMAh, 8_413, "AppleRawMaxCapacity is the measured maximum")
        XCTAssertEqual(try XCTUnwrap(capacity.healthPercent), 8_413.0 / 8_579 * 100, accuracy: 0.000_001)
    }

    func testTopLevelCapacitiesAreTheFallbackWhenBatteryDataIsAbsent() {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "AppleRawMaxCapacity": 8_413, "DesignCapacity": 8_579
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertEqual(capacity.maximumMAh, 8_413)
        XCTAssertNotNil(capacity.healthPercent)
    }

    func testCapacityNeverMixesNestedAndTopLevelDictionaries() {
        // The nested dictionary has a design capacity but no maximum. Falling
        // back to the unrelated top-level maximum would fabricate a ratio.
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["DesignCapacity": 8_579],
            "AppleRawMaxCapacity": 9_000
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertNil(capacity.maximumMAh)
        XCTAssertNil(capacity.healthPercent)
    }

    func testPercentageMaxCapacityIsNeverReadAsMilliampHours() {
        // MaxCapacity is a percentage on AppleSmartBattery; only explicit mAh
        // keys may feed the maximum capacity.
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["MaxCapacity": 100, "DesignCapacity": 8_579]
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertNil(capacity.maximumMAh)
        XCTAssertNil(capacity.healthPercent)
    }

    func testFullChargeCapacityIsUsedWhenMeasuredMaximumIsMissing() throws {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["FullChargeCapacity": 8_000, "DesignCapacity": 8_579]
        ])
        XCTAssertEqual(capacity.maximumMAh, 8_000)
        XCTAssertEqual(try XCTUnwrap(capacity.healthPercent), 8_000.0 / 8_579 * 100, accuracy: 0.000_001)
    }

    func testBooleanAndMalformedCapacityValuesAreRejected() {
        let booleans: [String: Any] = [
            "DesignCapacity": true,
            "BatteryData": ["DesignCapacity": true, "AppleRawMaxCapacity": NSNumber(value: true)]
        ]
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: booleans),
                       BatteryHealthParser.Capacity())

        let malformed: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": "8579",
                "AppleRawMaxCapacity": 8_413.5,
                "FullChargeCapacity": 0,
                "NominalChargeCapacity": -8_413,
                "MaxCapacity": 1_000_000
            ]
        ]
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: malformed),
                       BatteryHealthParser.Capacity())
    }

    func testMissingFieldsAndEmptyRegistryReturnEmptyCapacity() {
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: [:]), BatteryHealthParser.Capacity())
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: ["CycleCount": 52]),
                       BatteryHealthParser.Capacity())
    }

    // MARK: - Health percentage

    func testHealthPercentageMatchesMeasuredCapacityRatio() throws {
        let percent = try XCTUnwrap(BatteryHealthParser.healthPercent(maximumMAh: 8_413, designMAh: 8_579))
        XCTAssertEqual(percent, 98.065_043, accuracy: 0.000_001)
    }

    func testHealthAboveOneHundredPercentIsKeptUnclampedWithinCredibleRange() throws {
        // A replaced battery can read above design capacity. The number is
        // telemetry, not a display target, so it is not silently clamped.
        let percent = try XCTUnwrap(BatteryHealthParser.healthPercent(maximumMAh: 8_700, designMAh: 8_579))
        XCTAssertEqual(percent, 101.410_421, accuracy: 0.000_001)
    }

    func testImplausibleHealthIsUnavailableWhileCapacitiesRemainValid() {
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: 20_000, designMAh: 8_579))
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: 8_413, designMAh: 0))
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: nil, designMAh: 8_579))
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["DesignCapacity": 8_579, "AppleRawMaxCapacity": 20_000]
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertEqual(capacity.maximumMAh, 20_000)
        XCTAssertNil(capacity.healthPercent)
    }

    // MARK: - Temperature

    func testSMCBatteryTemperatureDecodesEveryVerifiedEncoding() throws {
        // flt 36.0 °C, little-endian host float.
        XCTAssertEqual(
            try XCTUnwrap(BatteryHealthParser.temperatureCelsius(
                smcType: 0x666c7420, bytes: [0x00, 0x00, 0x10, 0x42])),
            36.0, accuracy: 0.000_001)
        // sp78 (signed 8.8 fixed point) 30.5 °C.
        XCTAssertEqual(
            try XCTUnwrap(BatteryHealthParser.temperatureCelsius(
                smcType: 0x73703738, bytes: [0x1E, 0x80])),
            30.5, accuracy: 0.000_001)
        // fpe2 (unsigned 14.2 fixed point) 30.5 °C.
        XCTAssertEqual(
            try XCTUnwrap(BatteryHealthParser.temperatureCelsius(
                smcType: 0x66706532, bytes: [0x00, 0x7A])),
            30.5, accuracy: 0.000_001)
        // sp78 can express a cold battery.
        XCTAssertEqual(
            try XCTUnwrap(BatteryHealthParser.temperatureCelsius(
                smcType: 0x73703738, bytes: [0xF9, 0x00])),
            -7.0, accuracy: 0.000_001)
    }

    func testUnverifiedTemperatureEncodingsAndImplausibleValuesAreUnavailable() {
        XCTAssertNil(BatteryHealthParser.temperatureCelsius(smcType: 0x73693136, bytes: [0x00, 0x10]))
        XCTAssertNil(BatteryHealthParser.temperatureCelsius(smcType: 0x666c7420, bytes: [0x00, 0x00]))
        XCTAssertNil(BatteryHealthParser.temperatureCelsius(
            smcType: 0x666c7420, bytes: Float(120).bitPatternBytesLittleEndian))
        XCTAssertNil(BatteryHealthParser.temperatureCelsius(
            smcType: 0x666c7420, bytes: Float(-40).bitPatternBytesLittleEndian))
        XCTAssertNil(BatteryHealthParser.temperatureCelsius(
            smcType: 0x666c7420, bytes: Float.nan.bitPatternBytesLittleEndian))
    }

    // MARK: - Charge time

    func testChargeTimeUsesTheOfficialEstimate() {
        let state = BatteryHealthParser.parseChargeTime(
            description: chargeDescription(charging: true, charged: false, timeToFull: 80),
            isConnectedToPower: true,
            isCharging: true)
        XCTAssertEqual(state, .estimated(minutes: 80))
    }

    func testChargeTimeReportsCalculatingForMinusOneAndZeroWhileCharging() {
        for raw in [-1, 0] {
            let state = BatteryHealthParser.parseChargeTime(
                description: chargeDescription(charging: true, charged: false, timeToFull: raw),
                isConnectedToPower: true,
                isCharging: true)
            XCTAssertEqual(state, .calculating, "raw \(raw) must not become 0 minutes")
        }
    }

    func testChargeTimeReportsChargedAndPausedFromReliableState() {
        XCTAssertEqual(
            BatteryHealthParser.parseChargeTime(
                description: chargeDescription(charging: false, charged: true, timeToFull: 0),
                isConnectedToPower: true, isCharging: false),
            .charged)
        XCTAssertEqual(
            BatteryHealthParser.parseChargeTime(
                description: chargeDescription(charging: false, charged: false, timeToFull: 0),
                isConnectedToPower: true, isCharging: false),
            .paused)
    }

    func testChargeTimeIsUnavailableOnBatteryAndWithoutABattery() {
        XCTAssertEqual(
            BatteryHealthParser.parseChargeTime(
                description: chargeDescription(charging: false, charged: false,
                                               timeToFull: -1, state: "Battery Power"),
                isConnectedToPower: false, isCharging: false),
            .unavailable)
        // A description that omits every state key falls back to the caller's
        // IOPS-backed state instead of inventing an estimate.
        XCTAssertEqual(
            BatteryHealthParser.parseChargeTime(
                description: [kIOPSTypeKey: kIOPSInternalBatteryType],
                isConnectedToPower: true, isCharging: true),
            .calculating)
        XCTAssertEqual(
            BatteryHealthParser.parseChargeTime(
                description: [kIOPSIsPresentKey: false, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
                              kIOPSIsChargingKey: true, kIOPSTimeToFullChargeKey: 30],
                isConnectedToPower: true, isCharging: true),
            .unavailable)
    }

    // MARK: - Reader integration

    func testReaderParseCarriesHealthThroughPowerAvailabilityBranches() {
        var values = registry
        values["BatteryData"] = ["DesignCapacity": 8_579, "AppleRawMaxCapacity": 8_413]
        let details = BatteryDetailsReader.parse(
            registry: values, adapterWatts: nil, remainingSeconds: -1,
            state: state(), now: now,
            temperatureCelsius: 36.4,
            chargeTime: .estimated(minutes: 80))
        XCTAssertEqual(details.health?.designCapacityMAh, 8_579)
        XCTAssertEqual(details.health?.maximumCapacityMAh, 8_413)
        XCTAssertEqual(try XCTUnwrap(details.health?.healthPercent), 98.065_043, accuracy: 0.000_001)
        XCTAssertEqual(details.health?.temperatureCelsius, 36.4)
        XCTAssertEqual(details.health?.chargeTime, .estimated(minutes: 80))
        XCTAssertTrue(try XCTUnwrap(details.health).hasMetrics)
    }

    func testReaderParseWithoutBatteryHasNoHealth() {
        let noBattery = BatteryPowerState(BatteryStatus(
            rawPercentage: 0, isPresent: false, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false))
        let details = BatteryDetailsReader.parse(
            registry: registry, adapterWatts: nil, remainingSeconds: -1,
            state: noBattery, now: now, temperatureCelsius: 36.4,
            chargeTime: .estimated(minutes: 80))
        XCTAssertNil(details.health)
    }

    func testHealthWithoutCapacityOrTemperatureCanStillShowChargeTime() {
        let snapshot = BatteryHealthSnapshot(chargeTime: .calculating)
        XCTAssertFalse(snapshot.hasMetrics)
        XCTAssertTrue(snapshot.hasDisplayableChargeTime)
        XCTAssertFalse(BatteryHealthSnapshot(chargeTime: .paused).hasDisplayableChargeTime)
        XCTAssertFalse(BatteryHealthSnapshot(chargeTime: .unavailable).hasDisplayableChargeTime)
    }

    private func chargeDescription(
        charging: Bool, charged: Bool, timeToFull: Int, state: String = kIOPSACPowerValue
    ) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true,
            kIOPSIsChargingKey: charging,
            kIOPSIsChargedKey: charged,
            kIOPSTimeToFullChargeKey: timeToFull,
            kIOPSPowerSourceStateKey: state
        ]
    }
}

private extension Float {
    /// Little-endian `flt ` SMC payload bytes.
    var bitPatternBytesLittleEndian: [UInt8] {
        let bits = bitPattern
        return [
            UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)
        ]
    }
}
