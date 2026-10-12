import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Center percentage interactive range")
@MainActor
struct CenterPercentageInteractiveRangeTests {
    @Test func explicitEditsUseOneHundredThroughOneHundredEightyPercent() {
        var configuration = IconConfigurationV1.classic
        IconDesignerEditingModel.settingCommonPercentageScale(0.1, in: &configuration)
        #expect(configuration.appearance.center.normalizedSizePercentage == 1.0)
        IconDesignerEditingModel.settingCommonPercentageScale(9, in: &configuration)
        #expect(configuration.appearance.center.normalizedSizePercentage == 1.8)
        #expect(configuration.normalized().appearance.center.normalizedSizePercentage == 1.8)
        #expect(IconDesignerEditingModel.commonPercentageScaleRange == 1.0...1.8)
        #expect(IconDesignerEditingModel.commonPercentageScaleSliderValue(for: 0.5) == 1.0)
        #expect(IconDesignerEditingModel.commonPercentageScaleSliderValue(for: 1.8) == 1.8)
        #expect(IconDesignerEditingModel.commonPercentageScaleSliderValue(for: 2.0) == 1.8)
    }

    @Test func percentageLabelsShowTheUnprojectedScaleWhileSliderProjectsLegacyValues() {
        #expect(IconDesignerEditingModel.commonPercentageScaleLabel(for: 0.75) == "75%")
        #expect(IconDesignerEditingModel.commonPercentageScaleLabel(for: 1.0) == "100%")
        #expect(IconDesignerEditingModel.commonPercentageScaleLabel(for: 1.8) == "180%")
        #expect(IconDesignerEditingModel.commonPercentageScaleSliderValue(for: 0.75) == 1.0)
    }

