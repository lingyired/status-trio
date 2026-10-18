import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconSceneRendererParityTests: XCTestCase {
    func testAirPodsDualRingFromResolvedSceneReachesMenuBarAndDock() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: makeSnapshot(), audioIcon: nil),
            sources: IconSourceSnapshot(
                availability: ["airPodsBattery": .available],
                airPodsBattery: AirPodsBatteryIconSnapshot(
                    deviceAddress: "AA:BB:CC:DD:EE:FF", model: .airPodsPro,
                    main: 70, left: 73, right: 68, caseLevel: 80, observedAt: now
                )
            )
        )
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery)
        configuration.behaviors.showsAirPodsTopSymbol = true
        let dualScene = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now).scene
        XCTAssertEqual(dualScene.outerRing?.segments.count, 2)
        XCTAssertNotNil(dualScene.outerRing?.accessory)
        configuration.behaviors.airPodsRing = .single
        let singleScene = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now).scene

        let foreground = CGColor(gray: 1, alpha: 1)
        let dualMenu = try menuBarPixels(scene: dualScene, foreground: foreground, size: 28, scale: 2)
        let singleMenu = try menuBarPixels(scene: singleScene, foreground: foreground, size: 28, scale: 2)
        XCTAssertFalse(dualMenu.bytes.elementsEqual(singleMenu.bytes), "Menu bar must render the resolved dual scene.")
        let dualDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: dualScene, backgroundStyle: .dark, pixelLength: 256
        )))
        let singleDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: singleScene, backgroundStyle: .dark, pixelLength: 256
        )))
        XCTAssertFalse(dualDock.bytes.elementsEqual(singleDock.bytes), "Dock must render the same resolved dual scene.")
    }

    func testLayeredAirPodsRingKeepsTopMarkerInItsOwnTemplateRegion() throws {
        let blue = IconColorRole.custom(IconRGBA(red: 0, green: 0, blue: 1, alpha: 1))
        let scene = IconSceneState(outerRing: OuterRingState(
            segments: [
                RingSegmentState(progress: 1, color: blue, position: .left),
                RingSegmentState(progress: 1, color: blue, position: .right)
            ],
            gap: .closed,
            layout: .leftRight,
            accessory: .symbol(IconSymbolState(
                source: .symbol(name: "airpods", variableValue: nil, fallback: "headphones"),
                color: .primary,
                scale: 1.8
            ))
        ))
        XCTAssertEqual(scene.chromaticRegions, [.ringFill])
        XCTAssertTrue(scene.templateRegions.contains(.ringAccessory))

        let environment = StatusIconRenderEnvironment(
            size: 120,
            scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let whole = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment))
        let template = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene, environment: environment, regions: scene.templateRegions
        ))
        let chromatic = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene, environment: environment, regions: scene.chromaticRegions
        ))
        let accessory = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene, environment: environment, regions: .ringAccessory
        ))

        let wholePixels = try PixelBuffer(image: whole)
        let templatePixels = try PixelBuffer(image: template)
        let chromaticPixels = try PixelBuffer(image: chromatic)
        let accessoryPixels = try PixelBuffer(image: accessory)
        let layered = try composite(base: template, overlay: chromatic, environment: environment)
        XCTAssertLessThanOrEqual(
            maximumChannelDelta(try PixelBuffer(image: layered).bytes, wholePixels.bytes),
            1,
            "The template and blue AirPods ring overlay must reproduce the one-pass render."
        )
        XCTAssertGreaterThan(
            accessoryPixels.alphaSum(inSVGRect: CGRect(x: 43, y: 2, width: 34, height: 34), size: 120, scale: 1),
            0,
            "The ringAccessory region must draw the top marker."
        )
        XCTAssertEqual(
            accessoryPixels.alphaSum(inSVGRect: StatusIconGeometry.canvas, size: 120, scale: 1),
            accessoryPixels.alphaSum(inSVGRect: CGRect(x: 43, y: 2, width: 34, height: 34), size: 120, scale: 1),
            "The ringAccessory region must not redraw either ring layer."
        )
        XCTAssertGreaterThan(
            chromaticPixels.alphaSum(inSVGRect: CGRect(x: 18, y: 15, width: 84, height: 78), size: 120, scale: 1),
            0,
            "Both blue progress arcs must remain in the chromatic overlay."
        )
        XCTAssertGreaterThan(
            templatePixels.alphaSum(inSVGRect: CGRect(x: 43, y: 2, width: 34, height: 34), size: 120, scale: 1),
            0,
            "The monochrome AirPods marker must remain in the re-tintable template."
        )
    }

    func testDualRingTopAccessoryChangesRealTopGapPixelsInMenuBarAndDock() throws {
        let segments = [
            RingSegmentState(progress: 0.73, color: .bluetooth, position: .left),
            RingSegmentState(progress: 0.68, color: .primary, position: .right)
        ]
        let symbol = RingAccessoryState.symbol(IconSymbolState(
            source: .symbol(name: "airpods", variableValue: nil, fallback: "headphones"),
            color: .primary,
            scale: 1.8
        ))
        let withoutAccessory = IconSceneState(outerRing: OuterRingState(
            segments: segments, gap: .closed, layout: .leftRight
        ))
        let withAccessory = IconSceneState(outerRing: OuterRingState(
            segments: segments, gap: .closed, layout: .leftRight, accessory: symbol
        ))
        let foreground = CGColor(gray: 1, alpha: 1)

        let plainMenu = try menuBarPixels(scene: withoutAccessory, foreground: foreground, size: 28, scale: 2)
        let markedMenu = try menuBarPixels(scene: withAccessory, foreground: foreground, size: 28, scale: 2)
        let menuAccessoryPixels = changedPixels(
            plainMenu, markedMenu, inSVGRect: CGRect(x: 43, y: 2, width: 34, height: 34), size: 28, scale: 2
        )
        let allMenuDifferences = changedPixels(
            plainMenu, markedMenu, inSVGRect: StatusIconGeometry.canvas, size: 28, scale: 2
        )
        XCTAssertGreaterThan(menuAccessoryPixels.count, 0,
                             "A scene accessory must draw visible ink in the existing top-gap region.")
        XCTAssertTrue(allMenuDifferences.allSatisfy {
            $0.x > 0 && $0.y > 0 && $0.x < markedMenu.width - 1 && $0.y < markedMenu.height - 1
        }, "The top glyph must remain fully inside the menu-bar canvas.")

        let plainDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: withoutAccessory, backgroundStyle: .dark, pixelLength: 256
        )))
        let markedDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: withAccessory, backgroundStyle: .dark, pixelLength: 256
        )))
        let dockAccessoryPixels = changedPixels(
            plainDock, markedDock, inSVGRect: CGRect(x: 43, y: 2, width: 34, height: 34), size: 120, scale: 256.0 / 120.0
        )
        let allDockDifferences = changedPixels(
            plainDock, markedDock, inSVGRect: StatusIconGeometry.canvas, size: 120, scale: 256.0 / 120.0
        )
        XCTAssertGreaterThan(dockAccessoryPixels.count, 0,
                             "Dock must render the same scene accessory in the top-gap region.")
        XCTAssertTrue(allDockDifferences.allSatisfy {
            $0.x > 0 && $0.y > 0 && $0.x < markedDock.width - 1 && $0.y < markedDock.height - 1
        }, "The top glyph must remain fully inside the Dock canvas.")
    }

    func testSharedAirPodsTopGapChangesMenuBarAndDockTrackPixelsAroundTopMarker() throws {
        let leftColor = IconColorRole.custom(IconRGBA(red: 0, green: 0, blue: 1, alpha: 1))
        let rightColor = IconColorRole.custom(IconRGBA(red: 1, green: 0, blue: 0, alpha: 1))
        let left = RingSegmentState(progress: 1, color: leftColor, position: .left)
        let right = RingSegmentState(progress: 1, color: rightColor, position: .right)
        let legacy = IconSceneState(outerRing: OuterRingState(
            segments: [left, right], gap: .closed, layout: .leftRight
        ))
        let marked = IconSceneState(outerRing: OuterRingState(
            segments: [left, right], gap: .closed, layout: .leftRight,
            accessory: .symbol(IconSymbolState(
                source: .symbol(name: "airpods", variableValue: nil, fallback: "headphones"),
                color: .primary, scale: 1.8
            ))
        ))
        let foreground = CGColor(gray: 1, alpha: 1)
        let legacyMenu = try menuBarPixels(scene: legacy, foreground: foreground, size: 28, scale: 2)
        let markedMenu = try menuBarPixels(scene: marked, foreground: foreground, size: 28, scale: 2)
        let menuGapFlanks = [CGRect(x: 40, y: 4, width: 10, height: 21),
                             CGRect(x: 69, y: 4, width: 10, height: 21)]
        XCTAssertGreaterThan(menuGapFlanks.reduce(0) { total, region in
            total + changedPixelCount(legacyMenu, markedMenu, inSVGRect: region, size: 28, scale: 2)
        }, 0, "Accessory mode must widen the track cutout outside the glyph ink on the menu bar.")
        let markerRegion = scaledPixelRect(
            CGRect(x: 47, y: 3, width: 25, height: 21), size: 28, scale: 2
        )
        XCTAssertFalse(containsColor(markedMenu, inPixelRect: markerRegion,
                                      red: 0, green: 0, blue: 1, tolerance: 0.1),
                        "Left ring ink must not overlap the AirPods glyph area.")
        XCTAssertFalse(containsColor(markedMenu, inPixelRect: markerRegion,
                                      red: 1, green: 0, blue: 0, tolerance: 0.1),
                        "Right ring ink must not overlap the AirPods glyph area.")

        let legacyDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: legacy, backgroundStyle: .dark, pixelLength: 256
        )))
        let markedDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: marked, backgroundStyle: .dark, pixelLength: 256
        )))
        XCTAssertGreaterThan(menuGapFlanks.reduce(0) { total, region in
            total + changedPixelCount(legacyDock, markedDock, inSVGRect: region, size: 120,
                                      scale: 256.0 / 120.0)
        }, 0, "Accessory mode must widen the same Dock track cutout outside the glyph ink.")
        let dockMarkerRegion = scaledPixelRect(
            CGRect(x: 47, y: 3, width: 25, height: 21), size: 120, scale: 256.0 / 120.0
        )
        XCTAssertFalse(containsColor(markedDock, inPixelRect: dockMarkerRegion,
                                      red: 0, green: 0, blue: 1, tolerance: 0.1),
                        "Dock left ring ink must not overlap the AirPods glyph area.")
        XCTAssertFalse(containsColor(markedDock, inPixelRect: dockMarkerRegion,
                                      red: 1, green: 0, blue: 0, tolerance: 0.1),
                        "Dock right ring ink must not overlap the AirPods glyph area.")
    }

    func testAirPodsMacBatteryFallbackUsesOneResolvedSceneForMenuBarAndDock() throws {
        let snapshot = makeSnapshot(battery: battery(percentage: 52))
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            sources: IconSourceSnapshot(availability: [
                "airPodsBattery": .unavailable(.disconnected),
                "systemBattery": .available
            ])
        )
        var fallbackConfiguration = IconDesignerDefaults.configuration()
        fallbackConfiguration.behaviors.showsAirPodsTopSymbol = true
        fallbackConfiguration.composition.outerRing = SlotSelection(
            primary: .airPodsBattery, fallback: .systemBattery
        )
        let fallbackOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: fallbackConfiguration)
        XCTAssertEqual(fallbackOutput.trace.outerRing.selectedSourceID, RingSource.systemBattery.rawValue)

        var directConfiguration = fallbackConfiguration
        directConfiguration.composition.outerRing = SlotSelection(primary: .systemBattery)
        let directScene = IconCompositionResolver.resolve(inputs: inputs, configuration: directConfiguration).scene
        XCTAssertEqual(fallbackOutput.scene, directScene)

        let foreground = CGColor(gray: 1, alpha: 1)
        let fallbackMenu = try menuBarPixels(scene: fallbackOutput.scene, foreground: foreground, size: 28, scale: 2)
        let directMenu = try menuBarPixels(scene: directScene, foreground: foreground, size: 28, scale: 2)
        XCTAssertTrue(fallbackMenu.bytes.elementsEqual(directMenu.bytes))
        let fallbackDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: fallbackOutput.scene, backgroundStyle: .dark, pixelLength: 256
        )))
        let directDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: directScene, backgroundStyle: .dark, pixelLength: 256
        )))
        XCTAssertTrue(fallbackDock.bytes.elementsEqual(directDock.bytes))
    }

    func testUnifiedCenterSizePercentageChangesMenuBarAndDockRenderedPixels() throws {
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: makeSnapshot(wifi: WiFiStatus(state: .connected, rssi: -54), connection: .wifi),
                audioIcon: nil
            ),
            sources: .empty
        )
        var configuration = IconDesignerDefaults.configuration()
        configuration.appearance.center.normalizedSizePercentage = 1.0
        let small = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration).scene
        configuration.appearance.center.normalizedSizePercentage = 1.8
        let large = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration).scene
        XCTAssertNotEqual(small.center, large.center)

        let foreground = CGColor(gray: 1, alpha: 1)
        let smallMenu = try menuBarPixels(scene: small, foreground: foreground, size: 28, scale: 2)
        let largeMenu = try menuBarPixels(scene: large, foreground: foreground, size: 28, scale: 2)
        XCTAssertFalse(smallMenu.bytes.elementsEqual(largeMenu.bytes))

        let smallDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(scene: small, backgroundStyle: .dark, pixelLength: 256)))
        let largeDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(scene: large, backgroundStyle: .dark, pixelLength: 256)))
        XCTAssertFalse(smallDock.bytes.elementsEqual(largeDock.bytes))
    }

    func testCenterSemanticColorOverrideReachesMenuBarAndDockRenderers() throws {
        let snapshot = PresentationFixtures.snapshot(rssi: -55)
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center.primary = .network
        let accent = IconRGBA(red: 1, green: 0.05, blue: 0.35, alpha: 1)
        configuration.appearance.center.color = .semanticOverrides([.primary: accent])
        let scene = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: .empty
            ),
            configuration: configuration
        ).scene

        guard case let .symbol(center)? = scene.center else {
            XCTFail("Expected a network symbol")
            return
        }
        XCTAssertEqual(center.color, .custom(accent))

        var automaticConfiguration = configuration
        automaticConfiguration.appearance.center.color = .automatic
        let automaticScene = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: .empty
            ),
            configuration: automaticConfiguration
        ).scene

        let menu = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        let automaticMenu = try menuBarPixels(scene: automaticScene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        XCTAssertNotEqual(menu.bytes, automaticMenu.bytes, "Menu bar rendering must use the configured semantic override")
        for background in DockIconBackgroundStyle.allCases {
            let dock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                scene: scene, backgroundStyle: background, pixelLength: 96
            )))
            let automaticDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                scene: automaticScene, backgroundStyle: background, pixelLength: 96
            )))
            XCTAssertNotEqual(dock.bytes, automaticDock.bytes, "Dock (\(background)) must use the configured semantic override")
        }
    }

    func testInputSourceShortLabelUsesTheFixedCenterSlotOnBothSurfaces() throws {
        let descriptor = InputSourceDescriptor(
            id: "com.status-trio.preview.input-source",
            localizedName: "拼音",
            primaryLanguage: nil,
            iconURL: nil,
            shortLabel: "拼"
        )
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: makeSnapshot(wifi: WiFiStatus(state: .connected, rssi: -60), connection: .wifi),
                audioIcon: nil,
                inputSource: descriptor
            ),
            sources: .empty
        )
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.center = SlotSelection(primary: .inputSource)
        configuration.composition.footer = SlotSelection(primary: .none)
        let scene = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration).scene

        guard case let .text(center)? = scene.center else {
            return XCTFail("The selected input source should draw its short label")
        }
        XCTAssertEqual(center.text, "拼")

        let centerSlot = CGRect(x: 37, y: 48, width: 45, height: 43)
        let menu = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        XCTAssertGreaterThan(
            menu.alphaSum(inSVGRect: centerSlot, size: 28, scale: 2),
            100,
            "The input-source label must leave measurable ink in the fixed menu-bar centre slot"
        )
        for style in [DockIconBackgroundStyle.dark, .light] {
            let dock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                scene: scene, backgroundStyle: style, pixelLength: 96
            )))
            XCTAssertGreaterThan(
                alphaSum(dock, inPixelRect: CGRect(x: 34, y: 33, width: 34, height: 32)),
                100,
                "The input-source label must draw in the Dock centre slot: \(style)"
            )
        }
    }

    func testGlobalNetworkOverrideChangesOnlyTheCenterSlotAndRecoversOnBothSurfaces() throws {
        let snapshot = makeSnapshot(
            battery: battery(percentage: 68),
            wifi: WiFiStatus(state: .noInternet, rssi: -50),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            sources: .empty
        )
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .none)
        configuration.composition.footer = SlotSelection(primary: .systemVolume)
        let baseScene = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration).scene
        XCTAssertNil(baseScene.center, "A none centre stays empty while the global rule is off")

        var overrideConfiguration = configuration
        overrideConfiguration.composition.centerOverride.networkProblemOverridesPrimary = true
        let overrideOutput = IconCompositionResolver.resolve(inputs: inputs, configuration: overrideConfiguration)
        XCTAssertEqual(overrideOutput.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(overrideOutput.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertNotNil(overrideOutput.scene.center, "A down network must fill a none centre when the rule is on")

        // A left strip of the battery ring that never overlaps the centre slot
        // (x 37...82), so the assertion proves the rule is centre-local.
        let ringRegion = CGRect(x: 0, y: 0, width: 36, height: 100)
        let footerRegion = CGRect(x: 25, y: 98, width: 70, height: 22)
        let foreground = CGColor(gray: 1, alpha: 1)
        let baseMenu = try menuBarPixels(scene: baseScene, foreground: foreground, size: 28, scale: 2)
        let overrideMenu = try menuBarPixels(scene: overrideOutput.scene, foreground: foreground, size: 28, scale: 2)
        XCTAssertFalse(
            pixelsDiffer(baseMenu, overrideMenu, inSVGRect: ringRegion, size: 28, scale: 2),
            "The global network rule must not change the outer-ring pixels"
        )
        XCTAssertFalse(
            pixelsDiffer(baseMenu, overrideMenu, inSVGRect: footerRegion, size: 28, scale: 2),
            "The global network rule must not change the footer pixels"
        )

        let baseDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: baseScene, backgroundStyle: .dark, pixelLength: 256
        )))
        let overrideDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: overrideOutput.scene, backgroundStyle: .dark, pixelLength: 256
        )))
        XCTAssertFalse(
            baseDock.bytes.elementsEqual(overrideDock.bytes),
            "The Dock icon must redraw when the global rule fills the centre"
        )

        let recovered = StatusSnapshot(
            battery: snapshot.battery,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: snapshot.volume
        )
        let recoveredOutput = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: recovered, audioIcon: nil),
                sources: .empty
            ),
            configuration: overrideConfiguration
        )
        XCTAssertNil(recoveredOutput.scene.center, "A healthy network restores the configured none centre")
        let recoveredMenu = try menuBarPixels(scene: recoveredOutput.scene, foreground: foreground, size: 28, scale: 2)
        XCTAssertTrue(
            recoveredMenu.bytes.elementsEqual(baseMenu.bytes),
            "Recovery must return to the exact pre-override menu-bar pixels"
        )
        let recoveredDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: recoveredOutput.scene, backgroundStyle: .dark, pixelLength: 256
        )))
        XCTAssertTrue(
            recoveredDock.bytes.elementsEqual(baseDock.bytes),
            "Recovery must return to the exact pre-override Dock pixels"
        )
    }

    func testOrdinarySceneKeepsIndependentCanvasAndRegionConventions() throws {
        let scene = mappedScene(for: PresentationFixtures.snapshot())
        for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
            let pixels = try menuBarPixels(scene: scene, foreground: foreground, size: 28, scale: 2)
            assertMenuBarPixelConventions(pixels, size: 28, scale: 2, label: "ordinary")
        }
    }

    func testMigratedWiFiScaleMatchesMenuBarAndDockForConnectedErrorAndEthernet() throws {
        var oldConfiguration = IconConfigurationV1.classic
        oldConfiguration.composition.outerRing.primary = .none
        oldConfiguration.composition.center.primary = .network
        oldConfiguration.composition.footer.primary = .none
        oldConfiguration.behaviors.networkCenter.wifiScale = 2.1
        oldConfiguration.behaviors.networkCenter.showsWiFiIconForEthernet = true
        oldConfiguration.appearance.center.symbolScale = 1.2
        let encoded = try JSONEncoder().encode(oldConfiguration)
        var payloadObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payloadObject.removeValue(forKey: "wifiScaleMigrationVersion")
        let configuration = try IconConfigurationCodec.decode(JSONSerialization.data(withJSONObject: payloadObject))
        let cases: [(String, WiFiStatus, NetworkConnection)] = [
            ("connected", WiFiStatus(state: .connected, rssi: -54), .wifi),
            ("error", WiFiStatus(state: .noInternet, rssi: -54), .wifi),
            ("ethernet", WiFiStatus(state: .off, rssi: nil), .ethernet)
        ]

        for (name, wifi, connection) in cases {
            let inputs = IconResolutionInputs(
                system: IconPresentationInputs(
                    snapshot: makeSnapshot(wifi: wifi, connection: connection), audioIcon: nil
                ),
                sources: .empty
            )
            let resolved = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration).scene
            guard case let .symbol(actualCenter)? = resolved.center else {
                XCTFail("Expected the center Wi-Fi symbol for \(name)")
                continue
            }
            XCTAssertEqual(actualCenter.scale, 1.575, accuracy: 0.001, name)
            let expected = IconSceneState(center: .symbol(IconSymbolState(
                source: actualCenter.source, color: actualCenter.color, scale: 1.575
            )))

            for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
                let actualMenu = try menuBarPixels(scene: resolved, foreground: foreground, size: 28, scale: 2)
                let expectedMenu = try menuBarPixels(scene: expected, foreground: foreground, size: 28, scale: 2)
                XCTAssertTrue(actualMenu.bytes.elementsEqual(expectedMenu.bytes), "menu bar: \(name)")
            }
            for style in DockIconBackgroundStyle.allCases {
                let actualDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                    scene: resolved, backgroundStyle: style, pixelLength: 256
                )))
                let expectedDock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                    scene: expected, backgroundStyle: style, pixelLength: 256
                )))
                XCTAssertTrue(actualDock.bytes.elementsEqual(expectedDock.bytes), "Dock \(style): \(name)")
            }
        }
    }

    func testTaskOneVisualMatrixKeepsFixedGeometryAndDockPaletteConventions() throws {
        for fixture in visualCases() {
            let scene = mappedScene(for: fixture.snapshot, configuration: fixture.configuration)
            XCTAssertEqual(scene, fixture.expectedScene, "literal scene fields: \(fixture.name)")
            for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
                let pixels = try menuBarPixels(scene: scene, foreground: foreground, size: 28, scale: 2)
                assertMenuBarPixelConventions(pixels, size: 28, scale: 2, label: fixture.name)
                let expectedPixels = try menuBarPixels(
                    scene: fixture.expectedScene,
                    foreground: foreground,
                    size: 28,
                    scale: 2
                )
                XCTAssertTrue(
                    pixels.bytes.elementsEqual(expectedPixels.bytes),
                    "independent ring/center/footer reference: \(fixture.name)"
                )
            }
            for style in DockIconBackgroundStyle.allCases {
                let image = try XCTUnwrap(DockIconRenderer.image(scene: scene, backgroundStyle: style, pixelLength: 96))
                let pixels = try cgPixels(from: image)
                let expectedImage = try XCTUnwrap(DockIconRenderer.image(
                    scene: fixture.expectedScene,
                    backgroundStyle: style,
                    pixelLength: 96
                ))
                let expectedPixels = try cgPixels(from: expectedImage)
                XCTAssertEqual(pixels.width, 96, "Dock width: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.height, 96, "Dock height: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.bytes.count, 96 * 96 * 4, "Dock full buffer: \(fixture.name), \(style)")
                XCTAssertTrue(
                    pixels.bytes.elementsEqual(expectedPixels.bytes),
                    "independent ring/center/footer reference: \(fixture.name), \(style)"
                )
                XCTAssertEqual(pixels.rgba(x: 0, y: 0).alpha, 0, "Dock transparent corner: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.rgba(x: 48, y: 2).alpha, 0, "Dock transparent margin: \(fixture.name), \(style)")
                let body = pixels.rgba(x: 12, y: 48)
                switch style {
                case .dark:
                    XCTAssertGreaterThan(body.alpha, 250, "Dock dark body: \(fixture.name)")
                    XCTAssertEqual(body.red, 21, accuracy: 3)
                    XCTAssertEqual(body.green, 21, accuracy: 3)
                    XCTAssertEqual(body.blue, 23, accuracy: 3)
                    XCTAssertTrue(pixels.containsColor(red: 1, green: 1, blue: 1, tolerance: 0.08, minimumAlpha: 0.9), fixture.name)
                case .light:
                    XCTAssertGreaterThan(body.alpha, 250, "Dock light body: \(fixture.name)")
                    XCTAssertGreaterThanOrEqual(body.red, 250)
                    XCTAssertGreaterThanOrEqual(body.green, 250)
                    XCTAssertGreaterThanOrEqual(body.blue, 250)
                    XCTAssertTrue(pixels.containsColor(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0,
                                                       tolerance: 0.08, minimumAlpha: 0.9), fixture.name)
                case .clear:
                    XCTAssertGreaterThan(body.alpha, 80, "Dock clear body: \(fixture.name)")
                    XCTAssertLessThan(body.alpha, 240, "Dock clear body: \(fixture.name)")
                    XCTAssertTrue(pixels.containsColor(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0,
                                                       tolerance: 0.08, minimumAlpha: 0.9), fixture.name)
                }
            }
        }
    }

    func testOrdinarySceneSubstitutionFailsEveryMaterialVisualCategory() throws {
        let fixtures = visualCases()
        let ordinary = try XCTUnwrap(fixtures.first { $0.name == "ordinary" })
        for fixture in fixtures where fixture.name != "ordinary" {
            let actualScene = mappedScene(for: fixture.snapshot, configuration: fixture.configuration)
            for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
                let actual = try menuBarPixels(scene: actualScene, foreground: foreground, size: 28, scale: 2)
                let substitution = try menuBarPixels(
                    scene: ordinary.expectedScene,
                    foreground: foreground,
                    size: 28,
                    scale: 2
                )
                for region in fixture.distinctRegions where !region.isEmpty {
                    XCTAssertTrue(
                        pixelsDiffer(actual, substitution, inSVGRect: region, size: 28, scale: 2),
                        "ordinary menu-bar substitution must fail in \(region) for \(fixture.name)"
                    )
                }
            }
            for style in DockIconBackgroundStyle.allCases {
                let actual = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                    scene: actualScene,
                    backgroundStyle: style,
                    pixelLength: 96
                )))
                let substitution = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                    scene: ordinary.expectedScene,
                    backgroundStyle: style,
                    pixelLength: 96
                )))
                for region in fixture.distinctRegions where !region.isEmpty {
                    XCTAssertTrue(
                        pixelsDiffer(actual, substitution, inDockSVGRect: region, pixelLength: 96),
                        "ordinary Dock substitution must fail in \(region) for \(fixture.name), \(style)"
                    )
                }
            }
        }
    }

    func testAnimationPhasesKeepStaticAndDisabledPixelConventions() throws {
        let active = makeSnapshot(
            battery: battery(percentage: 43, charging: true, connected: true),
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let scene = mappedScene(for: active)
        var frames: [PixelBuffer] = []
        for phase in [
            nil,
            ChargingEffectPhase(step: 18, stepsPerCycle: 36, kind: .steady),
            ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst)
        ] {
            let image = try XCTUnwrap(StatusIconRenderer.render(
                scene: scene,
                environment: StatusIconRenderEnvironment(size: 28, scale: 2,
                                                         foreground: CGColor(gray: 1, alpha: 1),
                                                         criticalColor: StatusIconRenderer.defaultCriticalColor),
                phase: phase
            ))
            frames.append(try PixelBuffer(image: image))
        }
        for (index, frame) in frames.enumerated() {
            assertMenuBarPixelConventions(frame, size: 28, scale: 2, label: "animation phase \(index)")
        }
        XCTAssertNotEqual(frames[0].bytes, frames[1].bytes, "steady phase changes only the animated battery artwork")
        XCTAssertNotEqual(frames[0].bytes, frames[2].bytes, "burst phase changes only the animated battery artwork")

        let charged = mappedScene(for: makeSnapshot(
            battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: true, isCharged: true,
                                   isLowPowerMode: false, isConnectedToPower: true),
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        ))
        let chargedStatic = try menuBarPixels(scene: charged, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        let chargedBurst = try menuBarPixels(
            scene: charged, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2,
            phase: ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst)
        )
        XCTAssertTrue(chargedStatic.bytes == chargedBurst.bytes, "a completed battery has no charging animation")

        let disabled = mappedScene(for: active, configuration: configuration(
            battery: BatteryIconOptions(showsChargingEffect: false)
        ))
        let disabledStatic = try menuBarPixels(scene: disabled, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        let disabledBurst = try menuBarPixels(
            scene: disabled, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2,
            phase: ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst)
        )
        XCTAssertTrue(disabledStatic.bytes == disabledBurst.bytes, "disabled animation preserves static pixels")
    }

    func testFractionalMenuBarSizesKeepExactPixelLengthAndGeometryConventions() throws {
        let scene = mappedScene(for: PresentationFixtures.snapshot(rssi: -79, scalar: 0.74, muted: true))
        let standardScale = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 20, scale: 8)
        let fractionalSize = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 18.5, scale: 3)
        XCTAssertEqual(standardScale.width, 160)
        XCTAssertEqual(standardScale.height, 160)
        XCTAssertEqual(standardScale.bytes.count, 160 * 160 * 4)
        XCTAssertEqual(fractionalSize.width, 56)
        XCTAssertEqual(fractionalSize.height, 56)
        XCTAssertEqual(fractionalSize.bytes.count, 56 * 56 * 4)
        assertMenuBarPixelConventions(standardScale, size: 20, scale: 8, label: "20pt at 8x")
        assertMenuBarPixelConventions(fractionalSize, size: 18.5, scale: 3, label: "fractional logical size")
    }

    func testMenuBarRejectsNonFiniteAndNonPositiveSizeAndScale() {
        let scene = mappedScene(for: PresentationFixtures.snapshot())
        let foreground = CGColor(gray: 1, alpha: 1)
        let critical = StatusIconRenderer.defaultCriticalColor
        for size: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(StatusIconRenderer.render(
                scene: scene,
                environment: StatusIconRenderEnvironment(size: size, scale: 2,
                                                         foreground: foreground, criticalColor: critical)
            ), "size=\(size)")
        }
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(StatusIconRenderer.render(
                scene: scene,
                environment: StatusIconRenderEnvironment(size: 20, scale: scale,
                                                         foreground: foreground, criticalColor: critical)
            ), "scale=\(scale)")
        }
    }

    func testRendererRejectsEmptyAndMultiSegmentRings() {
        let foreground = CGColor(gray: 1, alpha: 1)
        let environment = StatusIconRenderEnvironment(
            size: 28,
            scale: 2,
            foreground: foreground,
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let one = RingSegmentState(progress: 0.4, color: .primary)
        let unsupported = [
            OuterRingState(segments: [], gap: .closed),
            OuterRingState(segments: [one, one], gap: .closed)
        ]
        for ring in unsupported {
            XCTAssertNil(StatusIconRenderer.render(scene: IconSceneState(outerRing: ring), environment: environment))
        }
        XCTAssertNil(StatusIconRenderer.render(
            scene: IconSceneState(footer: .dots(DotsState(count: 5, activeCount: 3, color: .primary))),
            environment: environment
        ))
        XCTAssertNil(DockIconRenderer.image(scene: IconSceneState(), pixelLength: 513))
    }

    func testUnknownSymbolAndUnreadableImageUseKnownSceneFallbacks() throws {
        let environment = StatusIconRenderEnvironment(
            size: 28,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let unknown = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "status-trio-symbol-that-does-not-exist", variableValue: nil,
                           fallback: "dot.radiowaves.left.and.right"),
            color: .bluetooth,
            scale: 1
        )))
        let knownWaveFallback = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "dot.radiowaves.left.and.right", variableValue: 1, fallback: nil),
            color: .bluetooth,
            scale: 1
        )))
        let unknownPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: unknown, environment: environment
        )))
        let fallbackPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: knownWaveFallback, environment: environment
        )))
        XCTAssertEqual(unknownPixels.width, 56)
        XCTAssertEqual(unknownPixels.height, 56)
        XCTAssertEqual(unknownPixels.bytes, fallbackPixels.bytes,
                       "an unavailable symbol uses its explicitly declared available glyph")

        let missingImage = IconSceneState(center: .symbol(IconSymbolState(
            source: .image(url: URL(fileURLWithPath: "/tmp/status-trio-missing-device-icon.png"),
                           fallbackSymbol: "headphones"),
            color: .bluetooth,
            scale: 1
        )))
        let knownImageFallback = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "headphones", variableValue: 1, fallback: nil),
            color: .bluetooth,
            scale: 1
        )))
        let missingPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: missingImage, environment: environment
        )))
        let imageFallbackPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: knownImageFallback, environment: environment
        )))
        XCTAssertEqual(missingPixels.bytes, imageFallbackPixels.bytes,
                       "an unreadable image uses its explicitly declared fallback glyph")
    }

    func testKnownPickedSymbolWithoutDeviceKeepsDeclaredCenterGlyph() throws {
        let snapshot = PresentationFixtures.snapshot()
        let symbol = "headphones"
        XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        let picked = configuration(bluetooth: BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: symbol
        ))
        let scene = mappedScene(for: snapshot, configuration: picked)
        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .symbol(name: symbol, variableValue: nil, fallback: "dot.radiowaves.left.and.right"),
            color: .bluetooth,
            scale: BluetoothAudioIconOptions(replacesNetworkIcon: true,
                                             networkIconSymbolOverride: symbol).symbolScale
        )))
        let pixels = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        XCTAssertGreaterThan(pixels.alphaSum(inSVGRect: CGRect(x: 42, y: 55, width: 35, height: 35), size: 28, scale: 2),
                             100, "the picked headphones glyph occupies the fixed center slot")
    }

    func testReadableDeviceImageMapsAndRendersOnBothSurfaces() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-readable-device-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)

        let device = AudioOutputDevice(id: 42, name: "Custom Bluetooth", isCurrent: true,
                                       volume: 0.6, transport: .bluetooth, iconURL: url)
        let snapshot = makeSnapshot(
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: device.name, currentDevice: device)
        )
        let bluetooth = BluetoothAudioIconOptions(replacesNetworkIcon: true)
        let scene = mappedScene(for: snapshot, configuration: configuration(bluetooth: bluetooth))
        XCTAssertEqual(IconPresentationResourceResolver.inputs(snapshot: snapshot).audioIcon,
                       .image(url: url, fallbackSymbol: "headphones"))
        guard case .symbol(let center)? = scene.center else {
            return XCTFail("A readable Bluetooth resource must occupy the center slot")
        }
        XCTAssertEqual(center.source, .image(url: url, fallbackSymbol: "headphones"))
        let pixels = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        XCTAssertGreaterThan(pixels.alphaSum(inSVGRect: CGRect(x: 38, y: 43, width: 43, height: 42), size: 28, scale: 2),
                             100, "the resolved image resource occupies its fixed 42-unit center box")
        XCTAssertTrue(pixels.containsColor(red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1,
                                           tolerance: 0.08, minimumAlpha: 0.9),
                      "the Bluetooth image keeps its declared menu-bar tint")
        for style in [DockIconBackgroundStyle.dark, .light] {
            let dock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                scene: scene, backgroundStyle: style, pixelLength: 96
            )))
            let centerImagePixels = CGRect(x: 35, y: 30, width: 30, height: 34)
            XCTAssertGreaterThan(alphaSum(dock, inPixelRect: centerImagePixels), 100,
                                 "the device image stays in the Dock center glyph box: \(style)")
            let expectedBlue = style == .dark
                ? (red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1.0)
                : (red: 0.0, green: 102.0 / 255.0, blue: 204.0 / 255.0)
            XCTAssertTrue(containsColor(
                dock,
                inPixelRect: centerImagePixels,
                red: expectedBlue.red,
                green: expectedBlue.green,
                blue: expectedBlue.blue,
                tolerance: 0.1
            ), "the device image keeps the Dock palette tint: \(style)")
        }
    }

    func testColoredBoltAndPlugPrimitivesUseDeclaredColor() throws {
        let foreground = CGColor(gray: 1, alpha: 1)
        let environment = StatusIconRenderEnvironment(size: 28, scale: 2, foreground: foreground,
                                                      criticalColor: StatusIconRenderer.defaultCriticalColor)
        for primitive in [IconPrimitive.bolt, .plug] {
            let primary = IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.43, color: .primary)],
                gap: .indicator,
                accessory: .symbol(IconSymbolState(source: .primitive(primitive), color: .primary, scale: 1)),
                effect: primitive == .bolt ? RingEffectState(pulsesAccessory: true, tintsAccessory: true) : nil
            ))
            let critical = IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.43, color: .primary)],
                gap: .indicator,
                accessory: .symbol(IconSymbolState(source: .primitive(primitive), color: .critical, scale: 1)),
                effect: primitive == .bolt ? RingEffectState(pulsesAccessory: true, tintsAccessory: true) : nil
            ))
            let phase = ChargingEffectPhase(step: 5, stepsPerCycle: 12, kind: .burst)
            let primaryImage = try XCTUnwrap(StatusIconRenderer.render(scene: primary, environment: environment,
                                                                        phase: phase))
            let criticalImage = try XCTUnwrap(StatusIconRenderer.render(scene: critical, environment: environment,
                                                                        phase: phase))
            XCTAssertNotEqual(try PixelBuffer(image: primaryImage).bytes,
                              try PixelBuffer(image: criticalImage).bytes,
                              "\(primitive) must use its declared scene color")
        }
    }

    func testBluetoothVolumeArcRetainsIndependentTintConventionOnDock() throws {
        let snapshot = makeSnapshot(volume: VolumeStatus(
            scalar: 0.72,
            isMuted: false,
            deviceName: "Headphones",
            currentDevice: PresentationFixtures.bluetoothDevice
        ))
        let options = configuration(
            volume: VolumeIconOptions(displayStyle: .arc),
            bluetooth: BluetoothAudioIconOptions(usesVolumeColor: true)
        )
        let scene = mappedScene(for: snapshot, configuration: options)
        let dark = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: scene, backgroundStyle: .dark, pixelLength: 96
        )))
        let light = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: scene, backgroundStyle: .light, pixelLength: 96
        )))
        XCTAssertTrue(dark.containsColor(red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1,
                                         tolerance: 0.08, minimumAlpha: 0.9),
                      "dark Dock retains the Bluetooth volume-arc tint")
        XCTAssertTrue(light.containsColor(red: 0, green: 102.0 / 255.0, blue: 204.0 / 255.0,
                                          tolerance: 0.1, minimumAlpha: 0.9),
                      "light Dock uses the established darker Bluetooth tint")
    }

    private struct VisualCase {
        let name: String
        let snapshot: StatusSnapshot
        let configuration: IconPresentationConfiguration
        let expectedScene: IconSceneState
        let distinctRegions: [CGRect]
    }

    private func pixelsDiffer(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat
    ) -> Bool {
        let pixelsPerSVGUnit = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * pixelsPerSVGUnit).rounded(.down)))
        let maxX = min(lhs.width, Int((rect.maxX * pixelsPerSVGUnit).rounded(.up)))
        let minY = max(0, Int((rect.minY * pixelsPerSVGUnit).rounded(.down)))
        let maxY = min(lhs.height, Int((rect.maxY * pixelsPerSVGUnit).rounded(.up)))
        for y in minY..<maxY {
            for x in minX..<maxX where lhs.rgba(x: x, y: y) != rhs.rgba(x: x, y: y) {
                return true
            }
        }
        return false
    }

    private func pixelsDiffer(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        inDockSVGRect rect: CGRect,
        pixelLength: Int
    ) -> Bool {
        let dockScale = CGFloat(pixelLength) / 1024
        let glyphOrigin = CGPoint(x: 194.8 * dockScale, y: 171.84 * dockScale)
        let glyphScale = 672 * dockScale / StatusIconGeometry.canvas.width
        let xMin = Int((glyphOrigin.x + rect.minX * glyphScale).rounded(.down))
        let xMax = Int((glyphOrigin.x + rect.maxX * glyphScale).rounded(.up))
        let yMin = Int((glyphOrigin.y + rect.minY * glyphScale).rounded(.down))
        let yMax = Int((glyphOrigin.y + rect.maxY * glyphScale).rounded(.up))
        for y in max(0, yMin)..<min(lhs.height, yMax) {
            for x in max(0, xMin)..<min(lhs.width, xMax) where lhs.rgba(x: x, y: y) != rhs.rgba(x: x, y: y) {
                return true
            }
        }
        return false
    }

    private func visualCases() -> [VisualCase] {
        let ordinary = PresentationFixtures.snapshot(rssi: -60)
        let mediumWiFi = symbol("wifi", value: 0.66)
        let ordinaryRing = ring(progress: 0.68, color: .primary, gap: .value,
                                accessory: .text(IconTextState(text: "68", color: .primary, scale: 1.8)))
        let slash = CenterState.symbol(IconSymbolState(source: .symbol(name: "wifi.slash", variableValue: 1, fallback: nil), color: .primary, scale: 1))
        let placeholderRing = ring(progress: 1, color: .primary, gap: .value,
                                   accessory: .text(IconTextState(text: "100", color: .primary, scale: 1.8)))
        let ordinaryFooter = FooterState.dots(DotsState(count: 4, activeCount: 3, color: .primary, strokeScale: 1.25))
        let inactiveFooter = FooterState.dots(DotsState(count: 4, activeCount: 0, color: .primary, strokeScale: 1.25))

        func scene(
            ring: OuterRingState,
            center: CenterState = mediumWiFi,
            footer: FooterState = ordinaryFooter
        ) -> IconSceneState {
            IconSceneState(outerRing: ring, center: center, footer: footer)
        }

        func visualCase(
            _ name: String,
            snapshot: StatusSnapshot,
            configuration: IconPresentationConfiguration = .standard,
            expected: IconSceneState,
            distinctRegion: CGRect
        ) -> VisualCase {
            VisualCase(
                name: name,
                snapshot: snapshot,
                configuration: configuration,
                expectedScene: expected,
                distinctRegions: [distinctRegion]
            )
        }

        let batteryRegion = CGRect(x: 0, y: 0, width: 120, height: 100)
        let centerRegion = CGRect(x: 30, y: 40, width: 60, height: 52)
        let footerRegion = CGRect(x: 25, y: 98, width: 70, height: 22)
        var cases = [visualCase(
            "ordinary",
            snapshot: ordinary,
            expected: scene(ring: ordinaryRing, center: symbol("wifi", value: 1)),
            distinctRegion: batteryRegion
        )]

        let batteryCases: [(String, BatteryStatus, BatteryIconOptions, OuterRingState)] = [
            ("low battery critical", battery(percentage: 12), .standard,
             ring(progress: 0.12, color: .critical, gap: .value, accessory: .text(IconTextState(text: "12", color: .primary, scale: 1.8)))),
            ("low power", BatteryStatus(rawPercentage: 34, isPresent: true, isCharging: false,
                                         isLowPowerMode: true, isConnectedToPower: false), .standard,
             ring(progress: 0.34, color: .lowPower, gap: .value, accessory: .text(IconTextState(text: "34", color: .primary, scale: 1.8)))),
            ("charging bolt", battery(percentage: 43, charging: true, connected: true), .standard,
             ring(progress: 0.43, color: .powered, gap: .indicator, accessory: .symbol(IconSymbolState(source: .primitive(.bolt), color: .primary, scale: 1.8)), effect: RingEffectState(pulsesAccessory: true, tintsAccessory: true))),
            ("connected plug", battery(percentage: 73, connected: true), .standard,
             ring(progress: 0.73, color: .powered, gap: .indicator, accessory: .symbol(IconSymbolState(source: .primitive(.plug), color: .primary, scale: 1.8)))),
            ("present battery closed ring", battery(percentage: 68), BatteryIconOptions(
                showsPercentage: false, showsChargingIndicator: false, usesStatusColors: false
            ), ring(progress: 0.68, color: .primary, gap: .closed, accessory: nil)),
            ("scaled battery text and bold ring", battery(percentage: 54), BatteryIconOptions(
                textScale: 1.35, ringStrokeScale: 1.5
            ), ring(progress: 0.54, color: .primary, gap: .value, accessory: .text(IconTextState(text: "54", color: .primary, scale: 1.35)), strokeScale: 1.5)),
            ("custom critical threshold", battery(percentage: 28), BatteryIconOptions(
                criticalThreshold: 30, ringStrokeScale: 1
            ), ring(progress: 0.28, color: .critical, gap: .value, accessory: .text(IconTextState(text: "28", color: .primary, scale: 1.8)), strokeScale: 1)),
            ("absent battery", BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                              isLowPowerMode: false, isConnectedToPower: false), .standard,
             placeholderRing)
        ]
        for (name, status, options, expectedRing) in batteryCases {
            cases.append(visualCase(
                name,
                snapshot: makeSnapshot(battery: status),
                configuration: configuration(battery: options),
                expected: scene(ring: expectedRing, center: slash, footer: inactiveFooter),
                distinctRegion: batteryRegion
            ))
        }

        let noInternet = CenterState.symbol(IconSymbolState(source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil), color: .primary, scale: 1))
        let wifiCases: [(String, WiFiStatus, NetworkConnection, ConnectionIconOptions, CenterState)] = [
            ("connected full signal", WiFiStatus(state: .connected, rssi: -60), .wifi, .standard, symbol("wifi", value: 1)),
            ("connected medium signal", WiFiStatus(state: .connected, rssi: -70), .wifi, .standard, mediumWiFi),
            ("connected weak signal", WiFiStatus(state: .connected, rssi: -85), .wifi, .standard, symbol("wifi", value: 0.33)),
            ("connected no signal", WiFiStatus(state: .connected, rssi: nil), .wifi, .standard, symbol("wifi", value: 0)),
            ("not associated", WiFiStatus(state: .notAssociated, rssi: nil), .wifi, .standard, symbol("wifi", value: 0)),
            ("wifi off", WiFiStatus(state: .off, rssi: nil), .wifi, .standard, slash),
            ("wifi unavailable", WiFiStatus(state: .unavailable, rssi: nil), .wifi, .standard, slash),
            ("no internet", WiFiStatus(state: .noInternet, rssi: -45), .wifi, .standard, noInternet),
            ("hotspot mark", WiFiStatus(state: .hotspot, rssi: -65), .wifi, .standard,
             symbol("personalhotspot", value: 1)),
            ("hotspot signal", WiFiStatus(state: .hotspot, rssi: -65), .wifi,
             ConnectionIconOptions(showsWiFiIconForHotspot: true), mediumWiFi),
            ("temporary mark", WiFiStatus(state: .temporary, rssi: -65), .wifi, .standard,
             .symbol(IconSymbolState(source: .primitive(.screenWedge), color: .primary, scale: 1))),
            ("temporary signal", WiFiStatus(state: .temporary, rssi: -65), .wifi,
             ConnectionIconOptions(showsWiFiIconForTemporaryConnection: true, wifiScale: 1.4), symbol("wifi", value: 0.66, scale: 1.4)),
            ("shared mark", WiFiStatus(state: .shared, rssi: -65), .wifi, .standard,
             .symbol(IconSymbolState(source: .primitive(.arrowWedge), color: .primary, scale: 1))),
            ("shared signal", WiFiStatus(state: .shared, rssi: -65), .wifi,
             ConnectionIconOptions(showsWiFiIconForInternetSharing: true, wifiScale: 0.8), symbol("wifi", value: 0.66, scale: 0.8)),
            ("ethernet", WiFiStatus(state: .off, rssi: nil), .ethernet, .standard,
             .symbol(IconSymbolState(source: .primitive(.wiredPort), color: .primary, scale: 1))),
            ("ethernet as full wifi", WiFiStatus(state: .off, rssi: nil), .ethernet,
             ConnectionIconOptions(showsWiFiIconForEthernet: true, wifiScale: 1.3), symbol("wifi", value: 1, scale: 1.3))
        ]
        for (name, wifi, connection, options, expectedCenter) in wifiCases {
            cases.append(visualCase(
                name,
                snapshot: makeSnapshot(wifi: wifi, connection: connection),
                configuration: configuration(connection: options),
                expected: scene(ring: placeholderRing, center: expectedCenter, footer: inactiveFooter),
                distinctRegion: name == "connected full signal" ? .zero : centerRegion
            ))
        }
        cases.append(visualCase(
            "battery percentage in center slot",
            snapshot: ordinary,
            configuration: configuration(connection: ConnectionIconOptions(showsBatteryPercentageInConnectionSlot: true)),
            expected: scene(ring: ordinaryRing, center: .text(IconTextState(text: "68", color: .primary, scale: 1))),
            distinctRegion: centerRegion
        ))

        let volumeCenter = slash
        let volumeCases: [(String, VolumeStatus, VolumeIconOptions, BluetoothAudioIconOptions, FooterState, CenterState)] = [
            ("volume silent dots", VolumeStatus(scalar: 0, isMuted: false, deviceName: "Output"), .standard, .standard,
             .dots(DotsState(count: 4, activeCount: 0, color: .primary, strokeScale: 1.25)), volumeCenter),
            ("volume partial dots", VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output"), .standard, .standard,
             .dots(DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1.25)), volumeCenter),
            ("volume full dots", VolumeStatus(scalar: 1, isMuted: false, deviceName: "Output"), .standard, .standard,
             .dots(DotsState(count: 4, activeCount: 4, color: .primary, strokeScale: 1.25)), volumeCenter),
            ("volume muted", VolumeStatus(scalar: 0.82, isMuted: true, deviceName: "Output"), .standard, .standard,
             .dots(DotsState(count: 4, activeCount: 0, color: .primary, strokeScale: 1.25)), volumeCenter),
            ("volume unavailable", .placeholder, .standard, .standard,
             .dots(DotsState(count: 4, activeCount: 0, color: .primary, strokeScale: 1.25)), volumeCenter),
            ("volume arc", VolumeStatus(scalar: 0.63, isMuted: false, deviceName: "Output"),
             VolumeIconOptions(displayStyle: .arc, ringStrokeScale: 1.5), .standard,
             .arc(ArcState(progress: 0.63, color: .primary, strokeScale: 1.5)), volumeCenter),
            ("bold volume dots", VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output"),
             VolumeIconOptions(ringStrokeScale: 1.5), .standard,
             .dots(DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: 1.5)), volumeCenter),
            ("volume muted arc", VolumeStatus(scalar: 0.63, isMuted: true, deviceName: "Output"),
             VolumeIconOptions(displayStyle: .arc), .standard,
             .arc(ArcState(progress: 0, color: .primary, strokeScale: 1.25)), volumeCenter),
            ("Bluetooth tinted volume", VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "Output",
                                                       currentDevice: PresentationFixtures.bluetoothDevice),
             .standard, BluetoothAudioIconOptions(usesVolumeColor: true),
             .dots(DotsState(count: 4, activeCount: 3, color: .bluetooth, strokeScale: 1.25)), volumeCenter),
            ("Bluetooth replaced center", VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "Output",
                                                         currentDevice: PresentationFixtures.bluetoothDevice),
             .standard, BluetoothAudioIconOptions(replacesNetworkIcon: true, usesVolumeColor: true),
             .dots(DotsState(count: 4, activeCount: 3, color: .bluetooth, strokeScale: 1.25)),
             .symbol(IconSymbolState(source: .symbol(name: "airpods.pro", variableValue: nil, fallback: "headphones"),
                                     color: .bluetooth, scale: 1.6)))
        ]
        for (name, volume, options, bluetooth, expectedFooter, expectedCenter) in volumeCases {
            let wifi = name == "Bluetooth replaced center"
                ? WiFiStatus(state: .connected, rssi: -60)
                : WiFiStatus.placeholder
            cases.append(visualCase(
                name,
                snapshot: makeSnapshot(wifi: wifi, volume: volume),
                configuration: configuration(volume: options, bluetooth: bluetooth),
                expected: scene(ring: placeholderRing, center: expectedCenter, footer: expectedFooter),
                distinctRegion: name == "Bluetooth replaced center" ? centerRegion : footerRegion
            ))
        }

        return cases
    }

    private func ring(
        progress: Double,
        color: IconColorRole,
        gap: RingGapStyle,
        accessory: RingAccessoryState?,
        strokeScale: Double = 1.25,
        effect: RingEffectState? = nil
    ) -> OuterRingState {
        OuterRingState(
            segments: [RingSegmentState(progress: progress, color: color)],
            gap: gap,
            accessory: accessory,
            effect: effect,
            strokeScale: strokeScale
        )
    }

    private func symbol(
        _ name: String,
        value: Double,
        color: IconColorRole = .primary,
        scale: Double = 1
    ) -> CenterState {
        .symbol(IconSymbolState(
            source: .symbol(name: name, variableValue: value, fallback: nil),
            color: color,
            scale: scale
        ))
    }

    private func menuBarPixels(
        scene: IconSceneState,
        foreground: CGColor,
        size: CGFloat,
        scale: CGFloat,
        phase: ChargingEffectPhase? = nil
    ) throws -> PixelBuffer {
        let environment = StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        return try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: scene, environment: environment, phase: phase
        )))
    }

    private func composite(
        base: CGImage,
        overlay: CGImage,
        environment: StatusIconRenderEnvironment
    ) throws -> CGImage {
        let pixelLength = Int((environment.size * environment.scale).rounded(.up))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelLength,
            height: pixelLength,
            bitsPerComponent: 8,
            bytesPerRow: pixelLength * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let rect = CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength)
        context.draw(base, in: rect)
        context.draw(overlay, in: rect)
        return try XCTUnwrap(context.makeImage())
    }

    private func maximumChannelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        zip(lhs, rhs).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    private func cgPixels(from image: NSImage) throws -> PixelBuffer {
        try PixelBuffer(image: XCTUnwrap(XCTUnwrap(image.representations.first as? NSBitmapImageRep).cgImage))
    }

    private func assertMenuBarPixelConventions(
        _ pixels: PixelBuffer,
        size: CGFloat,
        scale: CGFloat,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dimension = Int((size * scale).rounded(.up))
        XCTAssertEqual(pixels.width, dimension, "canvas width: \(label)", file: file, line: line)
        XCTAssertEqual(pixels.height, dimension, "canvas height: \(label)", file: file, line: line)
        XCTAssertEqual(pixels.bytes.count, dimension * dimension * 4, "complete RGBA buffer: \(label)", file: file, line: line)
        let fixedRegions: [(String, CGRect)] = [
            ("battery upper track", CGRect(x: 18, y: 11, width: 84, height: 22)),
            ("center connection slot", CGRect(x: 37, y: 48, width: 45, height: 43)),
            ("volume footer", CGRect(x: 33, y: 98, width: 54, height: 19))
        ]
        for (name, region) in fixedRegions {
            XCTAssertGreaterThan(
                pixels.alphaSum(inSVGRect: region, size: size, scale: scale),
                100,
                "\(name) must leave measurable ink at its fixed artwork location: \(label)",
                file: file,
                line: line
            )
        }
    }

    private func alphaSum(_ pixels: PixelBuffer, inPixelRect rect: CGRect) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(pixels.width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        return (minY..<maxY).reduce(0) { row, y in
            row + (minX..<maxX).reduce(0) { row, x in
                row + Int(pixels.rgba(x: x, y: y).alpha)
            }
        }
    }

    private func changedPixelCount(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat
    ) -> Int {
        let factor = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * factor).rounded(.down)))
        let maxX = min(lhs.width, Int((rect.maxX * factor).rounded(.up)))
        let minY = max(0, Int((rect.minY * factor).rounded(.down)))
        let maxY = min(lhs.height, Int((rect.maxY * factor).rounded(.up)))
        guard lhs.width == rhs.width, lhs.height == rhs.height, minX < maxX, minY < maxY else { return 0 }
        return (minY..<maxY).reduce(0) { count, y in
            count + (minX..<maxX).reduce(0) { rowCount, x in
                let left = lhs.rgba(x: x, y: y)
                let right = rhs.rgba(x: x, y: y)
                return rowCount + (left.red == right.red && left.green == right.green
                    && left.blue == right.blue && left.alpha == right.alpha ? 0 : 1)
            }
        }
    }

    private func scaledPixelRect(_ rect: CGRect, size: CGFloat, scale: CGFloat) -> CGRect {
        rect.applying(CGAffineTransform(
            scaleX: size * scale / StatusIconGeometry.canvas.width,
            y: size * scale / StatusIconGeometry.canvas.height
        ))
    }

    private func changedPixels(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat
    ) -> [(x: Int, y: Int)] {
        let factor = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * factor).rounded(.down)))
        let maxX = min(lhs.width, Int((rect.maxX * factor).rounded(.up)))
        let minY = max(0, Int((rect.minY * factor).rounded(.down)))
        let maxY = min(lhs.height, Int((rect.maxY * factor).rounded(.up)))
        guard lhs.width == rhs.width, lhs.height == rhs.height, minX < maxX, minY < maxY else { return [] }
        return (minY..<maxY).flatMap { y in
            (minX..<maxX).compactMap { x in
                let left = lhs.rgba(x: x, y: y)
                let right = rhs.rgba(x: x, y: y)
                guard left.red != right.red || left.green != right.green
                    || left.blue != right.blue || left.alpha != right.alpha else { return nil }
                return (x: x, y: y)
            }
        }
    }

    private func containsColor(
        _ pixels: PixelBuffer,
        inPixelRect rect: CGRect,
        red: Double,
        green: Double,
        blue: Double,
        tolerance: Double
    ) -> Bool {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(pixels.width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return false }
        for y in minY..<maxY {
            for x in minX..<maxX {
                let pixel = pixels.rgba(x: x, y: y)
                guard pixel.alpha >= 240 else { continue }
                if abs(Double(pixel.red) / 255 - red) <= tolerance,
                   abs(Double(pixel.green) / 255 - green) <= tolerance,
                   abs(Double(pixel.blue) / 255 - blue) <= tolerance {
                    return true
                }
            }
        }
        return false
    }

    private func mappedScene(
        for snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: snapshot),
            configuration: configuration
        )
    }

    private func configuration(
        battery: BatteryIconOptions = .standard,
        connection: ConnectionIconOptions = .standard,
        volume: VolumeIconOptions = .standard,
        bluetooth: BluetoothAudioIconOptions = .standard
    ) -> IconPresentationConfiguration {
        IconPresentationConfiguration(battery: battery, connection: connection, volume: volume, bluetooth: bluetooth)
    }

    private func makeSnapshot(
        battery: BatteryStatus = .placeholder,
        wifi: WiFiStatus = .placeholder,
        connection: NetworkConnection = .wifi,
        volume: VolumeStatus = .placeholder
    ) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
    }

    private func battery(percentage: Int, charging: Bool = false, connected: Bool = false) -> BatteryStatus {
        BatteryStatus(rawPercentage: percentage, isPresent: true, isCharging: charging,
                      isLowPowerMode: false, isConnectedToPower: connected)
    }

    private func cgImage(from image: NSImage) throws -> CGImage {
        try XCTUnwrap(XCTUnwrap(image.representations.first as? NSBitmapImageRep).cgImage)
    }

}
