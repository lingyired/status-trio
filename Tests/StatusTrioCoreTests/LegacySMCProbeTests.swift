import XCTest
@testable import StatusTrioCore

/// Phase 2 read-only capability-discovery tests, run entirely through FakeSMC.
/// No IOKit and no writes.
final class LegacySMCProbeTests: XCTestCase {
    private func ui8(_ key: String, _ value: UInt8) -> [String: (info: LegacySMCKeyInfo, data: Data)] {
        [key: (info: LegacySMCKeyInfo(dataType: "ui8", dataSize: 1), data: Data([value]))]
    }
    private func ui32(_ key: String, _ value: UInt32) -> [String: (info: LegacySMCKeyInfo, data: Data)] {
        var data = Data()
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        return [key: (info: LegacySMCKeyInfo(dataType: "ui32", dataSize: 4), data: data)]
    }

    func testIntelBCLMProbeDetectsKey() {
        let smc = FakeSMC(store: ui8("BCLM", 80))
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .intel,
            osBand: .thirteenToFourteen,
            hasInternalBattery: true
        )
        XCTAssertTrue(caps.presentKeys.contains("BCLM"))
        XCTAssertEqual(caps.keyInfo["BCLM"]?.dataType, "ui8")
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .intelBCLM)
    }

    func testSiliconProbeDetectsPairAndPrefersIt() {
        var store = ui8("CH0B", 0)
        store.merge(ui8("CH0C", 0)) { _, new in new }
        let smc = FakeSMC(store: store)
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .appleSilicon,
            osBand: .thirteenToFourteen,
            hasInternalBattery: true
        )
        XCTAssertTrue(caps.presentKeys.contains("CH0B"))
        XCTAssertTrue(caps.presentKeys.contains("CH0C"))
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .siliconLegacyInhibit)
    }

    func testSiliconProbeDetectsCHTEWhenNoPair() {
        let smc = FakeSMC(store: ui32("CHTE", 0))
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .appleSilicon,
            osBand: .fifteen,
            hasInternalBattery: true
        )
        XCTAssertTrue(caps.presentKeys.contains("CHTE"))
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .siliconLegacyInhibit)
    }

    func testKeyWithWrongTypeIsIgnored() {
        // CH0B exists but as ui32 (wrong) -> not recognized.
        let smc = FakeSMC(store: ui32("CH0B", 0))
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .appleSilicon,
            osBand: .thirteenToFourteen,
            hasInternalBattery: true
        )
        XCTAssertFalse(caps.presentKeys.contains("CH0B"))
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .unsupported)
    }

    func testKeyWithAbsurdWidthIsIgnored() {
        // A defensively oversized payload must not be mistaken for a ceiling.
        let big = [
            "BCLM": (
                info: LegacySMCKeyInfo(dataType: "ui8", dataSize: 99),
                data: Data(repeating: 0, count: 99)
            ),
        ]
        let smc = FakeSMC(store: big)
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .intel,
            osBand: .thirteenToFourteen,
            hasInternalBattery: true
        )
        XCTAssertFalse(caps.presentKeys.contains("BCLM"))
    }

    func testProbeRejectsNearMissWidthsAndInconsistentPayloads() {
        let cases: [(String, String, Int, [UInt8])] = [
            ("BCLM", "ui8", 2, [80, 0]),
            ("CH0B", "ui8", 4, [0, 0, 0, 0]),
            ("CHTE", "ui32", 1, [0]),
            ("CHTE", "ui32", 4, [0]),
            ("BCLM", "ui8", 1, []),
            ("BCLM", "ui8", 1, [255]),
            ("CH0C", "ui8", 1, [3]),
            ("CHTE", "ui32", 4, [0, 0, 0, 1]),
        ]
        for (key, type, size, bytes) in cases {
            let smc = FakeSMC(store: [key: (
                info: LegacySMCKeyInfo(dataType: type, dataSize: size), data: Data(bytes)
            )])
            let caps = LegacySMCProbe.probe(smc: smc, architecture: .intel,
                                           osBand: .fifteen, hasInternalBattery: true)
            XCTAssertFalse(caps.presentKeys.contains(key), "\(key) \(type)/\(size): \(bytes)")
            XCTAssertTrue(smc.writeLog.isEmpty)
        }
    }

    func testProbeAcceptsCanonicalPaddedSMCUint8Type() {
        let smc = FakeSMC(store: ["BCLM": (
            info: LegacySMCKeyInfo(dataType: "ui8 ", dataSize: 1), data: Data([90])
        )])
        let caps = LegacySMCProbe.probe(smc: smc, architecture: .intel,
                                       osBand: .thirteenToFourteen, hasInternalBattery: true)
        XCTAssertTrue(caps.presentKeys.contains("BCLM"))
        XCTAssertTrue(smc.writeLog.isEmpty)
    }

    func testNoBatteryMakesEverythingUnsupported() {
        let smc = FakeSMC(store: ui8("BCLM", 80))
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .intel,
            osBand: .thirteenToFourteen,
            hasInternalBattery: false
        )
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .unsupported)
        XCTAssertFalse(caps.hasUsableBattery)
    }

    func testEmptyStoreIsUnsupported() {
        let smc = FakeSMC(store: [:])
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .intel,
            osBand: .thirteenToFourteen,
            hasInternalBattery: true
        )
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .unsupported)
    }

    func testMachineOSOutOfBandDoesNotEnableBackend() {
        let smc = FakeSMC(store: ui8("BCLM", 80))
        let caps = LegacySMCProbe.probe(
            smc: smc,
            architecture: .intel,
            osBand: .sixteenToTahoeLegacy,
            hasInternalBattery: true
        )
        // present, but band blocks the backend: legacy must not appear on 16-26.3
        XCTAssertTrue(caps.presentKeys.contains("BCLM"))
        XCTAssertEqual(LegacyChargeBackend.select(using: caps), .unsupported)
    }
}