import AppKit
import XCTest
@testable import StatusTrioCore

final class IconSizingStandardTests: XCTestCase {
    func testCenterStandardDefinesOneContinuousPercentageRangeAndBaseline() {
        XCTAssertEqual(IconCenterSizingPolicy.percentageRange, 1.0...1.8)
        XCTAssertEqual(IconCenterSizingPolicy.percentageStep, 0.05, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.baselineVisibleHeight, 31.1, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.legacyPercentageRendererScale, 28.0 / 31.0, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.legacyWiFiRendererScale, 28.0 / 34.0, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.normalizedPercentage(.nan), 1, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.normalizedPercentage(4), 1.8, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.normalizedPercentage(0.4), 1, accuracy: 1e-12)
    }

    @MainActor
    func testLegacyNormalizedScaleRatiosAndRasterRemainFrozen() throws {
        XCTAssertEqual(IconCenterSizingPolicy.legacyPercentageRendererScale, 28.0 / 31.0, accuracy: 1e-12)
        XCTAssertEqual(IconCenterSizingPolicy.legacyWiFiRendererScale, 28.0 / 34.0, accuracy: 1e-12)

        var appearance = IconAppearanceConfiguration.classic
        appearance.center.normalizedSizePercentage = nil
        appearance.center.normalizedPercentageScale = 1.4
        appearance.center.effectiveSymbolScale = nil

        let wifiSource = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1
        )))
        let resolvedWiFi = IconPaletteResolver.apply(wifiSource, appearance: appearance, centerSource: .network)
        let historicalWiFi = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary,
            scale: 1.4 * (28.0 / 34.0)
        )))
        XCTAssertEqual(resolvedWiFi, historicalWiFi)

        let textSource = IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1)))
        let resolvedText = IconPaletteResolver.apply(textSource, appearance: appearance, centerSource: .systemBatteryPercentage)
        let historicalText = IconSceneState(center: .text(IconTextState(
            text: "100", color: .primary, scale: 1.4 * (28.0 / 31.0)
        )))
        XCTAssertEqual(resolvedText, historicalText)

        let menuEnvironment = StatusIconRenderEnvironment(
            size: 120, scale: 4, foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        for (resolved, historical) in [(resolvedWiFi, historicalWiFi), (resolvedText, historicalText)] {
            let resolvedMenu = try XCTUnwrap(StatusIconRenderer.render(scene: resolved, environment: menuEnvironment))
            let historicalMenu = try XCTUnwrap(StatusIconRenderer.render(scene: historical, environment: menuEnvironment))
            XCTAssertEqual(try PixelBuffer(image: resolvedMenu).bytes, try PixelBuffer(image: historicalMenu).bytes)

            let resolvedDock = try XCTUnwrap(DockIconRenderer.image(scene: resolved, pixelLength: 512))
            let historicalDock = try XCTUnwrap(DockIconRenderer.image(scene: historical, pixelLength: 512))
            let resolvedDockCG = try XCTUnwrap((resolvedDock.representations.first as? NSBitmapImageRep)?.cgImage)
            let historicalDockCG = try XCTUnwrap((historicalDock.representations.first as? NSBitmapImageRep)?.cgImage)
            XCTAssertEqual(try PixelBuffer(image: resolvedDockCG).bytes, try PixelBuffer(image: historicalDockCG).bytes)
        }
    }

    @MainActor
    func testOneExplicitCenterSizeAppliesToSymbolsTextAndSourceSwitches() throws {
        var appearance = IconAppearanceConfiguration.classic
        appearance.center.normalizedSizePercentage = 1.35
        appearance.center.normalizedPercentageScale = 1.1
        appearance.center.effectiveSymbolScale = 4.25

        let symbol = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
            color: .primary,
            scale: 2.4
        )))
        let text = IconSceneState(center: .text(IconTextState(text: "100", color: .primary, scale: 1.8)))
        let wired = IconSceneState(center: .symbol(IconSymbolState(
            source: .primitive(.wiredPort), color: .primary, scale: 1
        )))

        for source in [CenterSource.bluetoothAudioOutput, .network, .systemBatteryPercentage, .pinnedBluetoothGlyph] {
            for scene in [symbol, text, wired] {
                let resolved = IconPaletteResolver.apply(scene, appearance: appearance, centerSource: source)
                XCTAssertEqual(resolved.center?.normalizedSizePercentageValue, 1.35)
            }
        }

        var edited = IconConfigurationV1.classic
        edited.appearance.center.normalizedPercentageScale = 1.1
        edited.appearance.center.effectiveSymbolScale = 4.25
        IconDesignerEditingModel.settingCommonPercentageScale(1.35, in: &edited)
        XCTAssertEqual(try XCTUnwrap(edited.appearance.center.normalizedSizePercentage), 1.35, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(edited.appearance.center.normalizedPercentageScale), 1.1, accuracy: 1e-12,
                       "Explicit sizing must not rewrite historical source-specific data.")
        XCTAssertEqual(try XCTUnwrap(edited.appearance.center.effectiveSymbolScale), 4.25, accuracy: 1e-12,
                       "An explicit common-size edit must preserve the legacy raw scale for rollback.")
    }

    @MainActor
    func testLegacyNilSizeRemainsUnmarkedUntilExplicitEditAndOldPayloadRoundTrips() throws {
        var appearance = IconAppearanceConfiguration.classic
        appearance.center.effectiveSymbolScale = 4.25
        let scene = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
            color: .primary,
            scale: 1.6
        )))
        let legacy = IconPaletteResolver.apply(scene, appearance: appearance, centerSource: .bluetoothAudioOutput)
        XCTAssertNil(legacy.center?.normalizedSizePercentageValue)
        XCTAssertEqual(try XCTUnwrap(legacy.center?.legacyScale), 4.25, accuracy: 1e-12)

        let oldPayload = #"{"symbolScale":1.6,"effectiveSymbolScale":4.25,"normalizedPercentageScale":1.1,"color":{"automatic":{}}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CenterAppearance.self, from: oldPayload)
        XCTAssertNil(decoded.normalizedSizePercentage)
        XCTAssertEqual(try XCTUnwrap(decoded.effectiveSymbolScale), 4.25, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(decoded.normalizedPercentageScale), 1.1, accuracy: 1e-12)
    }

    @MainActor
    func testFallbackResolvedFromAnotherSourceKeepsTheExplicitCommonSize() throws {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        configuration.appearance.center.normalizedSizePercentage = 1.45
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: .placeholder,
                    wifi: WiFiStatus(state: .off, rssi: nil),
                    connection: .wifi,
                    volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Bluetooth",
                                         currentDevice: PresentationFixtures.bluetoothDevice)
                ),
                audioIcon: .symbol(name: "headphones", variableValue: nil, fallback: nil)
            ),
            sources: IconSourceSnapshot(availability: [CenterSource.network.rawValue: .unavailable(.disconnected)])
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration)
        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.bluetoothAudioOutput.rawValue)
        XCTAssertEqual(output.scene.center?.normalizedSizePercentageValue, 1.45)
    }

    @MainActor
    func testStrokeSettingsResolveToLegacyEndpointsForRingAndFooterTogether() throws {
        let scene = IconSceneState(
            outerRing: OuterRingState(segments: [RingSegmentState(progress: 0.5, color: .primary)], gap: .closed),
            footer: .arc(ArcState(progress: 0.5, color: .primary))
        )
        for percentage in [0.8, 1.0, 1.2] {
            var appearance = IconAppearanceConfiguration.classic
            let rawScale = IconStrokeSizingPolicy.strokeScale(for: percentage)
            appearance.outerRing.strokeScale = rawScale
            appearance.footer.strokeScale = rawScale
            let resolved = IconPaletteResolver.apply(scene, appearance: appearance)
            guard let ring = resolved.outerRing, case let .arc(footer)? = resolved.footer else {
                XCTFail("Both stroke-bearing elements should remain in the resolved scene")
                continue
            }
            XCTAssertEqual(ring.strokeScale, rawScale, accuracy: 1e-12)
            XCTAssertEqual(footer.strokeScale, rawScale, accuracy: 1e-12)
        }
    }

    func testLegacyStrokeStorageAndResetAreNonMutatingUntilExplicitEdit() {
        var appearance = IconAppearanceConfiguration.classic
        appearance.outerRing.strokeScale = 2.5
        appearance.footer.strokeScale = 0.5
        appearance.center.normalizedPercentageScale = 1.25
        let normalized = appearance.outerRing.normalized()
        XCTAssertEqual(normalized.strokeScale, 2.5)
        XCTAssertEqual(appearance.footer.normalized().strokeScale, 0.5)
        XCTAssertEqual(appearance.center.normalizedPercentageScale, 1.25)
        XCTAssertNil(appearance.center.normalizedSizePercentage)

        let reset = appearance.resetting(.center)
        XCTAssertNil(reset.center.normalizedSizePercentage)
        XCTAssertNil(reset.center.normalizedPercentageScale)
        XCTAssertEqual(reset.outerRing.strokeScale, appearance.outerRing.strokeScale)
        XCTAssertEqual(reset.footer.strokeScale, appearance.footer.strokeScale)
    }

    @MainActor
    func testFinalRasterCenterParityUsesProductionMenuPreviewAndDockTransforms() throws {
        let foreground = CGColor(gray: 1, alpha: 1)
        let critical = StatusIconRenderer.defaultCriticalColor
        let sources: [(String, CenterState)] = [
            ("text-8", .text(IconTextState(text: "8", color: .primary, scale: 1, normalizedSizePercentage: 1))),
            ("text-80", .text(IconTextState(text: "80", color: .primary, scale: 1, normalizedSizePercentage: 1))),
            ("text-100", .text(IconTextState(text: "100", color: .primary, scale: 1, normalizedSizePercentage: 1))),
            ("wifi", .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                                              color: .primary, scale: 1, normalizedSizePercentage: 1))),
            ("bluetooth", .symbol(IconSymbolState(source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                                                   color: .primary, scale: 1, normalizedSizePercentage: 1))),
            ("wired", .symbol(IconSymbolState(source: .primitive(.wiredPort), color: .primary,
                                                scale: 1, normalizedSizePercentage: 1)))
        ]

        let surfaces: [(name: String, size: CGFloat, scale: CGFloat)] = [
            ("menu-24pt-2x", 24, 2),
            ("menu-22pt-2x", 22, 2),
            ("preview", 120, 2)
        ]
        for surface in surfaces {
            for percentage in [1.0, 1.8] {
                let environment = StatusIconRenderEnvironment(size: surface.size, scale: surface.scale,
                                                               foreground: foreground, criticalColor: critical)
                let heights = try sources.map { name, source -> (String, CGFloat) in
                    let image = try XCTUnwrap(StatusIconRenderer.render(
                        scene: IconSceneState(center: normalizedCenter(source, percentage: percentage)),
                        environment: environment
                    ))
                    return (name, try coverageBounds(image).height)
                }
                for first in heights.indices {
                    for second in heights.indices where second > first {
                        XCTAssertLessThanOrEqual(abs(heights[first].1 - heights[second].1), 2,
                            "\(heights[first].0) and \(heights[second].0) must share alpha128 target at \(percentage * 100)% on \(surface.name)")
                    }
                }
            }
        }

        for percentage in [1.0, 1.8] {
            let legacy = IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary, scale: percentage
            )))
            let normalized = IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary, scale: 1, normalizedSizePercentage: percentage
            )))
            for surface in surfaces {
                let environment = StatusIconRenderEnvironment(size: surface.size, scale: surface.scale,
                                                               foreground: foreground, criticalColor: critical)
                let oldImage = try XCTUnwrap(StatusIconRenderer.render(scene: legacy, environment: environment))
                let newImage = try XCTUnwrap(StatusIconRenderer.render(scene: normalized, environment: environment))
                XCTAssertLessThanOrEqual(abs(try coverageBounds(oldImage).height - coverageBounds(newImage).height), 2,
                    "Legacy Wi-Fi size at \(percentage * 100)% must match final \(surface.name) raster")
            }

            let oldDock = try XCTUnwrap(DockIconRenderer.image(scene: legacy, pixelLength: 512))
            let newDock = try XCTUnwrap(DockIconRenderer.image(scene: normalized, pixelLength: 512))
            let oldDockCG = try XCTUnwrap((oldDock.representations.first as? NSBitmapImageRep)?.cgImage)
            let newDockCG = try XCTUnwrap((newDock.representations.first as? NSBitmapImageRep)?.cgImage)
            XCTAssertLessThanOrEqual(abs(try whiteDockInkBounds(oldDockCG).height - whiteDockInkBounds(newDockCG).height), 2,
                "Legacy Wi-Fi size at \(percentage * 100)% must match the actual 512px Dock glyph frame")
        }
    }

    @MainActor
    func testNormalizedVariableSymbolDrawsLiveAppearanceAfterReferenceSizing() throws {
        let environment = StatusIconRenderEnvironment(size: 24, scale: 2,
                                                       foreground: CGColor(gray: 1, alpha: 1),
                                                       criticalColor: StatusIconRenderer.defaultCriticalColor)
        func image(_ value: Double) throws -> CGImage {
            try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: value, fallback: nil),
                color: .primary, scale: 1, normalizedSizePercentage: 1.4
            ))), environment: environment))
        }
        let weak = try image(0.15)
        let strong = try image(0.9)
        let legacyWeak = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.15, fallback: nil), color: .primary, scale: 1
        ))), environment: environment))
        let legacyStrong = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0.9, fallback: nil), color: .primary, scale: 1
        ))), environment: environment))
        XCTAssertGreaterThan(abs(try coverageBounds(legacyWeak).height - coverageBounds(legacyStrong).height), 2,
                             "Legacy confirms weak/strong Wi-Fi naturally have different total ink heights")
        let legacyWeakDot = try smallestInkComponentBounds(legacyWeak)
        let legacyStrongDot = try smallestInkComponentBounds(legacyStrong)
        XCTAssertLessThanOrEqual(abs(legacyWeakDot.width - legacyStrongDot.width), 2,
                                 "Legacy weak/strong rasters confirm the shared dot component")
        XCTAssertLessThanOrEqual(abs(legacyWeakDot.height - legacyStrongDot.height), 2)
        XCTAssertLessThanOrEqual(abs(legacyWeakDot.midX - legacyStrongDot.midX), 2)
        let weakDot = try smallestInkComponentBounds(weak)
        let strongDot = try smallestInkComponentBounds(strong)
        XCTAssertLessThanOrEqual(abs(weakDot.width - strongDot.width), 2,
                                 "The shared reference multiplier must preserve the live dot size")
        XCTAssertLessThanOrEqual(abs(weakDot.height - strongDot.height), 2)
        XCTAssertLessThanOrEqual(abs(weakDot.midX - strongDot.midX), 2,
                                 "The live dot remains on the same artwork anchor")
        XCTAssertFalse(try PixelBuffer(image: weak).bytes == PixelBuffer(image: strong).bytes,
                       "The output raster must still draw each live variable-symbol appearance")
    }

    @MainActor
    func testMeasuredCenterInkUsesTheSameHeightForTextSymbolsPrimitivesAndAssets() throws {
        let environment = StatusIconRenderEnvironment(
            size: 120, scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let centers: [CenterState] = [
            .text(IconTextState(text: "8", color: .primary, scale: 1.8, normalizedSizePercentage: 1)),
            .symbol(IconSymbolState(source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                                   color: .primary, scale: 1.6, normalizedSizePercentage: 1)),
            .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                                   color: .primary, scale: 1.3, normalizedSizePercentage: 1)),
            .symbol(IconSymbolState(source: .primitive(.wiredPort), color: .primary,
                                   scale: 1, normalizedSizePercentage: 1)),
            .symbol(IconSymbolState(source: .primitive(.screenWedge), color: .primary,
                                   scale: 1.2, normalizedSizePercentage: 1)),
            .symbol(IconSymbolState(source: .primitive(.arrowWedge), color: .primary,
                                   scale: 1.2, normalizedSizePercentage: 1))
        ]

        for center in centers {
            let normalizedImage = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: center), environment: environment))
            let finalHeight = try coverageBounds(normalizedImage).height
            XCTAssertEqual(finalHeight, 31.1, accuracy: 2, "\(center) must use the common 100% visible-ink baseline")
        }

        let assetURL = try writeTransparentMarginAsset()
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let assetScene = IconSceneState(center: .symbol(IconSymbolState(
            source: .image(url: assetURL, fallbackSymbol: "headphones"), color: .primary,
            scale: 1, normalizedSizePercentage: 1
        )))
        let assetImage = try XCTUnwrap(StatusIconRenderer.render(scene: assetScene, environment: environment))
        XCTAssertEqual(try coverageBounds(assetImage).height, 31.1, accuracy: 2,
                       "Asset transparency margins must not distort the common visible-ink baseline")
    }

    @MainActor
    func testNormalizedCenterRasterPreservesForegroundAndCustomTint() throws {
        let cases: [(IconColorRole, CGColor, CGColor)] = [
            (.primary, CGColor(gray: 0.08, alpha: 1), CGColor(gray: 0.94, alpha: 1)),
            (.bluetooth, CGColor(gray: 0.08, alpha: 1), CGColor(gray: 0.94, alpha: 1)),
            (.custom(IconRGBA(red: 0.12, green: 0.72, blue: 0.34, alpha: 1)),
             CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1))
        ]
        for (role, foreground, critical) in cases {
            let state = CenterState.symbol(IconSymbolState(
                source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                color: role, scale: 1, normalizedSizePercentage: 1
            ))
            let environment = StatusIconRenderEnvironment(size: 120, scale: 2,
                                                           foreground: foreground, criticalColor: critical)
            let image = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: state), environment: environment))
            let pixels = try PixelBuffer(image: image)
            let firstInk = try XCTUnwrap((0..<pixels.height).lazy.flatMap { y in
                (0..<pixels.width).lazy.map { x in (x, y, pixels.rgba(x: x, y: y)) }
            }.first { $0.2.alpha > 245 })
            switch role {
            case .primary:
                XCTAssertLessThan(firstInk.2.red, 80)
                XCTAssertGreaterThan(pixels.rgba(x: firstInk.0, y: firstInk.1).red, 0)
            case .bluetooth:
                XCTAssertLessThan(firstInk.2.red, 80)
                XCTAssertGreaterThan(firstInk.2.blue, firstInk.2.red)
            case .custom:
                XCTAssertGreaterThan(firstInk.2.green, firstInk.2.red)
            default:
                XCTFail("Unexpected test color role")
            }
        }
    }

    @MainActor
    func testNormalizedAssetCacheInvalidatesWhenSameURLChanges() throws {
        let url = try writeTransparentMarginAsset()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = CenterState.symbol(IconSymbolState(
            source: .image(url: url, fallbackSymbol: "headphones"), color: .primary,
            scale: 1, normalizedSizePercentage: 1
        ))
        let environment = StatusIconRenderEnvironment(size: 120, scale: 2,
                                                       foreground: CGColor(gray: 1, alpha: 1),
                                                       criticalColor: StatusIconRenderer.defaultCriticalColor)
        let first = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: state), environment: environment))
        try writeAsset(to: url, width: 80, height: 30, ink: CGRect(x: 10, y: 10, width: 60, height: 10))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_800_000_100)], ofItemAtPath: url.path)
        let second = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: state), environment: environment))
        XCTAssertNotEqual(try PixelBuffer(image: first).bytes, try PixelBuffer(image: second).bytes,
                          "The same asset URL must reload after its modification time and size change")
    }

    @MainActor
    func testNormalizedAsymmetricArtworkKeepsLegacyVerticalOrientation() throws {
        let cases: [CenterState] = [
            .text(IconTextState(text: "6", color: .primary, scale: 1)),
            .symbol(IconSymbolState(source: .primitive(.screenWedge), color: .primary, scale: 1))
        ]
        let environment = StatusIconRenderEnvironment(size: 120, scale: 4,
                                                       foreground: CGColor(gray: 1, alpha: 1),
                                                       criticalColor: StatusIconRenderer.defaultCriticalColor)
        for raw in cases {
            let normalized: CenterState
            switch raw {
            case let .text(text): normalized = .text(IconTextState(text: text.text, color: text.color, scale: 1, normalizedSizePercentage: 1))
            case let .symbol(symbol): normalized = .symbol(IconSymbolState(source: symbol.source, color: symbol.color, scale: 1, normalizedSizePercentage: 1))
            }
            let legacyImage = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: raw), environment: environment))
            let normalizedImage = try XCTUnwrap(StatusIconRenderer.render(scene: IconSceneState(center: normalized), environment: environment))
            let legacyProfile = try normalizedRowProfile(legacyImage)
            let normalizedProfile = try normalizedRowProfile(normalizedImage)
            let directError = zip(legacyProfile, normalizedProfile).reduce(0.0) { $0 + abs($1.0 - $1.1) }
            let flippedError = zip(legacyProfile, normalizedProfile.reversed()).reduce(0.0) { $0 + abs($1.0 - $1.1) }
            XCTAssertLessThan(directError, flippedError,
                              "Canonical CGImage compositing must preserve the legacy vertical orientation for \(raw)")
        }
    }

    @MainActor
    private func normalizedRowProfile(_ image: CGImage) throws -> [Double] {
        let pixels = try PixelBuffer(image: image)
        let bounds = try coverageBounds(image)
        return (0..<64).map { row in
            let y = Int(bounds.minY + (Double(row) + 0.5) * bounds.height / 64)
            guard y >= 0, y < pixels.height else { return 0 }
            let minX = max(0, Int(bounds.minX)), maxX = min(pixels.width, Int(bounds.maxX))
            guard minX < maxX else { return 0 }
            let ink = (minX..<maxX).reduce(0) { $0 + (pixels.rgba(x: $1, y: y).alpha >= 128 ? 1 : 0) }
            return Double(ink) / Double(maxX - minX)
        }
    }

    @MainActor
    private func writeAsset(to url: URL, width: Int, height: Int, ink: CGRect) throws {
        let rowBytes = width * 4
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(ink)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    @MainActor
    func testCenterTextDigitsMatchWiFiAndBluetoothVisibleInkAcrossRenderScales() throws {
        let foreground = CGColor(gray: 1, alpha: 1)
        let critical = StatusIconRenderer.defaultCriticalColor
        let cases: [(String, CenterState)] = [
            ("text 8", .text(IconTextState(text: "8", color: .primary, scale: 1.8, normalizedSizePercentage: 1))),
            ("text 80", .text(IconTextState(text: "80", color: .primary, scale: 1.8, normalizedSizePercentage: 1))),
            ("text 100", .text(IconTextState(text: "100", color: .primary, scale: 1.8, normalizedSizePercentage: 1))),
            ("Wi-Fi", .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                                               color: .primary, scale: 1.3, normalizedSizePercentage: 1))),
            ("Bluetooth audio", .symbol(IconSymbolState(source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                                                         color: .primary, scale: 1.6, normalizedSizePercentage: 1)))
        ]

        // Exercise real menu-bar, preview, and Dock canvas sizes; normalize
        // measured raster pixels back into the renderer's 120-unit design space.
        let surfaces: [(name: String, size: CGFloat, backingScale: CGFloat)] = [
            ("menu bar", 28, 4), ("preview", 120, 2), ("Dock", 96, 2)
        ]
        for surface in surfaces {
            let environment = StatusIconRenderEnvironment(size: surface.size, scale: surface.backingScale,
                                                           foreground: foreground, criticalColor: critical)
            var normalizedHeights: [(String, CGFloat)] = []
            for (label, center) in cases {
                let scene = IconSceneState(center: center)
                let image = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment))
                let rendererScale = surface.size / 120 * surface.backingScale
                let halfCoverageHeight = try coverageBounds(image).height / rendererScale
                let fringeHeight = try alphaBounds(image).height / rendererScale
                print("CENTER_EDGE_METRICS source=\(label) surface=\(surface.name) alpha128=\(halfCoverageHeight) alphaNonzeroFringe=\(fringeHeight)")
                normalizedHeights.append((label, halfCoverageHeight))
            }
            let textHeights = normalizedHeights.filter { $0.0.hasPrefix("text ") }
            let references = normalizedHeights.filter { $0.0 == "Wi-Fi" || $0.0 == "Bluetooth audio" }
            // Two output pixels account for the raster-edge quantization of an
            // alpha bounding box; at menu scale this is still only ~2 design units.
            let tolerance = 2 * 120 / (surface.size * surface.backingScale) + 1e-6
            for (textLabel, textHeight) in textHeights {
                for (referenceLabel, referenceHeight) in references {
                    XCTAssertLessThanOrEqual(abs(textHeight - referenceHeight), tolerance,
                        "\(textLabel) must match \(referenceLabel) ink within \(tolerance) design units on \(surface.name); got \(textHeight) vs \(referenceHeight)")
                }
            }
        }
    }

    @MainActor
    func testCenterTextDigitsMatchWiFiAndBluetoothInProductionDockRaster() throws {
        let texts = ["8", "80", "100"]
        let sources: [(String, CenterState)] = [
            ("Wi-Fi", .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
                color: .primary, scale: 1.3, normalizedSizePercentage: 1
            ))),
            ("Bluetooth audio", .symbol(IconSymbolState(
                source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                color: .primary, scale: 1.6, normalizedSizePercentage: 1
            )))
        ]

        let sourceHeights = try sources.map { name, center in
            let image = try XCTUnwrap(DockIconRenderer.image(
                scene: IconSceneState(center: center), pixelLength: DockIconRenderer.pixelSize
            ))
            let cgImage = try XCTUnwrap((image.representations.first as? NSBitmapImageRep)?.cgImage)
            return (name, try whiteDockInkBounds(cgImage).height)
        }

        for text in texts {
            let center = CenterState.text(IconTextState(
                text: text, color: .primary, scale: 1.8, normalizedSizePercentage: 1
            ))
            let image = try XCTUnwrap(DockIconRenderer.image(
                scene: IconSceneState(center: center), pixelLength: DockIconRenderer.pixelSize
            ))
            let cgImage = try XCTUnwrap((image.representations.first as? NSBitmapImageRep)?.cgImage)
            let textHeight = try whiteDockInkBounds(cgImage).height

            for (sourceName, sourceHeight) in sourceHeights {
                XCTAssertLessThanOrEqual(abs(textHeight - sourceHeight), 2,
                    "Dock text \(text) must match \(sourceName) within two actual 512px raster pixels; got \(textHeight) vs \(sourceHeight)")
            }
        }
    }


    @MainActor
    private func whiteDockInkBounds(_ image: CGImage) throws -> CGRect {
        let pixels = try PixelBuffer(image: image)
        var minX = pixels.width, maxX = -1, minY = pixels.height, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let pixel = pixels.rgba(x: x, y: y)
                guard pixel.red >= 240, pixel.green >= 240, pixel.blue >= 240 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            throw NSError(domain: "IconSizingStandardTests", code: 4)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @MainActor
    func testMissingAssetUsesTheSameFallbackSymbolForSizingAndDrawing() throws {
        let environment = StatusIconRenderEnvironment(
            size: 120, scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-icon-sizing-\(UUID().uuidString).png")
        let scene = IconSceneState(center: .symbol(IconSymbolState(
            source: .image(url: missingURL, fallbackSymbol: "headphones"),
            color: .bluetooth,
            scale: 1,
            normalizedSizePercentage: 1
        )))

        let image = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment))
        XCTAssertEqual(try coverageBounds(image).height, 31.1, accuracy: 2,
                       "Missing-asset sizing must measure the exact symbol used by the renderer fallback.")
    }

    @MainActor
    func testVariableSymbolSizeMetricsStayPinnedToReferenceVariantAndParticipateInRenderIdentity() throws {
        let environment = StatusIconRenderEnvironment(
            size: 120, scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        func scene(_ value: Double) -> IconSceneState {
            IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: value, fallback: nil), color: .primary,
                scale: 1, normalizedSizePercentage: 1.2
            )))
        }
        let weak = scene(0.15)
        let strong = scene(0.9)
        XCTAssertNotEqual(weak, strong, "Live variable appearance remains scene input")
        XCTAssertNotEqual(DockIconRenderKey(scene: weak, backgroundStyle: .dark, pixelLength: 96),
                          DockIconRenderKey(scene: strong, backgroundStyle: .dark, pixelLength: 96))
        let weakImage = try XCTUnwrap(StatusIconRenderer.render(scene: weak, environment: environment))
        let strongImage = try XCTUnwrap(StatusIconRenderer.render(scene: strong, environment: environment))
        let weakCalibration = try XCTUnwrap(StatusIconRenderer.normalizedCenterCalibration(
            for: try XCTUnwrap(weak.center), percentage: 1.2, environment: environment
        ))
        let strongCalibration = try XCTUnwrap(StatusIconRenderer.normalizedCenterCalibration(
            for: try XCTUnwrap(strong.center), percentage: 1.2, environment: environment
        ))
        let repeatedWeakCalibration = try XCTUnwrap(StatusIconRenderer.normalizedCenterCalibration(
            for: try XCTUnwrap(weak.center), percentage: 1.2, environment: environment
        ))
        XCTAssertEqual(weakCalibration.identity, strongCalibration.identity,
                       "Both live variants use the shared variable=1 reference-calibration cache identity")
        XCTAssertEqual(weakCalibration.multiplier, strongCalibration.multiplier, accuracy: 1e-12,
                       "Variable appearance changes preserve the exact reference-calibrated multiplier")
        XCTAssertEqual(repeatedWeakCalibration.identity, weakCalibration.identity,
                       "Repeated renders at one output CTM reuse the calibration cache entry")
        XCTAssertEqual(repeatedWeakCalibration.multiplier, weakCalibration.multiplier, accuracy: 1e-12)
        XCTAssertFalse(try PixelBuffer(image: weakImage).bytes == PixelBuffer(image: strongImage).bytes)
    }

    @MainActor
    private func normalizedCenter(_ center: CenterState, percentage: Double) -> CenterState {
        switch center {
        case let .text(text):
            return .text(IconTextState(text: text.text, color: text.color, scale: text.scale,
                                       normalizedSizePercentage: percentage))
        case let .symbol(symbol):
            return .symbol(IconSymbolState(source: symbol.source, color: symbol.color, scale: symbol.scale,
                                           normalizedSizePercentage: percentage))
        }
    }

    private func coverageBounds(_ image: CGImage) throws -> CGRect {
        let pixels = try PixelBuffer(image: image)
        var minX = pixels.width, maxX = -1, minY = pixels.height, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.rgba(x: x, y: y).alpha >= 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw NSError(domain: "IconSizingStandardTests", code: 5) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func smallestInkComponentBounds(_ image: CGImage) throws -> CGRect {
        let pixels = try PixelBuffer(image: image)
        var visited = Set<Int>()
        var components: [CGRect] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let start = y * pixels.width + x
                guard !visited.contains(start), pixels.rgba(x: x, y: y).alpha >= 128 else { continue }
                var queue = [start]
                visited.insert(start)
                var head = 0
                var minX = x, maxX = x, minY = y, maxY = y
                while head < queue.count {
                    let index = queue[head]
                    head += 1
                    let px = index % pixels.width
                    let py = index / pixels.width
                    minX = min(minX, px); maxX = max(maxX, px)
                    minY = min(minY, py); maxY = max(maxY, py)
                    for ny in max(0, py - 1)...min(pixels.height - 1, py + 1) {
                        for nx in max(0, px - 1)...min(pixels.width - 1, px + 1) {
                            let neighbor = ny * pixels.width + nx
                            guard !visited.contains(neighbor), pixels.rgba(x: nx, y: ny).alpha >= 128 else { continue }
                            visited.insert(neighbor)
                            queue.append(neighbor)
                        }
                    }
                }
                components.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            }
        }
        guard let smallest = components.min(by: { $0.width * $0.height < $1.width * $1.height }) else {
            throw NSError(domain: "IconSizingStandardTests", code: 6)
        }
        return smallest
    }

    private func alphaBounds(_ image: CGImage) throws -> CGRect {
        guard let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else {
            throw NSError(domain: "IconSizingStandardTests", code: 1)
        }
        var minX = image.width, maxX = -1, minY = image.height, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where bytes[(y * image.width + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw NSError(domain: "IconSizingStandardTests", code: 2) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @MainActor
    private func writeTransparentMarginAsset() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("icon-sizing-\(UUID().uuidString).png")
        guard let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8,
                                      bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "IconSizingStandardTests", code: 3)
        }
        context.clear(CGRect(x: 0, y: 0, width: 40, height: 80))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 10, y: 20, width: 20, height: 40))
        let image = try XCTUnwrap(context.makeImage())
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url)
        return url
    }

    func testStrokeStandardKeepsLegacyThreeStyleEndpointsAndContinuousSteps() {
        XCTAssertEqual(IconStrokeSizingPolicy.interactiveScaleRange, 0.8...1.2)
        XCTAssertEqual(IconStrokeSizingPolicy.percentageStep, 0.05, accuracy: 1e-12)
        XCTAssertEqual(IconStrokeSizingPolicy.strokeScale(for: 0.8), 1.0, accuracy: 1e-12)
        XCTAssertEqual(IconStrokeSizingPolicy.strokeScale(for: 1.0), RingStrokeStyle.regular.scale, accuracy: 1e-12)
        XCTAssertEqual(IconStrokeSizingPolicy.strokeScale(for: 1.2), 1.5, accuracy: 1e-12)
        XCTAssertEqual(IconStrokeSizingPolicy.percentage(for: RingStrokeStyle.light.scale), 0.8, accuracy: 1e-12)
        XCTAssertEqual(IconStrokeSizingPolicy.percentage(for: RingStrokeStyle.bold.scale), 1.2, accuracy: 1e-12)
    }
}

private extension CenterState {
    var legacyScale: Double? {
        switch self {
        case let .symbol(symbol): symbol.scale
        case let .text(text): text.scale
        }
    }
}
