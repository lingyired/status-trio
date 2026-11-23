import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconDesignerOuterBatteryTextScaleTests: XCTestCase {
    func testLegacyRangeAndFivePercentStepsMapToTheShippedTextScaleBasis() {
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScaleRange, 0.9...1.1)
        XCTAssertEqual(BatteryIconOptions.defaultTextScale, 1.8)
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScale(forSliderValue: 0.9), 1.62, accuracy: 1e-12)
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScale(forSliderValue: 1.0), 1.8, accuracy: 1e-12)
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScale(forSliderValue: 1.1), 1.98, accuracy: 1e-12)
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScaleLabel(for: 1.62), "90%")
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScaleLabel(for: 1.8), "100%")
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScaleLabel(for: 1.98), "110%")
    }

    func testProjectionPreservesHistoricalRawValueUntilAnExplicitEdit() {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemBatteryRing.textScale = 2.4
        let rawTextScale = configuration.behaviors.systemBatteryRing.textScale

        XCTAssertEqual(IconDesignerEditingModel.batteryTextScaleSliderValue(for: rawTextScale), 1.1)
        XCTAssertEqual(IconDesignerEditingModel.batteryTextScaleLabel(for: rawTextScale), "133%")
        XCTAssertEqual(configuration.behaviors.systemBatteryRing.textScale, rawTextScale)

        IconDesignerEditingModel.settingBatteryTextScale(
            IconDesignerEditingModel.batteryTextScaleSliderValue(for: rawTextScale),
            in: &configuration
        )
        XCTAssertEqual(configuration.behaviors.systemBatteryRing.textScale, 1.98, accuracy: 1e-12)
    }

    func testLegacyMenuDockAndPreviewRenderingMatchAtNinetyOneHundredAndOneHundredTenPercent() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerOuterBatteryTextScale.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let legacyStore = SettingsStore(defaults: defaults)
        var baseConfiguration = IconConfigurationV1.classic
        baseConfiguration.composition.outerRing = SlotSelection(primary: .systemBattery)
        baseConfiguration.behaviors.systemBatteryRing.showsPercentage = true
        baseConfiguration.behaviors.systemBatteryRing.showsChargingEffect = false
        baseConfiguration.behaviors.systemBatteryRing.showsChargingBoltHeartbeat = false

        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: false,
                                           isLowPowerMode: false, isConnectedToPower: false),
                    wifi: .placeholder,
                    volume: .placeholder
                ),
                audioIcon: nil
            ),
            sources: .empty
        )

        for legacyRatio in [0.9, 1.0, 1.1] {
            legacyStore.updateIconConfiguration { $0 = baseConfiguration }
            legacyStore.batterySymbolScale = legacyRatio
            let legacyConfiguration = legacyStore.iconConfiguration

            var designerConfiguration = baseConfiguration
            IconDesignerEditingModel.settingBatteryTextScale(legacyRatio, in: &designerConfiguration)
            XCTAssertEqual(
                designerConfiguration.behaviors.systemBatteryRing.textScale,
                legacyConfiguration.behaviors.systemBatteryRing.textScale,
                accuracy: 1e-12
            )

            let menu = IconCompositionResolver.resolve(inputs: inputs, configuration: designerConfiguration).scene
            let legacyMenu = IconCompositionResolver.resolve(inputs: inputs, configuration: legacyConfiguration).scene
            let preview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: designerConfiguration).scene
            XCTAssertEqual(menu, legacyMenu, "menu-bar scene at \(Int(legacyRatio * 100))%")
            XCTAssertEqual(preview, legacyMenu, "designer preview scene at \(Int(legacyRatio * 100))%")
            XCTAssertEqual(try outerTextScale(menu), legacyRatio * BatteryIconOptions.defaultTextScale, accuracy: 1e-12)

            let menuImage = try XCTUnwrap(StatusIconRenderer.render(
                scene: menu,
                environment: StatusIconRenderEnvironment(
                    size: 120, scale: 2, foreground: CGColor(gray: 1, alpha: 1),
                    criticalColor: StatusIconRenderer.defaultCriticalColor
                )
            ))
            let legacyImage = try XCTUnwrap(StatusIconRenderer.render(
                scene: legacyMenu,
                environment: StatusIconRenderEnvironment(
                    size: 120, scale: 2, foreground: CGColor(gray: 1, alpha: 1),
                    criticalColor: StatusIconRenderer.defaultCriticalColor
                )
            ))
            XCTAssertEqual(try pixelData(menuImage), try pixelData(legacyImage), "menu-bar pixels")

            let previewImage = try XCTUnwrap(StatusIconRenderer.render(
                scene: preview,
                environment: StatusIconRenderEnvironment(
                    size: 240, scale: 1, foreground: CGColor(gray: 1, alpha: 1),
                    criticalColor: StatusIconRenderer.defaultCriticalColor
                )
            ))
            let legacyPreviewImage = try XCTUnwrap(StatusIconRenderer.render(
                scene: legacyMenu,
                environment: StatusIconRenderEnvironment(
                    size: 240, scale: 1, foreground: CGColor(gray: 1, alpha: 1),
                    criticalColor: StatusIconRenderer.defaultCriticalColor
                )
            ))
            XCTAssertEqual(try pixelData(previewImage), try pixelData(legacyPreviewImage), "preview pixels")

            let dock = try XCTUnwrap(DockIconRenderer.image(scene: menu, pixelLength: 512))
            let legacyDock = try XCTUnwrap(DockIconRenderer.image(scene: legacyMenu, pixelLength: 512))
            let dockCG = try XCTUnwrap((dock.representations.first as? NSBitmapImageRep)?.cgImage)
            let legacyDockCG = try XCTUnwrap((legacyDock.representations.first as? NSBitmapImageRep)?.cgImage)
            XCTAssertEqual(try pixelData(dockCG), try pixelData(legacyDockCG), "Dock pixels")
        }
    }

    func testOuterTextEditIsIndependentAndUndoRestoresThePreEditScale() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerOuterBatteryTextScaleUndo.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration {
            $0.behaviors.systemBatteryRing.textScale = 1.8
            $0.appearance.center.normalizedPercentageScale = 1.5
            $0.appearance.center.symbolScale = 2.4
        }
        let editor = IconDesignerEditorModel(store: store)
        editor.updateIconConfiguration(coalescingKey: "behavior.batteryTextScale") {
            IconDesignerEditingModel.settingBatteryTextScale(0.9, in: &$0)
        }
        XCTAssertEqual(store.iconConfiguration.behaviors.systemBatteryRing.textScale, 1.62, accuracy: 1e-12)
        XCTAssertEqual(store.iconConfiguration.appearance.center.normalizedPercentageScale, 1.5)
        XCTAssertEqual(store.iconConfiguration.appearance.center.symbolScale, 2.4)
        editor.undo()
        XCTAssertEqual(store.iconConfiguration.behaviors.systemBatteryRing.textScale, 1.8, accuracy: 1e-12)
        XCTAssertEqual(store.iconConfiguration.appearance.center.normalizedPercentageScale, 1.5)
        XCTAssertEqual(store.iconConfiguration.appearance.center.symbolScale, 2.4)
    }

    private func outerTextScale(_ scene: IconSceneState) throws -> Double {
        guard case let .text(text)? = scene.outerRing?.accessory else {
            XCTFail("Expected outer-ring percentage text")
            throw TestFailure.expectedOuterText
        }
        return text.scale
    }

    private func pixelData(_ image: CGImage) throws -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var data = Data(count: image.height * bytesPerRow)
        let rendered = data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(rendered)
        return data
    }

    private enum TestFailure: Error {
        case expectedOuterText
    }
}
