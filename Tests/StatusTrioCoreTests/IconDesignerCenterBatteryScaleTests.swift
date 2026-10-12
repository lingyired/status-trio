import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconDesignerCenterBatteryScaleTests: XCTestCase {
    func testCommonPercentageScaleIsOptionalAndLegacyScaleRemainsSeparate() throws {
        let appearanceSource = try String(
            contentsOf: sourceURL("Sources/StatusTrioCore/Presentation/Icon/Configuration/IconAppearanceConfiguration.swift"),
            encoding: .utf8
        )
        let paletteSource = try String(
            contentsOf: sourceURL("Sources/StatusTrioCore/Presentation/Icon/Resolution/IconPaletteResolver.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appearanceSource.contains("var normalizedPercentageScale: Double? = nil"))
        XCTAssertTrue(paletteSource.contains("normalizedPercentageScale"))
        XCTAssertTrue(paletteSource.contains("wifiScaleForCommonPercentageSize"))
    }

    func testAllCenterSourcesUseOneAppearanceSizeControlAndKeepOuterTextScale() throws {
        let behaviorSource = try String(contentsOf: sourceURL("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconBehaviorEditor.swift"), encoding: .utf8)
        let appearanceSource = try String(contentsOf: sourceURL("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconAppearanceEditor.swift"), encoding: .utf8)

        XCTAssertFalse(behaviorSource.contains("centerBatteryTextScaleSlider"))
        XCTAssertTrue(appearanceSource.contains("commonPercentageScale(in: configuration)"))
        XCTAssertTrue(appearanceSource.contains("settingCommonPercentageScale(value"))
        XCTAssertTrue(appearanceSource.contains("commonPercentageScaleRange"))
        XCTAssertTrue(appearanceSource.contains("IconStrokeSizingPolicy.interactiveScaleRange"))
        XCTAssertTrue(appearanceSource.contains("IconStrokeSizingPolicy.strokeScale(for: value)"))
        XCTAssertFalse(appearanceSource.contains("%.2f×"))

        XCTAssertTrue(behaviorSource.contains("batteryTextScaleSlider"))
        XCTAssertTrue(behaviorSource.contains("batteryTextScaleSliderValue(for: rawTextScale)"))
        XCTAssertTrue(behaviorSource.contains("settingBatteryTextScale(value"))
        XCTAssertTrue(behaviorSource.contains("batteryTextScaleLabel(for: rawTextScale)"))
    }

    func testCommonPercentageScaleMapsBatteryAndWiFiToTheSameRelativeSize() throws {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        IconDesignerEditingModel.settingCommonPercentageScale(1.2, in: &configuration)
        XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, 1.2)
        XCTAssertNil(configuration.appearance.center.effectiveSymbolScale)
        XCTAssertEqual(
            IconDesignerEditingModel.commonPercentageScale(for: .network, in: configuration),
            1.2,
            accuracy: 1e-12
        )

        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false,
                                           isLowPowerMode: false, isConnectedToPower: false),
                    wifi: WiFiStatus(state: .connected, rssi: -30),
                    connection: .wifi,
                    volume: .placeholder
                ),
                audioIcon: nil
            ),
            sources: .empty
        )
        var textConfiguration = configuration
        textConfiguration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        var wifiConfiguration = configuration
        wifiConfiguration.composition.center = SlotSelection(primary: .network)
        let textOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: textConfiguration)
        let wifiOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: wifiConfiguration)
        XCTAssertEqual(textOutput.trace.center.selectedSourceID, CenterSource.systemBatteryPercentage.rawValue)
        XCTAssertEqual(wifiOutput.trace.center.selectedSourceID, CenterSource.network.rawValue)
        let textScene = textOutput.scene
        let wifiScene = wifiOutput.scene

        XCTAssertEqual(textScene.center?.normalizedSizePercentageValue, 1.2)
        XCTAssertEqual(wifiScene.center?.normalizedSizePercentageValue, 1.2)
    }

    func testCommonPercentageScaleBoundsExplicitEditsToOneHundredThroughOneHundredEightyPercent() {
        var configuration = IconConfigurationV1.classic
        IconDesignerEditingModel.settingCommonPercentageScale(0.1, in: &configuration)
        XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, 1.0)
        IconDesignerEditingModel.settingCommonPercentageScale(9, in: &configuration)
        XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, 1.8)
        XCTAssertEqual(configuration.normalized().appearance.center.normalizedSizePercentage, 1.8)
    }

    func testMissingNormalizedPercentageScaleDecodesAsNilAndLegacyValueRoundTrips() throws {
        var configuration = IconConfigurationV1.classic
        configuration.appearance.center.effectiveSymbolScale = 4.25
        let encoded = try JSONEncoder().encode(configuration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var appearance = try XCTUnwrap(object["appearance"] as? [String: Any])
        var center = try XCTUnwrap(appearance["center"] as? [String: Any])
        center.removeValue(forKey: "normalizedPercentageScale")
        appearance["center"] = center
        object["appearance"] = appearance
        let oldPayload = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(IconConfigurationV1.self, from: oldPayload)

        XCTAssertNil(decoded.appearance.center.normalizedPercentageScale)
        XCTAssertEqual(decoded.appearance.center.effectiveSymbolScale, 4.25)
        XCTAssertEqual(decoded.normalized().appearance.center.effectiveSymbolScale, 4.25)
    }

    func testBatteryDigitsEightEightyAndOneHundredStayVisibleAcrossSharedSizeRange() throws {
        for commonScale in [1.0, 1.4, 1.8] {
            var configuration = IconConfigurationV1.classic
            IconDesignerEditingModel.settingCommonPercentageScale(commonScale, in: &configuration)
            let appearance = configuration.normalized().appearance

            for value in ["8", "80", "100"] {
                let scene = IconPaletteResolver.apply(
                    IconSceneState(center: .text(IconTextState(text: value, color: .primary, scale: 1))),
                    appearance: appearance,
                    centerSource: .systemBatteryPercentage
                )
                let menuImage = try XCTUnwrap(StatusIconRenderer.render(
                    scene: scene,
                    environment: StatusIconRenderEnvironment(
                        size: 120,
                        scale: 2,
                        foreground: CGColor(gray: 1, alpha: 1),
                        criticalColor: StatusIconRenderer.defaultCriticalColor
                    )
                ))
                let previewImage = try XCTUnwrap(StatusIconRenderer.render(
                    scene: scene,
                    environment: StatusIconRenderEnvironment(
                        size: 240,
                        scale: 1,
                        foreground: CGColor(gray: 1, alpha: 1),
                        criticalColor: StatusIconRenderer.defaultCriticalColor
                    )
                ))
                let dockImage = try XCTUnwrap(DockIconRenderer.image(scene: scene, pixelLength: 512))
                let dockCGImage = try XCTUnwrap((dockImage.representations.first as? NSBitmapImageRep)?.cgImage)

                XCTAssertGreaterThan(try visibleInkBounds(menuImage).width, 0, "menu text \(value) at \(commonScale)")
                XCTAssertGreaterThan(try visibleInkBounds(previewImage).width, 0, "preview text \(value) at \(commonScale)")
                XCTAssertGreaterThan(try visibleInkBounds(dockCGImage, whiteOnly: true).width, 0,
                                     "Dock text \(value) at \(commonScale)")
            }
        }
    }

    func testLegacyEffectiveCenterScaleIsUnchangedUntilCommonScaleIsExplicitlyEdited() throws {
        var configuration = IconConfigurationV1.classic
        configuration.appearance.center.effectiveSymbolScale = 2.4
        let normalized = configuration.normalized()
        XCTAssertNil(normalized.appearance.center.normalizedPercentageScale)
        XCTAssertEqual(normalized.appearance.center.effectiveSymbolScale, 2.4)

        let appearance = normalized.appearance
        let textScene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: appearance,
            centerSource: .systemBatteryPercentage
        )
        let wifiScene = IconPaletteResolver.apply(
            IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary,
                scale: 1
            ))),
            appearance: appearance,
            centerSource: .network
        )
        XCTAssertEqual(try centerTextScale(in: textScene), 2.4, accuracy: 1e-12)
        XCTAssertEqual(try centerSymbolScale(in: wifiScene), 2.4, accuracy: 1e-12)

        IconDesignerEditingModel.settingCommonPercentageScale(1.1, in: &configuration)
        XCTAssertEqual(configuration.appearance.center.effectiveSymbolScale, 2.4,
                       "An explicit edit preserves the historical scale payload.")
        XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, 1.1)
        XCTAssertNil(configuration.appearance.center.normalizedPercentageScale)
    }

    func testExplicitWiFiSizeMatchesLegacyAt100And180OnMenuBarAndDock() throws {
        for percentage in [1.0, 1.8] {
            let legacyScene = IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary,
                scale: percentage
            )))
            let normalizedScene = IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary,
                scale: 1,
                normalizedSizePercentage: percentage
            )))
            let legacyMenu = try XCTUnwrap(StatusIconRenderer.render(scene: legacyScene, environment: menuEnvironment))
            let normalizedMenu = try XCTUnwrap(StatusIconRenderer.render(scene: normalizedScene, environment: menuEnvironment))
            let legacyDock = try dockCGImage(for: legacyScene)
            let normalizedDock = try dockCGImage(for: normalizedScene)
            let legacyMenuHeight = try alphaThreshold128Height(legacyMenu)
            let normalizedMenuHeight = try alphaThreshold128Height(normalizedMenu)
            let legacyDockHeight = try dockCoverageHeight(legacyDock, minimumCoverage: 0.5)
            let normalizedDockHeight = try dockCoverageHeight(normalizedDock, minimumCoverage: 0.5)
            let legacyDockOpaqueHeight = try fullyOpaqueWhiteDockHeight(legacyDock)
            let normalizedDockOpaqueHeight = try fullyOpaqueWhiteDockHeight(normalizedDock)
            XCTAssertEqual(normalizedMenuHeight, legacyMenuHeight, accuracy: 2,
                           "explicit normalized Wi-Fi at \(Int(percentage * 100))% must retain legacy menu-bar ink size")
            XCTAssertEqual(normalizedDockHeight, legacyDockHeight, accuracy: 2,
                           "explicit normalized Wi-Fi at \(Int(percentage * 100))% must retain legacy Dock ink size at half coverage")
            print("WIFI_DOCK_EDGE_PARITY percentage=\(percentage) halfCoverage old=\(legacyDockHeight) new=\(normalizedDockHeight) fullyOpaque240 old=\(legacyDockOpaqueHeight) new=\(normalizedDockOpaqueHeight)")
        }
    }

    private var menuEnvironment: StatusIconRenderEnvironment {
        StatusIconRenderEnvironment(
            size: 120,
            scale: 4,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
    }

    private func dockCGImage(for scene: IconSceneState) throws -> CGImage {
        let dock = try XCTUnwrap(DockIconRenderer.image(scene: scene, pixelLength: 512))
        return try XCTUnwrap((dock.representations.first as? NSBitmapImageRep)?.cgImage)
    }

    func testHundredPercentBatteryTextAndWiFiVisibleInkHeightsMatchOnAllIconSurfaces() throws {
        var configuration = IconConfigurationV1.classic
        IconDesignerEditingModel.settingCommonPercentageScale(1, in: &configuration)
        let appearance = configuration.normalized().appearance
        let textScene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: appearance,
            centerSource: .systemBatteryPercentage
        )
        let wifiScene = IconPaletteResolver.apply(
            IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary,
                scale: 1
            ))),
            appearance: appearance,
            centerSource: .network
        )

        var legacyMaximumConfiguration = IconConfigurationV1.classic
        legacyMaximumConfiguration.appearance.center.normalizedSizePercentage = nil
        legacyMaximumConfiguration.appearance.center.normalizedPercentageScale = nil
        legacyMaximumConfiguration.appearance.center.effectiveSymbolScale = 1.25
        let legacyMaximumTextScene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: legacyMaximumConfiguration.normalized().appearance,
            centerSource: .systemBatteryPercentage
        )
        XCTAssertNil(legacyMaximumTextScene.center?.normalizedSizePercentageValue,
                     "Historical raster comparison must exercise the nil-marker renderer path")
        let legacyMaximumReference = IconSceneState(center: .text(
            IconTextState(text: "100", color: .primary, scale: 1.25)
        ))
        let legacyEnvironment = StatusIconRenderEnvironment(
            size: StatusIconGeometry.canvas.width, scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let legacyMaximumImage = try XCTUnwrap(StatusIconRenderer.render(
            scene: legacyMaximumTextScene, environment: legacyEnvironment
        ))
        let legacyMaximumReferenceImage = try XCTUnwrap(StatusIconRenderer.render(
            scene: legacyMaximumReference, environment: legacyEnvironment
        ))
        XCTAssertEqual(try PixelBuffer(image: legacyMaximumImage).bytes,
                       try PixelBuffer(image: legacyMaximumReferenceImage).bytes,
                       "Legacy nil-size 125% text raster must remain byte-identical to its saved raw scale")

        let normalized125Scene = IconPaletteResolver.apply(
            IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1))),
            appearance: { () -> IconAppearanceConfiguration in
                var value = IconConfigurationV1.classic
                IconDesignerEditingModel.settingCommonPercentageScale(1.25, in: &value)
                return value.normalized().appearance
            }(), centerSource: .systemBatteryPercentage
        )
        let normalized125Image = try XCTUnwrap(StatusIconRenderer.render(
            scene: normalized125Scene, environment: legacyEnvironment
        ))
        let normalized100Image = try XCTUnwrap(StatusIconRenderer.render(
            scene: textScene, environment: legacyEnvironment
        ))
        let normalized100Width = try visibleInkBounds(normalized100Image).width
        let normalized125Width = try visibleInkBounds(normalized125Image).width
        XCTAssertGreaterThanOrEqual(normalized125Width, normalized100Width * 1.23,
                                    "Explicit 125% sizing must preserve text aspect ratio without hidden width clamping")

        let menuEnvironment = StatusIconRenderEnvironment(
            size: 120,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let menuTextHeight = try visibleInkHeight(try XCTUnwrap(StatusIconRenderer.render(scene: textScene, environment: menuEnvironment)))
        let menuWiFiHeight = try visibleInkHeight(try XCTUnwrap(StatusIconRenderer.render(scene: wifiScene, environment: menuEnvironment)))
        XCTAssertEqual(menuTextHeight, menuWiFiHeight, accuracy: 2, "menu-bar visible ink")

        let previewTextHeight = try visibleInkHeight(try XCTUnwrap(StatusIconRenderer.render(
            scene: textScene,
            environment: StatusIconRenderEnvironment(
                size: 240,
                scale: 1,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        )))
        let previewWiFiHeight = try visibleInkHeight(try XCTUnwrap(StatusIconRenderer.render(
            scene: wifiScene,
            environment: StatusIconRenderEnvironment(
                size: 240,
                scale: 1,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        )))
        XCTAssertEqual(previewTextHeight, previewWiFiHeight, accuracy: 2, "designer preview visible ink")

        let dockTextImage = try XCTUnwrap(DockIconRenderer.image(scene: textScene, pixelLength: 512))
        let dockWiFiImage = try XCTUnwrap(DockIconRenderer.image(scene: wifiScene, pixelLength: 512))
        let dockTextCGImage = try XCTUnwrap((dockTextImage.representations.first as? NSBitmapImageRep)?.cgImage)
        let dockWiFiCGImage = try XCTUnwrap((dockWiFiImage.representations.first as? NSBitmapImageRep)?.cgImage)
        XCTAssertEqual(try visibleInkHeight(dockTextCGImage, whiteOnly: true),
                       try visibleInkHeight(dockWiFiCGImage, whiteOnly: true),
                       accuracy: 3, "Dock visible ink")
    }

    func testCenterSliderRangeProjectionDoesNotRewriteHistoricalEffectiveScale() {
        var configuration = IconConfigurationV1.classic
        configuration.appearance.center.effectiveSymbolScale = 4.25

        let sliderValue = IconDesignerEditingModel.commonPercentageScaleSliderValue(
            for: IconDesignerEditingModel.effectiveCenterScale(in: configuration)
        )

        XCTAssertEqual(sliderValue, 1.8)
        XCTAssertEqual(configuration.appearance.center.effectiveSymbolScale, 4.25)
    }

    func testCenterBatteryScaleEditUsesSharedResolverForPreviewAndUndoRestoresScales() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerCenterBatteryScale.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration { configuration in
            configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
            configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
            configuration.behaviors.systemBatteryRing.textScale = 1.65
            configuration.appearance.center.symbolScale = 2.52
            configuration.appearance.center.effectiveSymbolScale = 1.6
        }
        let editor = IconDesignerEditorModel(store: store)
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(rawPercentage: 62, isPresent: true, isCharging: true,
                                           isLowPowerMode: false, isConnectedToPower: true),
                    wifi: .placeholder,
                    volume: .placeholder
                ),
                audioIcon: nil
            ),
            sources: .empty
        )

        let ringScaleBefore = store.iconConfiguration.behaviors.systemBatteryRing.textScale
        let before = IconCompositionResolver.resolve(inputs: inputs, configuration: store.iconConfiguration).scene
        let beforePreview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: store.iconConfiguration).scene
        XCTAssertEqual(before, beforePreview)
        XCTAssertEqual(try centerTextScale(in: before), 1.6, accuracy: 1e-12)
        XCTAssertEqual(try chargingAccessoryScale(in: before), ringScaleBefore, accuracy: 1e-12)

        editor.updateIconConfiguration(coalescingKey: "behavior.centerBatteryTextScale") {
            IconDesignerEditingModel.settingCommonPercentageScale(1.2, in: &$0)
        }
        let editedConfiguration = store.iconConfiguration
        let edited = IconCompositionResolver.resolve(inputs: inputs, configuration: editedConfiguration).scene
        let editedPreview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: editedConfiguration).scene
        XCTAssertEqual(edited, editedPreview)
        XCTAssertEqual(
            edited.center?.normalizedSizePercentageValue,
            1.2
        )
        XCTAssertEqual(editedConfiguration.appearance.center.normalizedSizePercentage, 1.2)
        XCTAssertEqual(editedConfiguration.appearance.center.effectiveSymbolScale, 1.6)
        XCTAssertEqual(try chargingAccessoryScale(in: edited), ringScaleBefore, accuracy: 1e-12)
        XCTAssertEqual(editedConfiguration.behaviors.systemBatteryRing.textScale, ringScaleBefore)

        editor.undo()
        let restored = store.iconConfiguration
        XCTAssertEqual(restored.appearance.center.effectiveSymbolScale, 1.6)
        XCTAssertNil(restored.appearance.center.normalizedSizePercentage)
        XCTAssertEqual(restored.behaviors.systemBatteryRing.textScale, ringScaleBefore)
        XCTAssertEqual(restored.appearance.center.symbolScale, 2.52)
        let restoredScene = IconCompositionResolver.resolve(inputs: inputs, configuration: restored).scene
        XCTAssertEqual(try centerTextScale(in: restoredScene), 1.6, accuracy: 1e-12)
        XCTAssertEqual(try chargingAccessoryScale(in: restoredScene), ringScaleBefore, accuracy: 1e-12)
    }

    func testFallbackBatteryScaleUsesItsResolverScaleAndUndoRestoresFallbackScene() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerCenterBatteryScaleFallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration { configuration in
            configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
            configuration.composition.center = SlotSelection(primary: .network, fallback: .systemBatteryPercentage)
            configuration.behaviors.systemBatteryRing.textScale = 1.65
            configuration.appearance.center.symbolScale = 2.52
            configuration.appearance.center.effectiveSymbolScale = nil
        }
        let editor = IconDesignerEditorModel(store: store)
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(rawPercentage: 62, isPresent: true, isCharging: true,
                                           isLowPowerMode: false, isConnectedToPower: true),
                    wifi: .placeholder,
                    volume: .placeholder
                ),
                audioIcon: nil
            ),
            sources: IconSourceSnapshot(
                availability: [CenterSource.network.rawValue: .unavailable(.disconnected)]
            )
        )
        let appearanceFactor = store.iconConfiguration.appearance.center.symbolScale
            / CenterAppearance.classic.symbolScale
        let expectedFallbackScale = store.iconConfiguration.behaviors.systemBatteryRing.textScale * appearanceFactor
        XCTAssertEqual(
            IconDesignerEditingModel.effectiveCenterScale(for: .systemBatteryPercentage, in: store.iconConfiguration),
            expectedFallbackScale,
            accuracy: 1e-12
        )
        var explicitScaleConfiguration = store.iconConfiguration
        explicitScaleConfiguration.appearance.center.effectiveSymbolScale = 2.2
        XCTAssertEqual(
            IconDesignerEditingModel.effectiveCenterScale(for: .systemBatteryPercentage, in: explicitScaleConfiguration),
            2.2,
            accuracy: 1e-12
        )

        let beforeOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: store.iconConfiguration)
        let beforePreview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: store.iconConfiguration)
        XCTAssertEqual(beforeOutput.trace.center.role, .fallback)
        XCTAssertEqual(beforeOutput.trace.center.selectedSourceID, CenterSource.systemBatteryPercentage.rawValue)
        XCTAssertEqual(beforeOutput.scene, beforePreview.scene)
        XCTAssertEqual(try centerTextScale(in: beforeOutput.scene), expectedFallbackScale, accuracy: 1e-12)
        let outerAccessoryBefore = try chargingAccessoryScale(in: beforeOutput.scene)
        XCTAssertEqual(outerAccessoryBefore, store.iconConfiguration.behaviors.systemBatteryRing.textScale, accuracy: 1e-12)

        editor.updateIconConfiguration(coalescingKey: "behavior.centerBatteryTextScale") {
            IconDesignerEditingModel.settingCommonPercentageScale(1.45, in: &$0)
        }
        XCTAssertEqual(store.iconConfiguration.appearance.center.normalizedSizePercentage, 1.45)
        XCTAssertEqual(store.iconConfiguration.behaviors.systemBatteryRing.textScale, 1.65)
        let editedOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: store.iconConfiguration)
        let editedPreview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: store.iconConfiguration)
        XCTAssertEqual(editedOutput.trace.center.role, .fallback)
        XCTAssertEqual(editedOutput.scene, editedPreview.scene)
        XCTAssertEqual(editedOutput.scene.center?.normalizedSizePercentageValue, 1.45)
        XCTAssertEqual(try chargingAccessoryScale(in: editedOutput.scene), outerAccessoryBefore, accuracy: 1e-12)

        editor.undo()
        XCTAssertNil(store.iconConfiguration.appearance.center.effectiveSymbolScale)
        XCTAssertNil(store.iconConfiguration.appearance.center.normalizedSizePercentage)
        XCTAssertEqual(store.iconConfiguration.behaviors.systemBatteryRing.textScale, 1.65)
        let restoredOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: store.iconConfiguration)
        let restoredPreview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: store.iconConfiguration)
        XCTAssertEqual(restoredOutput.trace.center.role, .fallback)
        XCTAssertEqual(restoredOutput.scene, restoredPreview.scene)
        XCTAssertEqual(try centerTextScale(in: restoredOutput.scene), expectedFallbackScale, accuracy: 1e-12)
        XCTAssertEqual(try chargingAccessoryScale(in: restoredOutput.scene), outerAccessoryBefore, accuracy: 1e-12)
    }

    func testLegacyCenterScaleDoesNotRecurseForAutomaticLegacyOrNone() {
        for source: CenterSource in [.automaticLegacy, .none] {
            var configuration = IconConfigurationV1.classic
            configuration.composition.center = SlotSelection(primary: source)
            configuration.appearance.center.effectiveSymbolScale = nil
            configuration.appearance.center.symbolScale = 1.5
            let expected = 1.5 / CenterAppearance.classic.symbolScale

            XCTAssertEqual(IconDesignerEditingModel.effectiveCenterScale(for: source, in: configuration), expected,
                           accuracy: 1e-12, "source \(source)")
            XCTAssertEqual(IconDesignerEditingModel.effectiveCenterScale(in: configuration), expected,
                           accuracy: 1e-12, "selected source \(source)")
        }
    }

    func testLegacyBatteryPercentageUsesInverseCommonSizeCalibration() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        configuration.appearance.center.effectiveSymbolScale = nil
        configuration.appearance.center.normalizedPercentageScale = nil
        configuration.appearance.center.symbolScale = CenterAppearance.classic.symbolScale
        configuration.behaviors.systemBatteryRing.textScale = 1.4

        XCTAssertEqual(
            IconDesignerEditingModel.commonPercentageScale(for: .systemBatteryPercentage, in: configuration),
            1.4 / CenterPercentageScaleCalibration.percentageScaleForCommonSize,
            accuracy: 1e-12
        )
    }

    func testFallbackAndPrimaryShareTheSameExplicitCenterSize() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        IconDesignerEditingModel.settingCommonPercentageScale(1.35, in: &configuration)
        XCTAssertEqual(IconDesignerEditingModel.commonPercentageScale(in: configuration), 1.35)
        XCTAssertEqual(configuration.appearance.center.normalizedSizePercentage, 1.35)
    }

    func testCenterSizeControlUsesOnePercentageLabelForEverySource() throws {
        let source = try String(contentsOf: sourceURL("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconAppearanceEditor.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("IconDesignerEditingModel.commonPercentageScaleLabel(for: scale)"))
        XCTAssertFalse(source.contains("%.2f×"))
        XCTAssertFalse(source.contains("commonPercentageSource =="))
    }

    private func centerTextScale(in scene: IconSceneState) throws -> Double {
        guard case let .text(text)? = scene.center else { throw TestFailure.expectedCenterText }
        return text.scale
    }

    private func chargingAccessoryScale(in scene: IconSceneState) throws -> Double {
        guard case let .symbol(symbol)? = scene.outerRing?.accessory else {
            throw TestFailure.expectedChargingSymbol
        }
        return symbol.scale
    }

    private func centerSymbolScale(in scene: IconSceneState) throws -> Double {
        guard case let .symbol(symbol)? = scene.center else { throw TestFailure.expectedCenterSymbol }
        return symbol.scale
    }

    private func alphaThreshold128Height(_ image: CGImage) throws -> CGFloat {
        let pixels = try PixelBuffer(image: image)
        var minY = pixels.height
        var maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let pixel = pixels.rgba(x: x, y: y)
                if pixel.alpha >= 128 {
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxY >= minY else { throw TestFailure.expectedVisibleInk }
        return CGFloat(maxY - minY + 1)
    }

    /// Recovers foreground coverage from the known dark Dock body's RGB value.
    /// The glyph is opaque white over an opaque body, so linear channel distance
    /// from the body to white is the composited coverage for the alpha edge.
    private func dockCoverageHeight(_ image: CGImage, minimumCoverage: CGFloat) throws -> CGFloat {
        let pixels = try PixelBuffer(image: image)
        let backgroundRed: CGFloat = 21
        let threshold = backgroundRed + minimumCoverage * (255 - backgroundRed)
        var minY = pixels.height
        var maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where CGFloat(pixels.rgba(x: x, y: y).red) >= threshold {
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxY >= minY else { throw TestFailure.expectedVisibleInk }
        return CGFloat(maxY - minY + 1)
    }

    /// Retains the original RGB >= 240 edge measurement as a separate opaque-ink
    /// diagnostic; it is not a half-coverage alpha threshold.
    private func fullyOpaqueWhiteDockHeight(_ image: CGImage) throws -> CGFloat {
        try visibleInkBounds(image, whiteOnly: true).height
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
                let isInk = whiteOnly
                    ? pixel.red >= 240 && pixel.green >= 240 && pixel.blue >= 240
                    : pixel.alpha >= 32
                if isInk {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxY >= minY, maxX >= minX else { throw TestFailure.expectedVisibleInk }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    private enum TestFailure: Error {
        case expectedCenterText
        case expectedChargingSymbol
        case expectedCenterSymbol
        case expectedVisibleInk
    }
}
