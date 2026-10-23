import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

/// The Dock animation is split into a static base and a small effect raster so a
/// 20-Hz tick never rasterizes the whole tile. These tests pin that the split
/// composites back to the one-pass picture, and that the effect raster really is
/// the small slice it claims to be.
@MainActor
struct DockChargingSplitParityTests {
    @Test func compositedSplitMatchesTheSinglePassTile() throws {
        let scene = chargingScene()
        let phase = ChargingEffectPhase(step: 12, stepsPerCycle: 36, kind: .steady)
        let pixelLength = 512

        let single = try #require(
            DockIconRenderer.tileImage(
                scene: scene,
                backgroundStyle: .dark,
                pixelLength: pixelLength,
                phase: phase
            )
        )
        let base = try #require(
            DockIconRenderer.animationBaseImage(
                scene: scene,
                backgroundStyle: .dark,
                pixelLength: pixelLength
            )
        )
        let effect = try #require(
            DockIconRenderer.chargingEffectImage(
                scene: scene,
                phase: phase,
                backgroundStyle: .dark,
                pixelLength: pixelLength
            )
        )
        let rect = try #require(
            DockIconRenderer.chargingEffectRect(scene: scene, pixelLength: pixelLength)
        )

        let context = try #require(CGContext(
            data: nil,
            width: pixelLength,
            height: pixelLength,
            bitsPerComponent: 8,
            bytesPerRow: pixelLength * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength))
        context.draw(effect, in: rect)
        let composited = try #require(context.makeImage())

        let expected = try pixels(of: single)
        let actual = try pixels(of: composited)
        let difference = expected.maximumChannelDifference(from: actual)
        #expect(difference <= 2, "The split changed the artwork by \(difference) per channel.")
    }

    @Test func effectRasterIsASmallSliceOfTheTile() throws {
        let scene = chargingScene()
        let pixelLength = 512
        let rect = try #require(
            DockIconRenderer.chargingEffectRect(scene: scene, pixelLength: pixelLength)
        )
        let effect = try #require(
            DockIconRenderer.chargingEffectImage(
                scene: scene,
                phase: ChargingEffectPhase(step: 0, stepsPerCycle: 36, kind: .steady),
                backgroundStyle: .dark,
                pixelLength: pixelLength
            )
        )

        #expect(effect.width == Int(rect.width))
        #expect(effect.height == Int(rect.height))
        #expect(rect.width < CGFloat(pixelLength) * 0.85)
        #expect(rect.height < CGFloat(pixelLength) * 0.85)
    }

    @Test func aSceneWithoutAChargingEffectHasNoEffectRect() {
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: PresentationFixtures.snapshot(),
                audioIcon: nil
            ),
            configuration: .standard
        )

        #expect(DockIconRenderer.chargingEffectRect(scene: scene, pixelLength: 512) == nil)
    }

    private func chargingScene() -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: 62,
                        isPresent: true,
                        isCharging: true,
                        isLowPowerMode: false,
                        isConnectedToPower: true
                    ),
                    wifi: WiFiStatus(state: .connected, rssi: -50),
                    connection: .wifi,
                    volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
                ),
                audioIcon: nil
            ),
            configuration: .standard
        )
    }

    private func pixels(of image: CGImage) throws -> PixelBuffer {
        try PixelBuffer(image: image)
    }
}

private extension PixelBuffer {
    /// The largest per-channel difference between two rasters of one size.
    func maximumChannelDifference(from other: PixelBuffer) -> Int {
        guard width == other.width, height == other.height else { return .max }
        var difference = 0
        for index in bytes.indices {
            difference = max(difference, abs(Int(bytes[index]) - Int(other.bytes[index])))
        }
        return difference
    }
}
