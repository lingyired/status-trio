import Foundation
import SMCPrivateAPI
import XCTest

/// Exercises the same pure validators called by the real C read/write bridge.
/// No SMC client is opened and no IOKit request is issued.
final class SMCPrivateAPIValidationTests: XCTestCase {
    func testKeyNamesMatchExactlyAndNeverAllowAdapterOrFanKeys() {
        for key in ["BCLM", "CH0B", "CH0C", "CHTE"] {
            XCTAssertTrue(STSMIsWriteAllowlisted(key))
        }
        for key in ["", "BCL", "BCLMextra", "CH0Bextra", "CH0I", "CHIE", "F0Tg", "BFCL", "CHWA"] {
            XCTAssertFalse(STSMIsWriteAllowlisted(key), key)
        }
    }

    func testMetadataRequiresTheExactTypeAndWidthForEachKey() {
        XCTAssertTrue(STSMValidateChargeKeyInfo("BCLM", "ui8 ", 1))
        XCTAssertTrue(STSMValidateChargeKeyInfo("CH0B", "ui8 ", 1))
        XCTAssertTrue(STSMValidateChargeKeyInfo("CH0C", "ui8 ", 1))
        XCTAssertTrue(STSMValidateChargeKeyInfo("CHTE", "ui32", 4))
        for size: UInt32 in [0, 2, 3, 4, 32] {
            XCTAssertFalse(STSMValidateChargeKeyInfo("BCLM", "ui8 ", size))
        }
        XCTAssertFalse(STSMValidateChargeKeyInfo("CHTE", "ui8 ", 4))
        XCTAssertFalse(STSMValidateChargeKeyInfo("CH0B", "ui32", 1))
        XCTAssertFalse(STSMValidateChargeKeyInfo("CHTE", "ui32", 1))
        XCTAssertFalse(STSMValidateChargeKeyInfo("BCLM", "flt ", 1))
    }

    func testWriteValuesAreClosedToChargeCeilingsAndTheTwoGateValues() {
        XCTAssertTrue(valid("BCLM", [50])) // captured original may be below 80
        XCTAssertTrue(valid("BCLM", [80]))
        XCTAssertTrue(valid("BCLM", [100]))
        XCTAssertFalse(valid("BCLM", [0]))
        XCTAssertFalse(valid("BCLM", [101]))
        XCTAssertFalse(valid("BCLM", [80, 0]))
        for key in ["CH0B", "CH0C"] {
            XCTAssertTrue(valid(key, [0]))
            XCTAssertTrue(valid(key, [2]))
            XCTAssertFalse(valid(key, [1]))
            XCTAssertFalse(valid(key, [3]))
        }
        XCTAssertTrue(valid("CHTE", [0, 0, 0, 0]))
        XCTAssertTrue(valid("CHTE", [1, 0, 0, 0]))
        XCTAssertFalse(valid("CHTE", [0, 0, 0, 1]))
        XCTAssertFalse(valid("CHTE", [2, 0, 0, 0]))
        XCTAssertFalse(valid("CH0I", [0]))
        XCTAssertFalse(valid("CHTE", []))
    }

    private func valid(_ key: String, _ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBufferPointer { buffer in
            STSMValidateChargeWrite(key, buffer.baseAddress, UInt32(buffer.count))
        }
    }
}
