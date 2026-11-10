import Foundation
import XCTest
@testable import StatusTrioCore

final class IconConfigurationSchemaExtensionTests: XCTestCase {
    func testNewIconSchemaFieldsRoundTripThroughCodec() throws {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.batteryMarkers = BatteryMarkerBehavior(
            onBattery: .hidden,
            charging: .percentage,
            connected: .bolt,
            noBattery: .plug
        )
        configuration.behaviors.splitGapProgress = true
        configuration.appearance.bluetoothIconColor = BluetoothIconColorConfiguration(storageValue: "primary")
        configuration.appearance.inputSourceMarkerStyle = .script
        configuration.appearance.bluetoothSymbolScale = 1.9

        let decoded = try IconConfigurationCodec.decode(try IconConfigurationCodec.encode(configuration))
        XCTAssertEqual(decoded.behaviors.batteryMarkers, configuration.behaviors.batteryMarkers)
        XCTAssertEqual(decoded.behaviors.splitGapProgress, true)
        XCTAssertEqual(decoded.appearance.bluetoothIconColor, configuration.appearance.bluetoothIconColor)
        XCTAssertEqual(decoded.appearance.inputSourceMarkerStyle, .script)
        XCTAssertEqual(decoded.appearance.bluetoothSymbolScale, 1.9, accuracy: 0.0001)
    }

    func testLegacyPayloadWithoutNewFieldsDecodesToClassicDefaults() throws {
        let encoded = try IconConfigurationCodec.encode(.classic)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var behaviors = try XCTUnwrap(root["behaviors"] as? [String: Any])
        var appearance = try XCTUnwrap(root["appearance"] as? [String: Any])
        behaviors.removeValue(forKey: "batteryMarkers")
        behaviors.removeValue(forKey: "splitGapProgress")
        appearance.removeValue(forKey: "bluetoothIconColor")
        appearance.removeValue(forKey: "inputSourceMarkerStyle")
        appearance.removeValue(forKey: "bluetoothSymbolScale")
        root["behaviors"] = behaviors
        root["appearance"] = appearance

        let legacy = try JSONSerialization.data(withJSONObject: root)
        let decoded = try IconConfigurationCodec.decode(legacy)
        XCTAssertEqual(decoded.behaviors.batteryMarkers, .classic)
        XCTAssertEqual(decoded.behaviors.splitGapProgress, false)
        XCTAssertEqual(decoded.appearance.bluetoothIconColor, .classic)
        XCTAssertEqual(decoded.appearance.inputSourceMarkerStyle, .systemIcon)
        XCTAssertEqual(
            decoded.appearance.bluetoothSymbolScale,
            BluetoothAudioIconOptions.defaultSymbolScale,
            accuracy: 0.0001
        )
    }
}
