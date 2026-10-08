import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusIconRendererTests: XCTestCase {
    func testRendererProducesExpectedPixelSize() throws {
        let image = try XCTUnwrap(renderMenuBarFixture(
            snapshot: .placeholder,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        ))

        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 40)
    }

    func testSceneRendererUsesLogicalSizeAndBackingScale() throws {
        let scene = IconSceneState(outerRing: OuterRingState(
            segments: [RingSegmentState(progress: 0.5, color: .primary)],
            gap: .closed
        ))
        let image = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        ))

        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 40)
        let nsImage = try XCTUnwrap(StatusIconRenderer.image(
            scene: scene,
            size: 20,
            scale: 2,
            appearance: nil
        ))
        XCTAssertEqual(nsImage.size, NSSize(width: 20, height: 20))
    }

    func testRendererRejectsNonPositiveSizeOrScale() {
        let snapshot = StatusSnapshot.placeholder
        let foreground = CGColor(gray: 1, alpha: 1)

        XCTAssertNil(renderMenuBarFixture(
            snapshot: snapshot,
            size: 0,
            scale: 2,
            foreground: foreground
        ))
        XCTAssertNil(renderMenuBarFixture(
            snapshot: snapshot,
            size: -1,
            scale: 2,
            foreground: foreground
        ))
        XCTAssertNil(renderMenuBarFixture(
            snapshot: snapshot,
            size: 20,
            scale: 0,
            foreground: foreground
        ))
        XCTAssertNil(renderMenuBarFixture(
            snapshot: snapshot,
            size: 20,
            scale: -1,
            foreground: foreground
        ))
    }

    func testForegroundStateDrawsRedPixels() throws {
        let red = try XCTUnwrap(CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [1, 0, 0, 1]
        ))
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: .placeholder,
                size: 20,
                scale: 2,
                foreground: red
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 1,
            green: 0,
            blue: 0,
            tolerance: 0.02,
            minimumAlpha: 0.9
        ))
    }

    func testChargingStateDrawsGreenPixels() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        )

        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 0.20,
            green: 0.78,
            blue: 0.35,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testChargingStateUsesDarkerGreenForLightMenuBar() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 50, isCharging: true),
            wifi: .placeholder,
            volume: .placeholder
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 0, alpha: 1)
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 31.0 / 255.0,
            green: 143.0 / 255.0,
            blue: 61.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testOffAndUnavailableStatesDrawSlashOutsideWiFiArcs() throws {
        let offSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .off, rssi: nil),
            volume: .placeholder
        )
        let unavailableSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .unavailable, rssi: nil),
            volume: .placeholder
        )
        let notAssociatedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .notAssociated, rssi: nil),
            volume: .placeholder
        )
        let offPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: offSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let unavailablePixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: unavailableSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let notAssociatedPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: notAssociatedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        XCTAssertEqual(offPixels.bytes, unavailablePixels.bytes)
        XCTAssertNotEqual(offPixels.bytes, notAssociatedPixels.bytes)
    }

    func testNoInternetOmitsNormalWiFiDotWhileKeepingOverlay() throws {
        let noInternetSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .noInternet, rssi: nil),
            volume: .placeholder
        )
        let notAssociatedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .notAssociated, rssi: nil),
            volume: .placeholder
        )
        let noInternetPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: noInternetSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let notAssociatedPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: notAssociatedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        XCTAssertNotEqual(noInternetPixels.bytes, notAssociatedPixels.bytes)
    }

    func testLowPowerStateDrawsYellowPixels() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: true,
                isConnectedToPower: false
            ),
            wifi: .placeholder,
            volume: .placeholder
        )

        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 0.95,
            green: 0.73,
            blue: 0.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testLowPowerStateUsesDarkerYellowForLightMenuBar() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 50, isLowPowerMode: true),
            wifi: .placeholder,
            volume: .placeholder
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 0, alpha: 1)
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 201.0 / 255.0,
            green: 151.0 / 255.0,
            blue: 0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }


    func testBatteryPercentageCanBeHidden() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 50),
            wifi: .placeholder,
            volume: .placeholder
        )
        let visible = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: true,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let hidden = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let valueRegion = CGRect(x: 45, y: 0, width: 30, height: 34)

        XCTAssertGreaterThan(
            visible.alphaSum(inSVGRect: valueRegion, size: 20, scale: 8),
            hidden.alphaSum(inSVGRect: valueRegion, size: 20, scale: 8)
        )
    }

    func testBatteryPercentageFollowsForegroundColor() throws {
        let batteries = [
            makeBattery(rawPercentage: 50),
            makeBattery(rawPercentage: 50, isLowPowerMode: true),
            makeBattery(rawPercentage: 19)
        ]

        for battery in batteries {
            let pixels = try PixelBuffer(
                image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: StatusSnapshot(
                        battery: battery,
                        wifi: .placeholder,
                        volume: .placeholder
                    ),
                    size: 20,
                    scale: 8,
                    foreground: CGColor(gray: 0, alpha: 1)
                ))
            )

            XCTAssertTrue(pixels.containsColor(
                red: 0,
                green: 0,
                blue: 0,
                tolerance: 0.08,
                minimumAlpha: 0.9
            ))
            XCTAssertFalse(pixels.containsColor(
                red: 1,
                green: 1,
                blue: 1,
                tolerance: 0.08,
                minimumAlpha: 0.9
            ))
        }
    }

    func testChargingIndicatorCanBeHidden() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 50, isCharging: true),
            wifi: .placeholder,
            volume: .placeholder
        )
        let visible = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let hidden = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: false,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let boltRegion = CGRect(x: 50, y: 0, width: 20, height: 23)

        XCTAssertGreaterThan(
            visible.alphaSum(inSVGRect: boltRegion, size: 20, scale: 8),
            hidden.alphaSum(inSVGRect: boltRegion, size: 20, scale: 8)
        )
    }

    func testBatteryPercentageScaleChangesRenderedSize() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 50),
            wifi: .placeholder,
            volume: .placeholder
        )
        let small = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: true,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20,
                    textScale: 1
                )
            ))
        )
        let large = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: true,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20,
                    textScale: 2
                )
            ))
        )
        let valueRegion = CGRect(x: 35, y: 0, width: 50, height: 45)

        XCTAssertGreaterThan(
            large.alphaSum(inSVGRect: valueRegion, size: 20, scale: 8),
            small.alphaSum(inSVGRect: valueRegion, size: 20, scale: 8)
        )
    }

    func testConnectedToPowerWithoutActiveChargingShowsBolt() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(
                rawPercentage: 80,
                isCharging: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        )
        let withBolt = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let withoutBolt = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: false,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let markerRegion = CGRect(x: 45, y: 0, width: 30, height: 34)
        XCTAssertGreaterThan(
            withBolt.alphaSum(inSVGRect: markerRegion, size: 20, scale: 8),
            withoutBolt.alphaSum(inSVGRect: markerRegion, size: 20, scale: 8)
        )
    }

    func testBoltScaleTracksBatterySymbolScale() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(
                rawPercentage: 80,
                isCharging: true,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        )
        let small = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20,
                    textScale: 1
                )
            ))
        )
        let large = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20,
                    textScale: 2
                )
            ))
        )
        let boltRegion = CGRect(x: 40, y: 0, width: 40, height: 40)

        XCTAssertGreaterThan(
            large.alphaSum(inSVGRect: boltRegion, size: 20, scale: 8),
            small.alphaSum(inSVGRect: boltRegion, size: 20, scale: 8)
        )
    }

    func testChargingBoltFollowsForegroundColor() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 50, isCharging: true),
            wifi: .placeholder,
            volume: .placeholder
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 0, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: false,
                    showsChargingIndicator: true,
                    usesStatusColors: false,
                    criticalThreshold: 20
                )
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 0,
            green: 0,
            blue: 0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
        XCTAssertFalse(pixels.containsColor(
            red: 1,
            green: 1,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testBatteryStatusColorsCanBeDisabled() throws {
        let snapshot = StatusSnapshot(
            battery: makeBattery(rawPercentage: 19),
            wifi: .placeholder,
            volume: .placeholder
        )
        let colored = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 4,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: true,
                    showsChargingIndicator: true,
                    usesStatusColors: true,
                    criticalThreshold: 20
                )
            ))
        )
        let monochrome = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 4,
                foreground: CGColor(gray: 1, alpha: 1),
                options: BatteryIconOptions(
                    showsPercentage: true,
                    showsChargingIndicator: true,
                    usesStatusColors: false,
                    criticalThreshold: 20
                )
            ))
        )

        XCTAssertTrue(colored.containsColor(
            red: 1,
            green: 0.23,
            blue: 0.19,
            tolerance: 0.14,
            minimumAlpha: 0.9
        ))
        XCTAssertFalse(monochrome.containsColor(
            red: 1,
            green: 0.23,
            blue: 0.19,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testAppKitWrapperProducesBitmapRepresentation() throws {
        let image = menuBarFixtureImage(
            snapshot: .placeholder,
            size: 28
        )

        XCTAssertEqual(image.size.width, 28, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 28, accuracy: 0.01)

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    func testSceneBackedWiFiPreviewUsesRequestedSizeAndRasterRepresentation() throws {
        let image = menuBarFixtureImage(
            snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -55),
                volume: .placeholder
            ),
            size: 22
        )

        XCTAssertEqual(image.size.width, 22, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 22, accuracy: 0.01)
        XCTAssertFalse(image.isTemplate)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testSceneBackedWiFiPreviewKeepsTransparentBorderAroundStrokes() throws {
        let centerOnlyWiFiScene = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
            color: .primary,
            scale: 1
        )))
        let image = try XCTUnwrap(StatusIconRenderer.image(
            scene: centerOnlyWiFiScene,
            size: 16,
            scale: 2
        ))
        let pixels = try renderPixels(image: image)

        // SF Symbols releases vary by a few anti-aliased alpha levels at the bitmap edge.
        XCTAssertLessThanOrEqual(pixels.maximumAlphaOnEdges, 4)
    }

    func testConnectedZeroBarsUsesMutedSignalWhileNotAssociatedUsesFullForeground() throws {
        let zeroBars = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: nil),
            volume: .placeholder
        )
        let notAssociated = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .notAssociated, rssi: nil),
            volume: .placeholder
        )
        let oneBar = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -85),
            volume: .placeholder
        )
        let twoBars = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -75),
            volume: .placeholder
        )
        let threeBars = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: .placeholder
        )

        let zeroPixels = try renderPixels(zeroBars)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(notAssociated).bytes)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(oneBar).bytes)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(twoBars).bytes)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(threeBars).bytes)
    }

    func testConnectedNonzeroSignalAlphaSumIncreasesWithBars() throws {
        let rssiValues: [Int?] = [-85, -75, -55]
        let signalRegion = CGRect(x: 35, y: 43, width: 50, height: 43)
        var alphaSums: [Int] = []

        for rssi in rssiValues {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: rssi),
                volume: .placeholder
            )
            let pixels = try renderPixels(snapshot)
            alphaSums.append(pixels.alphaSum(
                inSVGRect: signalRegion,
                size: 20,
                scale: 8
            ))
        }

        for index in 0..<(alphaSums.count - 1) {
            XCTAssertLessThan(alphaSums[index], alphaSums[index + 1])
        }
    }

    func testConnectedLowSignalRendersInactiveTrackWithMutedAlpha() throws {
        let oneBar = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -85),
            volume: .placeholder
        )
        let outerArcRegion = CGRect(x: 35, y: 43, width: 50, height: 18)
        let pixels = try renderPixels(oneBar)
        let outerAlpha = pixels.alphaSum(
            inSVGRect: outerArcRegion,
            size: 20,
            scale: 8
        )
        // Outer arc is not active at 1 bar, but must be rendered in muted track color (> 0 alpha)
        XCTAssertGreaterThan(outerAlpha, 0)
    }

    func testRendererResolvesForegroundForEachDrawingAppearance() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: .placeholder
        )
        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAqua = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let image = menuBarFixtureImage(
            snapshot: snapshot,
            size: 20
        )
        let aquaPixels = try renderPixels(image: image, appearance: aqua)
        let darkAquaPixels = try renderPixels(image: image, appearance: darkAqua)
        let aquaLuminance = try XCTUnwrap(aquaPixels.averageOpaqueLuminance())
        let darkAquaLuminance = try XCTUnwrap(darkAquaPixels.averageOpaqueLuminance())

        XCTAssertLessThan(aquaLuminance, 0.4)
        XCTAssertGreaterThan(darkAquaLuminance, 0.55)
        XCTAssertGreaterThan(darkAquaLuminance - aquaLuminance, 0.25)
    }

    func testHotspotOverlayPointIsUnique() throws {
        let hotspotSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .hotspot, rssi: nil),
            volume: .placeholder
        )
        let connectedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: .placeholder
        )
        let hotspotPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: hotspotSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let connectedPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: connectedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let wifiArea = CGRect(x: 35, y: 35, width: 50, height: 50)
        XCTAssertGreaterThan(
            hotspotPixels.alphaSum(inSVGRect: wifiArea, size: 20, scale: 8),
            0
        )
        XCTAssertNotEqual(hotspotPixels.bytes, connectedPixels.bytes)
    }

    func testEthernetConnectionDrawsThreeDotMark() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .ethernet,
            volume: .placeholder
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 16,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        for dot in StatusIconGeometry.ethernetDots() {
            XCTAssertGreaterThan(
                pixels.alpha(atSVGPoint: dot, size: 20, scale: 16),
                230
            )
        }
    }

    func testEthernetConnectionDrawsAFullWiFiIconWhateverTheWiFiSignalIs() throws {
        // "Use Wi-Fi icon for Ethernet" is a look, not a reading: the link is a
        // cable, so there is no signal for the icon to report. Borrowing the
        // Wi-Fi radio's bar count used to make this icon go flat and grey with
        // Wi-Fi off, and move whenever the Wi-Fi signal did.
        let fullWiFiSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            volume: .placeholder
        )
        let fullWiFiPixels = try renderPixels(fullWiFiSnapshot)

        let signals: [WiFiStatus] = [
            WiFiStatus(state: .hotspot, rssi: -55),
            WiFiStatus(state: .connected, rssi: -75),
            WiFiStatus(state: .notAssociated, rssi: nil)
        ]
        for wifi in signals {
            let ethernetPixels = try renderPixels(
                StatusSnapshot(
                    battery: .placeholder,
                    wifi: wifi,
                    connection: .ethernet,
                    volume: .placeholder
                ),
                connectionOptions: ConnectionIconOptions(
                    showsWiFiIconForEthernet: true
                )
            )

            XCTAssertEqual(
                ethernetPixels.bytes,
                fullWiFiPixels.bytes,
                "\(wifi.state) should still draw a full Wi-Fi icon on a cable"
            )
        }
    }

    func testWiFiIconOptionsReplaceEachSpecialConnectionMark() throws {
        let cases: [(WiFiState, ConnectionIconOptions)] = [
            (
                .hotspot,
                ConnectionIconOptions(showsWiFiIconForHotspot: true)
            ),
            (
                .temporary,
                ConnectionIconOptions(showsWiFiIconForTemporaryConnection: true)
            ),
            (
                .shared,
                ConnectionIconOptions(showsWiFiIconForInternetSharing: true)
            )
        ]
        let standardWiFiPixels = try renderPixels(
            StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -55),
                volume: .placeholder
            )
        )

        for (state, connectionOptions) in cases {
            let pixels = try renderPixels(
                StatusSnapshot(
                    battery: .placeholder,
                    wifi: WiFiStatus(state: state, rssi: -55),
                    volume: .placeholder
                ),
                connectionOptions: connectionOptions
            )

            XCTAssertEqual(pixels.bytes, standardWiFiPixels.bytes, "\(state)")
        }
    }

    func testWiFiIconOptionUsesMutedFullSignalWhenRSSIIsMissing() throws {
        let specialPixels = try renderPixels(
            StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .hotspot, rssi: nil),
                volume: .placeholder
            ),
            connectionOptions: ConnectionIconOptions(showsWiFiIconForHotspot: true)
        )
        let standardPixels = try renderPixels(
            StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: nil),
                volume: .placeholder
            )
        )

        XCTAssertEqual(specialPixels.bytes, standardPixels.bytes)
    }

    func testTemporaryAndSharedStatesRenderExpectedSizeAndMasks() throws {
        let temporarySnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .temporary, rssi: -50),
            volume: .placeholder
        )
        let sharedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .shared, rssi: -50),
            volume: .placeholder
        )
        let connectedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            volume: .placeholder
        )

        let temporaryImage = try XCTUnwrap(renderMenuBarFixture(
            snapshot: temporarySnapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        ))
        let sharedImage = try XCTUnwrap(renderMenuBarFixture(
            snapshot: sharedSnapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        ))

        XCTAssertEqual(temporaryImage.width, 40)
        XCTAssertEqual(temporaryImage.height, 40)
        XCTAssertEqual(sharedImage.width, 40)
        XCTAssertEqual(sharedImage.height, 40)

        let pixelScale: CGFloat = 16
        let temporaryPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: temporarySnapshot,
                size: 20,
                scale: pixelScale,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let sharedPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: sharedSnapshot,
                size: 20,
                scale: pixelScale,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let connectedPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: connectedSnapshot,
                size: 20,
                scale: pixelScale,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let outerEdgePoint = CGPoint(x: 59.5, y: 50.5)

        XCTAssertGreaterThan(
            temporaryPixels.alpha(atSVGPoint: outerEdgePoint, size: 20, scale: pixelScale),
            0
        )
        XCTAssertGreaterThan(
            sharedPixels.alpha(atSVGPoint: outerEdgePoint, size: 20, scale: pixelScale),
            0
        )
        XCTAssertGreaterThan(
            temporaryPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 59.5),
                size: 20,
                scale: pixelScale
            ),
            0
        )
        XCTAssertEqual(
            temporaryPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 53.5),
                size: 20,
                scale: pixelScale
            ),
            0
        )
        XCTAssertEqual(
            temporaryPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 68.5),
                size: 20,
                scale: pixelScale
            ),
            0
        )
        XCTAssertEqual(
            sharedPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 72),
                size: 20,
                scale: pixelScale
            ),
            0
        )

        let volumeRegion = CGRect(x: 25, y: 92, width: 75, height: 28)
        let connectedVolumeAlpha = connectedPixels.alphaSum(
            inSVGRect: volumeRegion,
            size: 20,
            scale: pixelScale
        )
        XCTAssertEqual(
            temporaryPixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: pixelScale
            ),
            connectedVolumeAlpha
        )
        XCTAssertEqual(
            sharedPixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: pixelScale
            ),
            connectedVolumeAlpha
        )
        XCTAssertNotEqual(temporaryPixels.bytes, sharedPixels.bytes)
    }

    func testVolumeAlphaSumIncreasesWithVisibleDots() throws {
        let scalars = [0.0, 0.25, 0.50, 0.75, 1.0]
        let volumeRegion = CGRect(x: 25, y: 92, width: 75, height: 28)
        var alphaSums: [Int] = []

        for scalar in scalars {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: VolumeStatus(
                    scalar: scalar,
                    isMuted: false,
                    deviceName: nil
                )
            )
            let pixels = try PixelBuffer(
                image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                    size: 20,
                    scale: 8,
                    foreground: CGColor(gray: 1, alpha: 1)
                ))
            )
            alphaSums.append(pixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: 8
            ))
        }

        for index in 0..<(alphaSums.count - 1) {
            XCTAssertLessThan(alphaSums[index], alphaSums[index + 1])
        }
    }

    func testVolumeContinuousArcAlphaSumIncreasesWithVolume() throws {
        let scalars = [0.0, 0.25, 0.50, 0.75, 1.0]
        let volumeRegion = CGRect(x: 25, y: 92, width: 75, height: 28)
        var alphaSums: [Int] = []

        let arcOptions = VolumeIconOptions(displayStyle: .arc)

        for scalar in scalars {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: VolumeStatus(
                    scalar: scalar,
                    isMuted: false,
                    deviceName: nil
                )
            )
            let pixels = try PixelBuffer(
                image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                    size: 20,
                    scale: 8,
                    foreground: CGColor(gray: 1, alpha: 1),
                    volumeOptions: arcOptions
                ))
            )
            alphaSums.append(pixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: 8
            ))
        }

        for index in 0..<(alphaSums.count - 1) {
            XCTAssertLessThan(alphaSums[index], alphaSums[index + 1])
        }
    }

    func testVolumeArcStyleDiffersFromDotsStyle() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )
        let dotsPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                volumeOptions: VolumeIconOptions(displayStyle: .dots)
            ))
        )
        let arcPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                volumeOptions: VolumeIconOptions(displayStyle: .arc)
            ))
        )
        XCTAssertNotEqual(dotsPixels.bytes, arcPixels.bytes)
    }

    func testWiFiSymbolScaleChangesRenderedPixels() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            volume: .placeholder
        )
        let normalPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                connectionOptions: ConnectionIconOptions(wifiScale: 1.0)
            ))
        )
        let scaledPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                connectionOptions: ConnectionIconOptions(wifiScale: 1.5)
            ))
        )
        let wifiRegion = CGRect(x: 20, y: 20, width: 80, height: 80)
        let normalSum = normalPixels.alphaSum(inSVGRect: wifiRegion, size: 20, scale: 8)
        let scaledSum = scaledPixels.alphaSum(inSVGRect: wifiRegion, size: 20, scale: 8)
        XCTAssertGreaterThan(scaledSum, normalSum)
        XCTAssertNotEqual(normalPixels.bytes, scaledPixels.bytes)
    }

    func testCenterSymbolScaleUsesTheSharedBasePointSize() {
        XCTAssertEqual(StatusIconRenderer.centerSymbolBasePointSize, 38)
        XCTAssertEqual(StatusIconRenderer.centerSymbolPointSize(for: 1.0), 38)
        XCTAssertEqual(
            StatusIconRenderer.centerSymbolPointSize(for: 1.6),
            60.8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StatusIconRenderer.centerSymbolPointSize(for: 1.8),
            68.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StatusIconRenderer.centerSymbolPointSize(for: 0),
            StatusIconRenderer.centerSymbolBasePointSize
        )
    }

    func testMutedVolumeMatchesZeroVolume() throws {
        let zeroSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0, isMuted: false, deviceName: nil)
        )
        let mutedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.8, isMuted: true, deviceName: nil)
        )
        let zeroPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: zeroSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let mutedPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: mutedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        XCTAssertEqual(mutedPixels.bytes, zeroPixels.bytes)
    }

    func testBluetoothOutputReplacesNetworkIconWithBluePixels() throws {
        let snapshot = bluetoothAudioSnapshot(volumeScalar: 0.5)
        let standard = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let bluetooth = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true
                )
            ))
        )

        XCTAssertNotEqual(standard.bytes, bluetooth.bytes)
        XCTAssertTrue(bluetooth.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    /// The picker mode draws the picked device's glyph with no current audio
    /// output at all — the state the mode mostly runs in, and the one the
    /// original rule could never reach.
    func testNetworkIconOverrideReplacesNetworkIconWithoutAnyAudioOutput() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )
        let standard = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let overridden = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    networkIconSymbolOverride: "keyboard"
                )
            ))
        )

        XCTAssertNotEqual(standard.bytes, overridden.bytes)
        XCTAssertTrue(overridden.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    /// A symbol the running system does not ship must not blank the icon: the
    /// fallback is the generic Bluetooth glyph, still in the Bluetooth blue.
    func testNetworkIconOverrideFallsBackToTheGenericGlyphForUnknownSymbols() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )
        let known = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    networkIconSymbolOverride: "keyboard"
                )
            ))
        )
        let unknown = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    networkIconSymbolOverride: "statustrio.nonexistent.symbol"
                )
            ))
        )

        // Both draw something blue, and the fallback is not the known glyph.
        for buffer in [known, unknown] {
            XCTAssertTrue(buffer.containsColor(
                red: 77.0 / 255.0,
                green: 163.0 / 255.0,
                blue: 1,
                tolerance: 0.08,
                minimumAlpha: 0.9
            ))
        }
        XCTAssertNotEqual(known.bytes, unknown.bytes)
    }

    /// The connection-slot setting replaces whatever the slot would draw — the
    /// Wi-Fi glyph here — with the battery percentage, and it does so without
    /// touching the top battery indicator, which the same snapshot draws too.
    func testBatteryPercentageInConnectionSlotReplacesTheNetworkGlyph() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 79,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )

        let standard = try renderPixels(snapshot)
        let slotPercentage = try renderPixels(
            snapshot,
            connectionOptions: ConnectionIconOptions(
                showsBatteryPercentageInConnectionSlot: true
            )
        )

        XCTAssertNotEqual(standard.bytes, slotPercentage.bytes)
    }

    /// The slot keeps drawing the connection glyph when the machine reports no
    /// battery at all, so a desktop Mac cannot end up with an empty middle.
    func testBatteryPercentageInConnectionSlotFallsBackWhenBatteryIsAbsent() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: nil,
                isPresent: false,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )

        let standard = try renderPixels(snapshot)
        let slotPercentage = try renderPixels(
            snapshot,
            connectionOptions: ConnectionIconOptions(
                showsBatteryPercentageInConnectionSlot: true
            )
        )

        XCTAssertEqual(standard.bytes, slotPercentage.bytes)
    }

    /// The slot percentage wins over a picked Bluetooth symbol, which is the
    /// ordering the settings subtitle promises ("replaces the Wi-Fi or
    /// connection symbol", independent of the top indicator).
    func testBatteryPercentageInConnectionSlotWinsOverPickedNetworkSymbol() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 79,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )
        let pickedSymbol = BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: "keyboard"
        )

        let symbolOnly = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: pickedSymbol
            ))
        )
        let withSlotPercentage = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                connectionOptions: ConnectionIconOptions(
                    showsBatteryPercentageInConnectionSlot: true
                ),
                bluetoothAudioOptions: pickedSymbol
            ))
        )

        XCTAssertNotEqual(symbolOnly.bytes, withSlotPercentage.bytes)
        // The picked symbol is Bluetooth blue; the slot draws in the
        // foreground, so its blue must be gone.
        XCTAssertTrue(symbolOnly.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
        XCTAssertFalse(withSlotPercentage.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testBluetoothOutputUsesDarkerBlueForLightMenuBar() throws {
        let snapshot = bluetoothAudioSnapshot(volumeScalar: 0.5)
        let bluetooth = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 0, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true
                )
            ))
        )

        XCTAssertTrue(bluetooth.containsColor(
            red: 0,
            green: 102.0 / 255.0,
            blue: 204.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testNetworkErrorPriorityKeepsNetworkIconInsteadOfBluetooth() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .noInternet, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "AirPods Pro",
                currentDevice: bluetoothOutputDevice(name: "AirPods Pro")
            )
        )
        let standard = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    prioritizesNetworkErrors: false
                )
            ))
        )
        let networkPriority = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    prioritizesNetworkErrors: true
                )
            ))
        )

        XCTAssertNotEqual(standard.bytes, networkPriority.bytes)
        XCTAssertFalse(networkPriority.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.04,
            minimumAlpha: 0.9
        ))
    }

    func testBluetoothOutputColorsActiveVolumeDotsBlue() throws {
        let snapshot = bluetoothAudioSnapshot(volumeScalar: 0.25)
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                volumeOptions: VolumeIconOptions(displayStyle: .dots),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    usesVolumeColor: true
                )
            ))
        )
        let dots = StatusIconGeometry.volumeDots()
        let active = pixels.rgba(atSVGPoint: dots[0], size: 20, scale: 8)
        let inactive = pixels.rgba(atSVGPoint: dots[1], size: 20, scale: 8)

        XCTAssertGreaterThanOrEqual(active.alpha, 245)
        XCTAssertEqual(active.red, 92, accuracy: 8)
        XCTAssertEqual(active.green, 180, accuracy: 30)
        XCTAssertEqual(active.blue, 255, accuracy: 8)
        XCTAssertEqual(inactive.red, 56, accuracy: 8)
        XCTAssertEqual(inactive.green, 56, accuracy: 8)
        XCTAssertEqual(inactive.blue, 56, accuracy: 8)
        XCTAssertEqual(inactive.alpha, 56, accuracy: 3)
    }

    func testBluetoothOutputColorsActiveVolumeArcBlue() throws {
        let snapshot = bluetoothAudioSnapshot(volumeScalar: 0.75)
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                volumeOptions: VolumeIconOptions(displayStyle: .arc),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    usesVolumeColor: true
                )
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testBluetoothSymbolScaleChangesRenderedPixels() throws {
        let snapshot = bluetoothAudioSnapshot(volumeScalar: 0.5)
        let normalPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    symbolScale: 1.0
                )
            ))
        )
        let scaledPixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    symbolScale: 1.5
                )
            ))
        )
        let bluetoothRegion = CGRect(x: 20, y: 20, width: 80, height: 80)
        let normalSum = normalPixels.alphaSum(
            inSVGRect: bluetoothRegion,
            size: 20,
            scale: 8
        )
        let scaledSum = scaledPixels.alphaSum(
            inSVGRect: bluetoothRegion,
            size: 20,
            scale: 8
        )

        XCTAssertGreaterThan(scaledSum, normalSum)
        XCTAssertNotEqual(normalPixels.bytes, scaledPixels.bytes)
    }

    func testZeroVolumeDrawsFourHiddenDots() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0, isMuted: false, deviceName: nil)
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let expectedAlpha = 0.22 * 255.0

        for point in StatusIconGeometry.volumeDots() {
            let alpha = Double(pixels.alpha(atSVGPoint: point, size: 20, scale: 8))
            XCTAssertEqual(alpha, expectedAlpha, accuracy: 2)
        }
    }

    /// Only the battery ring width varies; the volume options stay on the
    /// regular width, so this fails if the battery multiplier regresses on its
    /// own.
    func testRingStrokeStyleChangesMenuBarBatteryRingPixels() throws {
        let snapshot = StatusSnapshot.placeholder
        let foreground = CGColor(gray: 1, alpha: 1)
        let regularVolume = VolumeIconOptions(
            displayStyle: .dots,
            ringStrokeScale: RingStrokeStyle.regular.scale
        )

        let lightPixels = try menuBarPixels(
            snapshot: snapshot,
            foreground: foreground,
            options: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.light.scale),
            volumeOptions: regularVolume
        )
        let boldPixels = try menuBarPixels(
            snapshot: snapshot,
            foreground: foreground,
            options: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale),
            volumeOptions: regularVolume
        )

        XCTAssertNotEqual(lightPixels.bytes, boldPixels.bytes)
    }

    /// Only the discrete volume dots vary; the battery ring stays on the regular
    /// width.
    func testRingStrokeStyleChangesMenuBarVolumeDotPixels() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: nil)
        )
        let foreground = CGColor(gray: 1, alpha: 1)
        let regularBattery = BatteryIconOptions(ringStrokeScale: RingStrokeStyle.regular.scale)

        let lightPixels = try menuBarPixels(
            snapshot: snapshot,
            foreground: foreground,
            options: regularBattery,
            volumeOptions: VolumeIconOptions(
                displayStyle: .dots,
                ringStrokeScale: RingStrokeStyle.light.scale
            )
        )
        let boldPixels = try menuBarPixels(
            snapshot: snapshot,
            foreground: foreground,
            options: regularBattery,
            volumeOptions: VolumeIconOptions(
                displayStyle: .dots,
                ringStrokeScale: RingStrokeStyle.bold.scale
            )
        )

        XCTAssertNotEqual(lightPixels.bytes, boldPixels.bytes)
    }

    /// Only the continuous volume arc varies; the battery ring stays on the
    /// regular width.
    func testRingStrokeStyleChangesMenuBarVolumeArcPixels() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: nil)
        )
        let foreground = CGColor(gray: 1, alpha: 1)
        let regularBattery = BatteryIconOptions(ringStrokeScale: RingStrokeStyle.regular.scale)

        let regularPixels = try menuBarPixels(
            snapshot: snapshot,
            foreground: foreground,
            options: regularBattery,
            volumeOptions: VolumeIconOptions(
                displayStyle: .arc,
                ringStrokeScale: RingStrokeStyle.regular.scale
            )
        )
        let boldPixels = try menuBarPixels(
            snapshot: snapshot,
            foreground: foreground,
            options: regularBattery,
            volumeOptions: VolumeIconOptions(
                displayStyle: .arc,
                ringStrokeScale: RingStrokeStyle.bold.scale
            )
        )

        XCTAssertNotEqual(regularPixels.bytes, boldPixels.bytes)
    }

    private func menuBarPixels(
        snapshot: StatusSnapshot,
        foreground: CGColor,
        options: BatteryIconOptions,
        volumeOptions: VolumeIconOptions
    ) throws -> PixelBuffer {
        try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: foreground,
                options: options,
                volumeOptions: volumeOptions
            ))
        )
    }

    private func makeBattery(
        rawPercentage: Int,
        isCharging: Bool = false,
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool? = nil
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: rawPercentage,
            isPresent: true,
            isCharging: isCharging,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isConnectedToPower ?? isCharging
        )
    }

    /// The menu bar has to draw the glyph macOS declares for the device's own
    /// product ID. AirPods (2nd generation, A2031/A2032) reports 0x200F, so a
    /// renamed device still draws the AirPods glyph instead of a headphone one.
    func testBluetoothIconUsesTheAirPodsProductIDNotTheName() throws {
        let namedAirPods = try bluetoothPixels(deviceName: "AirPods", modelUID: nil)
        let renamedAirPods = try bluetoothPixels(deviceName: "小王的耳机", modelUID: "200f 4c")
        let renamedWithoutProductID = try bluetoothPixels(deviceName: "小王的耳机", modelUID: nil)

        // The product ID, not the name, decides the glyph.
        XCTAssertEqual(namedAirPods.bytes, renamedAirPods.bytes)
        XCTAssertNotEqual(renamedWithoutProductID.bytes, renamedAirPods.bytes)
    }

    private func bluetoothPixels(deviceName: String, modelUID: String?) throws -> PixelBuffer {
        let snapshot = StatusSnapshot(
                    battery: .placeholder,
                    wifi: WiFiStatus(state: .connected, rssi: -55),
                    connection: .wifi,
                    volume: VolumeStatus(
                        scalar: 0.5,
                        isMuted: false,
                        deviceName: deviceName,
                        currentDevice: bluetoothOutputDevice(
                            name: deviceName,
                            modelUID: modelUID
                        )
                    )
                )
        let audioIcon = IconPresentationResourceResolver.inputs(snapshot: snapshot).audioIcon
        return try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
                snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                bluetoothAudioOptions: BluetoothAudioIconOptions(replacesNetworkIcon: true),
                inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: audioIcon)
            ))
        )
    }

    private func bluetoothAudioSnapshot(volumeScalar: Double) -> StatusSnapshot {
        StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: volumeScalar,
                isMuted: false,
                deviceName: "AirPods Pro",
                currentDevice: bluetoothOutputDevice(name: "AirPods Pro")
            )
        )
    }

    private func bluetoothOutputDevice(name: String, modelUID: String? = nil) -> AudioOutputDevice {
        AudioOutputDevice(
            id: 42,
            name: name,
            uid: "bluetooth-output",
            isCurrent: true,
            volume: 0.5,
            transport: .bluetooth,
            modelUID: modelUID
        )
    }

    private func renderPixels(_ snapshot: StatusSnapshot) throws -> PixelBuffer {
        try renderPixels(snapshot, connectionOptions: .standard)
    }

    private func renderPixels(
        _ snapshot: StatusSnapshot,
        connectionOptions: ConnectionIconOptions
    ) throws -> PixelBuffer {
        try PixelBuffer(
            image: try XCTUnwrap(renderMenuBarFixture(
            snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1),
                connectionOptions: connectionOptions
            ))
        )
    }

    private func renderPixels(image: NSImage) throws -> PixelBuffer {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            data: try XCTUnwrap(image.tiffRepresentation)
        ))
        return try PixelBuffer(
            image: try XCTUnwrap(bitmap.cgImage)
        )
    }

    private func renderPixels(
        image: NSImage,
        appearance: NSAppearance
    ) throws -> PixelBuffer {
        let width = Int(image.size.width.rounded(.up))
        let height = Int(image.size.height.rounded(.up))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = image.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()

        return try PixelBuffer(image: try XCTUnwrap(bitmap.cgImage))
    }
}
