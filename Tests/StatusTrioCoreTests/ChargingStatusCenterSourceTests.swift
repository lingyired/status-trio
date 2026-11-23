import AppKit
import CoreGraphics
import CryptoKit
import Testing
@testable import StatusTrioCore

/// #253: the "charging status inside the ring" middle-icon source draws the
/// battery/charging status in the centre slot. While on battery the level
/// percentage sits in the centre and the ring closes (drawn once); while
/// charging / on power the centre shows the bolt or plug and the top gap keeps
/// the level percentage visible, so the number is never lost. These tests lock
/// the raster consequences the mapper alone cannot: the vector charge glyphs
/// must land on the ring centre, the ring's top gap must open or close by state,
/// and the Dock's static/effect split must stay on the same scene.
@MainActor
struct ChargingStatusCenterSourceTests {
    private let size: CGFloat = 120
    private let scale: CGFloat = 2
    private let white = CGColor(gray: 1, alpha: 1)
    private var ringCentre: CGPoint {
        CGPoint(x: StatusIconGeometry.artworkCenterX, y: StatusIconGeometry.batteryCenterY)
    }

    // MARK: - Fixtures

    private func battery(_ percentage: Int, charging: Bool, charged: Bool,
                         connected: Bool) -> BatteryStatus {
        BatteryStatus(rawPercentage: percentage, isPresent: true, isCharging: charging,
                      isCharged: charged, isLowPowerMode: false,
                      isConnectedToPower: connected)
    }

