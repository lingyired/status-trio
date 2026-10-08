import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

@MainActor
struct Issue13IconParityTests {
    @Test(
        "Special Wi-Fi connection marks follow the Wi-Fi symbol scale",
        .bug("https://github.com/lingyired/status-trio/issues/13"),
        arguments: [WiFiState.temporary, .shared]
    )
    func specialWiFiConnectionMarksFollowSymbolScale(_ state: WiFiState) throws {
        let normal = try renderedPixels(for: state, wifiScale: 1.0)
        let scaled = try renderedPixels(for: state, wifiScale: 1.5)
        let wifiRegion = CGRect(x: 20, y: 20, width: 80, height: 80)
        let normalAlpha = normal.alphaSum(
            inSVGRect: wifiRegion,
            size: 20,
            scale: 8
        )
        let scaledAlpha = scaled.alphaSum(
            inSVGRect: wifiRegion,
            size: 20,
            scale: 8
        )

        #expect(scaledAlpha > normalAlpha, "\(state)")
    }

    @Test(
        "Dock icon reflects the continuous volume arc style",
        .bug("https://github.com/lingyired/status-trio/issues/13")
    )
    func dockIconReflectsVolumeArcStyle() throws {
        let status = MenuBarStatus(snapshot: StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        ))
        let dots = try dockPixels(
            for: status,
            volumeOptions: VolumeIconOptions(displayStyle: .dots)
        )
        let arc = try dockPixels(
            for: status,
            volumeOptions: VolumeIconOptions(displayStyle: .arc)
        )

        #expect(pixelsDiffer(dots, arc))
    }

    @Test(
        "Light Dock icons preserve the white body in custom connection cutouts",
        .bug("https://github.com/lingyired/status-trio/issues/13"),
        arguments: [
            (WiFiState.temporary, CGPoint(x: 59.5, y: 53.5)),
            (WiFiState.shared, CGPoint(x: 59.5, y: 65.0))
        ]
    )
    func dockLightStylePreservesCustomConnectionCutouts(
        _ state: WiFiState,
        cutoutPoint: CGPoint
    ) throws {
        let pixels = try dockPixels(
            for: MenuBarStatus(snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: state, rssi: -50),
                volume: .placeholder
            )),
            backgroundStyle: .light
        )
        let pixelPoint = dockPixelPoint(forSVGPoint: cutoutPoint)
        let pixel = pixels.rgba(x: pixelPoint.x, y: pixelPoint.y)

        #expect(pixel.alpha > 240, "\(state) should keep the light body")
        #expect(pixel.red > 240, "\(state) should keep the light body")
        #expect(pixel.green > 240, "\(state) should keep the light body")
        #expect(pixel.blue > 240, "\(state) should keep the light body")
    }

    @Test(
        "Inactive Wi-Fi status symbols keep the full foreground color",
        .bug("https://github.com/lingyired/status-trio/issues/13"),
        arguments: [
            (WiFiState.notAssociated, UInt8(50)),
            (.off, UInt8(120)),
            (.unavailable, UInt8(120)),
            (.noInternet, UInt8(120))
        ]
    )
    func inactiveWiFiStatusSymbolsKeepFullForeground(
        _ state: WiFiState,
        minimumAlpha: UInt8
    ) throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: state, rssi: nil),
            volume: .placeholder
        )
        let canonicalScene = IconPreviewScene.make(snapshot: snapshot, configuration: .standard)
        let image = try #require(render(scene: IconSceneState(center: canonicalScene.center)))
        let pixels = try PixelBuffer(image: image)

        #expect(centerPassesForegroundFloor(pixels, minimumAlpha: minimumAlpha), "\(state)")
    }

    @Test("Wi-Fi foreground floor rejects a missing or muted center")
    func wifiForegroundFloorRejectsMissingOrMutedCenter() throws {
        let missingPixels = try PixelBuffer(image: #require(render(scene: IconSceneState())))
        let mutedCenter = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 0, fallback: nil),
            color: .inactive,
            scale: 1
        )))
        let mutedPixels = try PixelBuffer(image: #require(render(scene: mutedCenter)))

        #expect(!centerPassesForegroundFloor(missingPixels, minimumAlpha: 120))
        #expect(!centerPassesForegroundFloor(mutedPixels, minimumAlpha: 120))
    }

    private func renderedPixels(
        for state: WiFiState,
        wifiScale: Double
    ) throws -> PixelBuffer {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: state, rssi: -50),
            volume: .placeholder
        )
        let image = try #require(renderMenuBarFixture(
                snapshot: snapshot,
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            connectionOptions: ConnectionIconOptions(wifiScale: wifiScale)
        ))
        return try PixelBuffer(image: image)
    }

    private func dockPixels(
        for status: MenuBarStatus,
        volumeOptions: VolumeIconOptions = .standard,
        backgroundStyle: DockIconBackgroundStyle = .dark
    ) throws -> PixelBuffer {
        let image = try #require(renderDockFixture(
                status: status,
            volumeOptions: volumeOptions,
            backgroundStyle: backgroundStyle
        ))
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try #require(representation.cgImage))
    }

    private func dockPixelPoint(forSVGPoint point: CGPoint) -> (x: Int, y: Int) {
        let pixelScale = CGFloat(DockIconRenderer.pixelSize) / 1024
        let glyphOrigin = CGPoint(x: 194.8, y: 171.84)
        let glyphScale = 672 * pixelScale / StatusIconGeometry.canvas.width
        return (
            x: Int((glyphOrigin.x * pixelScale + point.x * glyphScale).rounded()),
            y: Int((glyphOrigin.y * pixelScale + point.y * glyphScale).rounded())
        )
    }

    private func pixelsDiffer(_ lhs: PixelBuffer, _ rhs: PixelBuffer) -> Bool {
        lhs.bytes != rhs.bytes
    }

    private func pixels(from image: NSImage) throws -> PixelBuffer {
        let tiff = try #require(image.tiffRepresentation)
        let representation = try #require(NSBitmapImageRep(data: tiff))
        return try PixelBuffer(image: try #require(representation.cgImage))
    }

    private func maximumAlpha(in pixels: PixelBuffer) -> UInt8 {
        stride(from: 3, to: pixels.bytes.count, by: 4)
            .map { pixels.bytes[$0] }
            .max() ?? 0
    }

    private func centerPassesForegroundFloor(_ pixels: PixelBuffer, minimumAlpha: UInt8) -> Bool {
        var maximum: UInt8 = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let point = CGPoint(
                    x: (CGFloat(x) + 0.5) * 120 / CGFloat(pixels.width),
                    y: (CGFloat(y) + 0.5) * 120 / CGFloat(pixels.height)
                )
                guard CGRect(x: 30, y: 40, width: 60, height: 50).contains(point) else { continue }
                maximum = max(maximum, pixels.rgba(x: x, y: y).alpha)
            }
        }
        return maximum > minimumAlpha
    }

    private func render(scene: IconSceneState) -> CGImage? {
        StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: 16,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        )
    }
}
