import AppKit
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class UnifiedWiFiScaleMigrationTests: XCTestCase {
    func testOldV1ScaleIsFoldedOnceAndPreservesCapturedRenderedSize() throws {
        var oldConfiguration = IconConfigurationV1.classic
        oldConfiguration.composition.center.primary = .network
        oldConfiguration.behaviors.networkCenter.wifiScale = 2.1
        oldConfiguration.appearance.center.symbolScale = 1.2
        let oldPayload = try oldV1Payload(oldConfiguration)

        var payload = oldPayload
        var migrated = IconConfigurationV1.classic
        for _ in 0..<3 {
            migrated = try IconConfigurationCodec.decode(payload)
            XCTAssertEqual(migrated.behaviors.networkCenter.wifiScale, 1, accuracy: 0.001)
            XCTAssertEqual(migrated.appearance.center.symbolScale, 2.52, accuracy: 0.001)
            payload = try IconConfigurationCodec.encode(migrated)
        }

        let scene = IconPaletteResolver.apply(
            IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 0.66, fallback: nil), color: .primary,
                scale: migrated.behaviors.networkCenter.wifiScale
            ))),
            appearance: migrated.appearance
        )
        guard case let .symbol(symbol)? = scene.center else {
            return XCTFail("Expected a Wi-Fi center symbol")
        }
        XCTAssertEqual(symbol.scale, 1.575, accuracy: 0.001)
    }

    func testCompositionResolverAppliesCapturedWiFiScaleExactlyOnce() throws {
        var oldConfiguration = IconConfigurationV1.classic
        oldConfiguration.composition.center.primary = .network
        oldConfiguration.behaviors.networkCenter.wifiScale = 2.1
        oldConfiguration.appearance.center.symbolScale = 1.2
        let configuration = try IconConfigurationCodec.decode(oldV1Payload(oldConfiguration))
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: PresentationFixtures.snapshot(rssi: -54), audioIcon: nil),
            sources: .empty
        )

        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration)

        guard case let .symbol(centerSymbol)? = output.scene.center else {
            return XCTFail("Expected the center Wi-Fi symbol")
        }
        XCTAssertEqual(centerSymbol.scale, 1.575, accuracy: 0.001)
        XCTAssertEqual(configuration.compositionLegacyPresentationConfiguration.connection.wifiScale, 1, accuracy: 0.001)
        XCTAssertEqual(configuration.legacyPresentationConfiguration.connection.wifiScale, 1.575, accuracy: 0.001)
    }

    func testOldWiFiScaleDoesNotEnlargeUnrelatedPrimaryOrMixedFallbackSelections() throws {
        for selection in [
            SlotSelection(primary: CenterSource.bluetoothAudioOutput),
            SlotSelection(primary: CenterSource.systemBatteryPercentage),
            SlotSelection(primary: CenterSource.bluetoothAudioOutput, fallback: .network)
        ] {
            var oldConfiguration = IconConfigurationV1.classic
            oldConfiguration.composition.center = selection
            oldConfiguration.behaviors.networkCenter.wifiScale = 2.1
            oldConfiguration.appearance.center.symbolScale = 1.2

            let migrated = try IconConfigurationCodec.decode(oldV1Payload(oldConfiguration))

            XCTAssertEqual(migrated.appearance.center.symbolScale, 1.2, accuracy: 0.001,
                           "Do not apply an unused Wi-Fi scale to \(selection)")
            XCTAssertEqual(migrated.behaviors.networkCenter.wifiScale, 1, accuracy: 0.001)
        }
    }

    private func oldV1Payload(_ configuration: IconConfigurationV1) throws -> Data {
        let encoded = try JSONEncoder().encode(configuration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "wifiScaleMigrationVersion")
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func sourceURL(_ filename: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/\(filename)")
    }
}
