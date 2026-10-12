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

    func testLegacyDefaultsDoNotPromoteWiFiScaleIntoAutomaticLegacyCenterAppearance() {
        let legacy = IconPresentationConfiguration(
            battery: .standard, connection: ConnectionIconOptions(wifiScale: 1.4),
            volume: .standard, bluetooth: .standard
        )
        let migrated = IconConfigurationMigration.makeConfiguration(from: legacy)

        XCTAssertEqual(migrated.behaviors.networkCenter.wifiScale, 1, accuracy: 0.001)
        XCTAssertEqual(migrated.legacyPresentationConfiguration.connection.wifiScale, 1.4, accuracy: 0.001)
        XCTAssertEqual(migrated.appearance.center.symbolScale, 2.24, accuracy: 0.001)
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

    func testLegacyWiFiScaleSetterUpdatesTheUnifiedAppearanceValue() throws {
        let suiteName = "UnifiedWiFiScaleMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.wifiSymbolScale = 1.45
        XCTAssertEqual(first.iconConfiguration.behaviors.networkCenter.wifiScale, 1, accuracy: 0.001)
        XCTAssertEqual(first.iconConfiguration.appearance.center.symbolScale, 2.32, accuracy: 0.001)
        XCTAssertEqual(first.wifiSymbolScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(first.connectionIconOptions.wifiScale, 1.45, accuracy: 0.001)

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.wifiSymbolScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(second.iconConfiguration.behaviors.networkCenter.wifiScale, 1, accuracy: 0.001)
    }

    func testCenterScaleEditorUsesSharedCenterAndStrokeStandards() throws {
        let appearanceSource = try String(contentsOf: sourceURL("IconAppearanceEditor.swift"), encoding: .utf8)
        let editingModelSource = try String(contentsOf: sourceURL("IconDesignerEditingModel.swift"), encoding: .utf8)

        XCTAssertTrue(appearanceSource.contains("commonPercentageScaleRange"))
        XCTAssertTrue(appearanceSource.contains("commonPercentageScale(in: configuration)"))
        XCTAssertTrue(appearanceSource.contains("settingCommonPercentageScale(value"))
        XCTAssertTrue(appearanceSource.contains("IconStrokeSizingPolicy.interactiveScaleRange"))
        XCTAssertTrue(appearanceSource.contains("IconStrokeSizingPolicy.label(for: scale)"))
        XCTAssertFalse(appearanceSource.contains("%.2f×"))
        XCTAssertFalse(appearanceSource.contains("centerScaleSliderValue(for:"))
        XCTAssertFalse(appearanceSource.contains("settingCenterScaleFromAppearanceControl"))
        XCTAssertTrue(editingModelSource.contains("IconCenterSizingPolicy.percentageRange"))
        XCTAssertTrue(editingModelSource.contains("normalizedSizePercentage"))
        XCTAssertFalse(appearanceSource.contains("frame(minWidth: 90, maxWidth: 160)"))
    }

    func testOutOfUiRangeCenterScalesSurviveNormalizationAndOnlyChangeOnExplicitEdit() {
        for historicalScale in [0.75, 4.25] {
            var configuration = IconConfigurationV1.classic
            configuration.appearance.center.effectiveSymbolScale = historicalScale
            let normalized = configuration.normalized()

            XCTAssertEqual(normalized.appearance.center.effectiveSymbolScale, historicalScale)
            XCTAssertEqual(
                IconDesignerEditingModel.effectiveCenterScale(in: normalized),
                historicalScale,
                accuracy: 0.001
            )
        }
    }

    func testCenterPercentageProjectionDoesNotMutateLegacyValuesUntilExplicitEdit() {
        for (historicalScale, projected) in [(0.75, 1.0), (4.25, 1.8)] {
            var configuration = IconConfigurationV1.classic
            configuration.appearance.center.effectiveSymbolScale = historicalScale
            let before = configuration

            XCTAssertEqual(IconDesignerEditingModel.commonPercentageScaleSliderValue(for: historicalScale), projected)
            XCTAssertEqual(configuration, before, "Reading the projected knob must not edit stored configuration")

            IconDesignerEditingModel.settingCommonPercentageScale(projected, in: &configuration)
            XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, projected)
            XCTAssertEqual(configuration.appearance.center.effectiveSymbolScale, historicalScale,
                           "Explicit sizing retains historical scale data for compatibility.")
        }
    }

    func testCenterPercentageSetterClampsToOneHundredThroughOneHundredEightyPercent() {
        for (input, expected) in [(0.5, 1.0), (1.25, 1.25), (2.4, 1.8)] {
            var configuration = IconConfigurationV1.classic
            IconDesignerEditingModel.settingCommonPercentageScale(input, in: &configuration)
            XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, Optional(expected))
        }
    }

    func testOnlyAppearanceEditorOwnsTheUnifiedCenterSizeControl() throws {
        let behaviorSource = try String(contentsOf: sourceURL("IconBehaviorEditor.swift"), encoding: .utf8)
        let appearanceSource = try String(contentsOf: sourceURL("IconAppearanceEditor.swift"), encoding: .utf8)

        XCTAssertFalse(behaviorSource.contains("centerBatteryTextScaleSlider"))
        XCTAssertFalse(behaviorSource.contains("iconDesignerControlWifiSymbolScale"))
        XCTAssertTrue(appearanceSource.contains("iconDesignerControlSymbolScale"))
        XCTAssertTrue(appearanceSource.contains("commonPercentageScale(in: configuration)"))
        XCTAssertTrue(appearanceSource.contains("settingCommonPercentageScale(value"))
        XCTAssertFalse(appearanceSource.contains("store.iconConfiguration.appearance.center.symbolScale"))
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
