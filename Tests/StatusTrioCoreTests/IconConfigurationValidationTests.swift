import XCTest
@testable import StatusTrioCore

final class IconConfigurationValidationTests: XCTestCase {
    func testClassicCodecRoundTrip() throws {
        let data = try IconConfigurationCodec.encode(.classic)
        XCTAssertEqual(try IconConfigurationCodec.decode(data), .classic)
    }

    func testDuplicateFallbackIsRemoved() {
        var value = IconConfigurationV1.classic
        value.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .systemBattery)

        XCTAssertNil(value.normalized().composition.outerRing.fallback)
    }

    func testNoneFallbackIsRemoved() {
        var value = IconConfigurationV1.classic
        value.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: RingSource.none)

        XCTAssertNil(value.normalized().composition.outerRing.fallback)
    }

    func testNonePrimaryRemovesFallback() {
        var value = IconConfigurationV1.classic
        value.composition.outerRing = SlotSelection(primary: .none, fallback: .systemBattery)
        value.composition.center = SlotSelection(primary: .none, fallback: .network)
        value.composition.footer = SlotSelection(primary: .none, fallback: .systemVolume)

        let normalized = value.normalized()
        XCTAssertNil(normalized.composition.outerRing.fallback)
        XCTAssertNil(normalized.composition.center.fallback)
        XCTAssertNil(normalized.composition.footer.fallback)
    }

    func testCodecRejectsUnknownSchemaBeforeDecodingConfiguration() throws {
        let data = Data(#"{"schemaVersion":99,"composition":{}}"#.utf8)

        XCTAssertThrowsError(try IconConfigurationCodec.decode(data)) { error in
            XCTAssertEqual(error as? IconConfigurationCodecError, .unsupportedSchemaVersion(99))
        }
    }

    func testCodecRejectsUnknownSourceEnum() throws {
        let data = Data(#"{"schemaVersion":1,"composition":{"outerRing":{"primary":"futureBattery","fallback":null},"center":{"primary":"automaticLegacy","fallback":null},"footer":{"primary":"systemVolume","fallback":null},"centerOverride":{"networkProblemOverridesPrimary":false}},"behaviors":{},"appearance":{}}"#.utf8)

        XCTAssertThrowsError(try IconConfigurationCodec.decode(data)) { error in
            XCTAssertEqual(error as? IconConfigurationCodecError, .malformedData)
        }
    }

    func testCodecRejectsCorruptData() {
        XCTAssertThrowsError(try IconConfigurationCodec.decode(Data([0x00, 0xFF, 0x01])))
    }

    func testResettingOneSlotLeavesOtherSlotsUnchanged() {
        var value = IconConfigurationV1.classic
        value.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        value.appearance.center.symbolScale = 1.4
        value.behaviors.networkCenter.showsWiFiIconForEthernet = true
        value.appearance.outerRing.strokeScale = 1.5
        value.appearance.footer.strokeScale = 0.75

        let reset = value.resetting(.center)

        XCTAssertEqual(reset.composition.outerRing, value.composition.outerRing)
        XCTAssertEqual(reset.composition.footer, value.composition.footer)
        XCTAssertEqual(reset.appearance.outerRing, value.appearance.outerRing)
        XCTAssertEqual(reset.appearance.footer, value.appearance.footer)
        XCTAssertEqual(reset.behaviors.systemBatteryRing, value.behaviors.systemBatteryRing)
        XCTAssertEqual(reset.behaviors.systemVolumeFooter, value.behaviors.systemVolumeFooter)
        XCTAssertEqual(reset.composition.center, IconConfigurationV1.classic.composition.center)
        XCTAssertEqual(reset.appearance.center, IconConfigurationV1.classic.appearance.center)
        XCTAssertEqual(reset.behaviors.networkCenter, IconConfigurationV1.classic.behaviors.networkCenter)
    }

    func testClassicIsPureValueAndDoesNotConstructMonitoring() {
        XCTAssertEqual(IconConfigurationV1.classic.composition.outerRing.primary, .systemBattery)
        XCTAssertEqual(IconConfigurationV1.classic.composition.center.primary, .automaticLegacy)
        XCTAssertEqual(IconConfigurationV1.classic.composition.footer.primary, .systemVolume)
    }

    func testNormalizationBoundsAppearanceScales() {
        var value = IconConfigurationV1.classic
        value.appearance.outerRing.strokeScale = 99
        value.appearance.center.symbolScale = .infinity
        value.appearance.footer.strokeScale = .nan

        let normalized = value.normalized()
        XCTAssertEqual(normalized.appearance.outerRing.strokeScale, 2.5)
        XCTAssertEqual(normalized.appearance.center.symbolScale, 1.6)
        XCTAssertEqual(normalized.appearance.footer.strokeScale, RingStrokeStyle.regular.scale)
    }
}