    @Test func openingLegacyValueProjectsTheControlWithoutChangingStorageOrRenderedScale() throws {
        var configuration = IconConfigurationV1.classic
        configuration.appearance.center.normalizedPercentageScale = 0.75

        let openedConfiguration = configuration.normalized()
        #expect(openedConfiguration.appearance.center.normalizedPercentageScale == 0.75)
        #expect(IconDesignerEditingModel.commonPercentageScale(
            for: .systemBatteryPercentage, in: openedConfiguration
        ) == 0.75)
        #expect(IconDesignerEditingModel.commonPercentageScaleSliderValue(for: 0.75) == 1.0)
        #expect(configuration.appearance.center.normalizedPercentageScale == 0.75)

        let legacyScene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: openedConfiguration.appearance,
            centerSource: .systemBatteryPercentage
        )
        #expect(centerTextScale(legacyScene) == 0.75 * CenterPercentageScaleCalibration.percentageScaleForCommonSize)

        let commonScene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: IconConfigurationV1.classic.appearance,
            centerSource: .systemBatteryPercentage
        )
        let environment = renderEnvironment(size: 240, scale: 1)
        let legacyImage = try #require(StatusIconRenderer.render(scene: legacyScene, environment: environment))
        let commonImage = try #require(StatusIconRenderer.render(scene: commonScene, environment: environment))
        #expect(try visibleInkHeight(legacyImage) < visibleInkHeight(commonImage))

        IconDesignerEditingModel.settingCommonPercentageScale(
            IconDesignerEditingModel.commonPercentageScaleSliderValue(for: 0.75),
            in: &configuration
        )
        #expect(configuration.appearance.center.normalizedSizePercentage == 1.0)
        #expect(configuration.appearance.center.normalizedPercentageScale == 0.75)
    }

    @Test func batteryAndWiFiKeepTheirCommonVisibleHeightAtOneHundredPercent() throws {
        var configuration = IconConfigurationV1.classic
        IconDesignerEditingModel.settingCommonPercentageScale(1.0, in: &configuration)
        let appearance = configuration.normalized().appearance
        let batteryScene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: appearance,
            centerSource: .systemBatteryPercentage
        )
        let wifiScene = wifiScene(appearance: appearance)

        for (size, scale) in [(CGFloat(120), CGFloat(2)), (240, 1)] {
            let environment = renderEnvironment(size: size, scale: scale)
            let battery = try #require(StatusIconRenderer.render(scene: batteryScene, environment: environment))
            let wifi = try #require(StatusIconRenderer.render(scene: wifiScene, environment: environment))
            let batteryHeight = try visibleInkHeight(battery)
            let wifiHeight = try visibleInkHeight(wifi)
            #expect(abs(batteryHeight - wifiHeight) <= 2)
        }

        let batteryDock = try dockCGImage(scene: batteryScene)
        let wifiDock = try dockCGImage(scene: wifiScene)
        let batteryDockHeight = try visibleInkHeight(batteryDock, whiteOnly: true)
        let wifiDockHeight = try visibleInkHeight(wifiDock, whiteOnly: true)
        #expect(abs(batteryDockHeight - wifiDockHeight) <= 3)
    }

    @Test func bothSourcesRenderAtOneHundredAndOneHundredEightyPercentAcrossSurfaces() throws {
        for commonScale in [1.0, 1.8] {
            var configuration = IconConfigurationV1.classic
            IconDesignerEditingModel.settingCommonPercentageScale(commonScale, in: &configuration)
            let appearance = configuration.normalized().appearance
            let batteryScene = IconPaletteResolver.apply(
                IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
                appearance: appearance,
                centerSource: .systemBatteryPercentage
            )
            let networkScene = wifiScene(appearance: appearance)

            for (surface, size, scale) in [("menu", CGFloat(120), CGFloat(2)), ("preview", 240, 1)] {
                let environment = renderEnvironment(size: size, scale: scale)
                let battery = try #require(StatusIconRenderer.render(scene: batteryScene, environment: environment))
                let wifi = try #require(StatusIconRenderer.render(scene: networkScene, environment: environment))
                let batteryWidth = try visibleInkBounds(battery).width
                let wifiWidth = try visibleInkBounds(wifi).width
                #expect(batteryWidth > 0, "battery text on \(surface) at \(commonScale * 100)%")
                #expect(wifiWidth > 0, "Wi-Fi on \(surface) at \(commonScale * 100)%")
            }

            let batteryDock = try dockCGImage(scene: batteryScene)
            let wifiDock = try dockCGImage(scene: networkScene)
            let batteryDockWidth = try visibleInkBounds(batteryDock, whiteOnly: true).width
            let wifiDockWidth = try visibleInkBounds(wifiDock, whiteOnly: true).width
            #expect(batteryDockWidth > 0)
            #expect(wifiDockWidth > 0)
        }
    }

    @Test func oneHundredEightyPercentTextBoundsAndRasterConfirmRingOverlap() throws {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        IconDesignerEditingModel.settingCommonPercentageScale(1.8, in: &configuration)
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false,
                                           isLowPowerMode: false, isConnectedToPower: false),
                    wifi: .placeholder,
                    volume: .placeholder
                ),
                audioIcon: nil
            ),
            sources: .empty
        )
        let scene = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration).scene
        let environment = renderEnvironment(size: StatusIconGeometry.canvas.width, scale: 1)
        let textImage = try #require(StatusIconRenderer.render(scene: IconSceneState(center: scene.center), environment: environment))
        let ringImage = try #require(StatusIconRenderer.render(scene: IconSceneState(outerRing: scene.outerRing), environment: environment))
        let textBounds = try visibleInkBounds(textImage)
        let ringPixels = try PixelBuffer(image: ringImage)
        let textPixels = try PixelBuffer(image: textImage)
        var overlapCount = 0
        for y in 0..<ringPixels.height {
            for x in 0..<ringPixels.width {
                if ringPixels.rgba(x: x, y: y).alpha >= 32,
                   textPixels.rgba(x: x, y: y).alpha >= 32 {
                    overlapCount += 1
                }
            }
        }
        #expect(textBounds.width > 80, "the current ring interior is approximately 80 design units wide")
        #expect(overlapCount > 0)
    }

    @Test func undoRestoresLegacyAppearanceAfterAnExplicitMaximumEdit() throws {
        let suiteName = "CenterPercentageInteractiveRange.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration { configuration in
            configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
            configuration.appearance.center.effectiveSymbolScale = 1.6
            configuration.behaviors.systemBatteryRing.textScale = 1.65
        }
        let editor = IconDesignerEditorModel(store: store)
        editor.updateIconConfiguration(coalescingKey: "center-percentage-range") {
            IconDesignerEditingModel.settingCommonPercentageScale(1.8, in: &$0)
        }
        #expect(store.iconConfiguration.appearance.center.normalizedSizePercentage == 1.8)
        #expect(store.iconConfiguration.appearance.center.effectiveSymbolScale == 1.6)
        editor.undo()
        #expect(store.iconConfiguration.appearance.center.normalizedPercentageScale == nil)
        #expect(store.iconConfiguration.appearance.center.effectiveSymbolScale == 1.6)
        #expect(store.iconConfiguration.behaviors.systemBatteryRing.textScale == 1.65)
    }

    @Test func bothEditorControlsUseTheSharedRangeAndRawLabel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appearance = try String(contentsOf: root.appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconAppearanceEditor.swift"), encoding: .utf8)
        let behavior = try String(contentsOf: root.appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconBehaviorEditor.swift"), encoding: .utf8)
        #expect(appearance.contains("IconDesignerEditingModel.commonPercentageScaleRange"))
        #expect(appearance.contains("commonPercentageScaleLabel(for: scale)"))
        #expect(appearance.contains("commonPercentageScaleSliderValue(for: rawValue)"))
        #expect(appearance.contains("IconStrokeSizingPolicy.interactiveScaleRange"))
        #expect(!behavior.contains("commonPercentageScaleRange"),
                "Source-specific behavior controls must not duplicate the element-wide center size control.")
    }

    private func wifiScene(appearance: IconAppearanceConfiguration) -> IconSceneState {
        IconPaletteResolver.apply(
            IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary,
                scale: 1
            ))),
            appearance: appearance,
            centerSource: .network
        )
    }

    private func centerTextScale(_ scene: IconSceneState) -> Double? {
        guard case let .text(text)? = scene.center else { return nil }
        return text.scale
    }

    private func renderEnvironment(size: CGFloat, scale: CGFloat) -> StatusIconRenderEnvironment {
        StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
    }

    private func dockCGImage(scene: IconSceneState) throws -> CGImage {
        let image = try #require(DockIconRenderer.image(scene: scene, pixelLength: 512))
        return try #require((image.representations.first as? NSBitmapImageRep)?.cgImage)
    }

    private func visibleInkHeight(_ image: CGImage, whiteOnly: Bool = false) throws -> CGFloat {
        try visibleInkBounds(image, whiteOnly: whiteOnly).height
    }

    private func visibleInkBounds(_ image: CGImage, whiteOnly: Bool = false) throws -> CGRect {
        let pixels = try PixelBuffer(image: image)
        var minX = pixels.width
        var maxX = -1
        var minY = pixels.height
        var maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let pixel = pixels.rgba(x: x, y: y)
                let visible = whiteOnly
                    ? pixel.red >= 240 && pixel.green >= 240 && pixel.blue >= 240
                    : pixel.alpha >= 32
                if visible {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