    private func snapshot(_ battery: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(
            battery: battery,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: nil)
        )
    }

    private func scene(
        _ snapshot: StatusSnapshot,
        source: ConnectionCenterSource = .chargingStatus,
        batteryOptions: BatteryIconOptions = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: batteryOptions,
                connection: ConnectionIconOptions(
                    centerSource: source,
                    prioritizesNetworkErrors: false,
                    wifiScale: 1
                ),
                volume: .standard,
                bluetooth: .standard
            )
        )
    }

    // MARK: - Raster helpers

    private func pixels(
        _ scene: IconSceneState,
        regions: IconSceneRegion = .all,
        foreground: CGColor? = nil,
        phase: ChargingEffectPhase? = nil
    ) throws -> PixelBuffer {
        let image = try #require(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: size,
                scale: scale,
                foreground: foreground ?? white,
                criticalColor: CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
            ),
            phase: phase,
            regions: regions
        ))
        return try PixelBuffer(image: image)
    }

    private func pixelsPerUnit() -> CGFloat {
        size * scale / StatusIconGeometry.canvas.width
    }

    /// Ink bounds in canvas units: only pixels with alpha >= threshold count.
    private func inkBounds(_ pixels: PixelBuffer, threshold: UInt8 = 24) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let alpha = pixels.rgba(x: x, y: y).alpha
                guard alpha >= threshold else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        let ppu = pixelsPerUnit()
        return CGRect(
            x: CGFloat(minX) / ppu,
            y: CGFloat(minY) / ppu,
            width: CGFloat(maxX - minX + 1) / ppu,
            height: CGFloat(maxY - minY + 1) / ppu
        )
    }

    private func assertInkCentredOnRing(_ pixels: PixelBuffer, _ label: String) throws {
        let bounds = try #require(inkBounds(pixels), "\(label) drew no ink")
        #expect(abs(bounds.midX - ringCentre.x) <= 0.75,
                "\(label) ink x=\(bounds.midX) is off the ring centre")
        #expect(abs(bounds.midY - ringCentre.y) <= 0.75,
                "\(label) ink y=\(bounds.midY) is off the ring centre")
        // Whichever glyph replaces the middle icon must stay inside the ring.
        let maxRadius = max(
            hypot(bounds.minX - ringCentre.x, bounds.minY - ringCentre.y),
            hypot(bounds.maxX - ringCentre.x, bounds.maxY - ringCentre.y)
        )
        #expect(maxRadius <= 44, "\(label) overflows the ring interior")
    }

    // MARK: - Centre glyph placement

    @Test func centredBoltSitsOnTheRingCentre() throws {
        let scene = scene(snapshot(battery(76, charging: true, charged: false, connected: true)))
        try assertInkCentredOnRing(
            pixels(scene, regions: .center),
            "bolt"
        )
    }

    @Test func centredPlugSitsOnTheRingCentreWhenConnectedWithoutCharging() throws {
        let scene = scene(snapshot(battery(100, charging: false, charged: true, connected: true)))
        try assertInkCentredOnRing(
            pixels(scene, regions: .center),
            "plug"
        )
    }

    @Test func levelPercentageSitsOnTheRingCentreOnBattery() throws {
        let scene = scene(snapshot(battery(62, charging: false, charged: false, connected: false)))
        guard case let .text(text)? = scene.center else {
            Issue.record("expected the level percentage in the centre")
            return
        }
        #expect(text.text == "62")
        try assertInkCentredOnRing(
            pixels(scene, regions: .center),
            "percentage"
        )
    }

    // MARK: - Ring closure

    @Test func chargingStatusKeepsTheTopGapOpenWhileChargingAndClosesItOnBattery() throws {
        let charging = battery(76, charging: true, charged: false, connected: true)
        let onBattery = battery(76, charging: false, charged: false, connected: false)
        // While charging the centre shows the bolt, so the top gap stays open for
        // the level percentage. On battery the centre carries the percentage, so
        // the ring closes and the same number is not drawn twice.
        let open = try pixels(scene(snapshot(charging)), regions: .ringTrack)
        let closed = try pixels(scene(snapshot(onBattery)), regions: .ringTrack)
        let topPoint = CGPoint(x: ringCentre.x, y: 10)
        #expect(open.alpha(atSVGPoint: topPoint, size: size, scale: scale) == 0)
        #expect(closed.alpha(atSVGPoint: topPoint, size: size, scale: scale) > 0)
    }

    @Test func chargingStatusDrawsThePercentageInTheTopGapWhileCharging() throws {
        let scene = scene(snapshot(battery(76, charging: true, charged: false, connected: true)))
        // The bolt lives in the centre slot, so the top gap carries the level
        // percentage instead of a second indicator.
        guard case let .text(text)? = scene.outerRing?.accessory else {
            Issue.record("expected the level percentage in the top gap")
            return
        }
        #expect(text.text == "76")
        // Rendering only the accessory region paints the percentage.
        let accessoryPixels = try pixels(scene, regions: .ringAccessory)
        #expect(inkBounds(accessoryPixels) != nil)
    }

    // MARK: - Dock split parity

    @Test func dockSplitKeepsTheCentredStatus() throws {
        let scene = scene(snapshot(battery(76, charging: true, charged: false, connected: true)))
        let phase = ChargingEffectPhase(step: 12, stepsPerCycle: 36, kind: .steady)
        let pixelLength = 512
        let single = try #require(DockIconRenderer.tileImage(
            scene: scene, backgroundStyle: .dark, pixelLength: pixelLength, phase: phase
        ))
        let base = try #require(DockIconRenderer.animationBaseImage(
            scene: scene, backgroundStyle: .dark, pixelLength: pixelLength
        ))
        let effect = try #require(DockIconRenderer.chargingEffectImage(
            scene: scene, phase: phase, backgroundStyle: .dark, pixelLength: pixelLength
        ))
        let rect = try #require(DockIconRenderer.chargingEffectRect(
            scene: scene, pixelLength: pixelLength
        ))
        let context = try #require(CGContext(
            data: nil, width: pixelLength, height: pixelLength,
            bitsPerComponent: 8, bytesPerRow: pixelLength * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(base, in: CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength))
        context.draw(effect, in: rect)
        let composite = try #require(context.makeImage())
        let singlePixels = try PixelBuffer(image: single)
        let compositePixels = try PixelBuffer(image: composite)
        var difference = 0
        for index in stride(from: 0, to: singlePixels.bytes.count, by: 4) {
            for channel in 0..<4 {
                difference = max(
                    difference,
                    abs(Int(singlePixels.bytes[index + channel])
                        - Int(compositePixels.bytes[index + channel]))
                )
            }
        }
        #expect(difference <= 2, "the split changed the artwork by \(difference) per channel")
    }

    // MARK: - Static fingerprint

    @Test func centredChargingStaticFingerprint() throws {
        // Percentage numerals use the system font, which varies with the display's
        // type metrics; the fingerprint pins the vector-only baseline instead, so
        // it renders with `showsPercentage` off (the ring closes and only the
        // vector bolt, ring and footer are drawn).
        let scene = scene(
            snapshot(battery(76, charging: true, charged: false, connected: true)),
            batteryOptions: BatteryIconOptions(showsPercentage: false)
        )
        let rendered = try pixels(scene)
        let fingerprint = SHA256.hash(data: Data(rendered.bytes))
            .map { String(format: "%02x", $0) }
            .joined()
        print("CENTRED_STATUS_STATIC sha256=\(fingerprint)")
        #expect(fingerprint == centredStatusStaticFingerprint)
    }

    /// Recorded from the current `.chargingStatus` scene at 120 pt @2x, dark
    /// ink, no SF Symbols (the centre glyph is the vector bolt, the ring is
    /// closed, the footer is vector), so the value does not vary with the
    /// display's symbol metrics.
    /// Recorded after the centre charge glyph was matched to the Wi-Fi glyph's
    /// ink height (0.8 factor), so this also locks that visual baseline.
    private let centredStatusStaticFingerprint =
        "7fd2292a12ee2c32e5bea4ac86d18408fff58b1cf35dd04463a844e90597a43e"
}
