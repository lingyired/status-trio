import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectRenderingTests {
    @Test func nilPhaseKeepsThePreEffectStaticPixelFingerprint() throws {
        let pixels = try renderPixels(
            snapshot: staticSnapshot,
            options: BatteryIconOptions(
                showsPercentage: false,
                showsChargingIndicator: false
            ),
            phase: nil
        )
        let fingerprint = SHA256.hash(data: Data(pixels.bytes))
            .map { String(format: "%02x", $0) }
            .joined()

        // CoreGraphics rasterizes a few edge pixels differently across the
        // supported macOS 26 CI runner and the macOS 27 local toolchain. Keep
        // both observed static baselines so other pixel changes still fail.
        //
        // These baselines were re-recorded for the #30 fix, which moved the
        // Wi-Fi symbol from `canvas.midX` (60.0) to `artworkCenterX` (59.5).
        // `staticSnapshot` reports `.off`, so it draws `wifi.slash` through the
        // same anchor and its pixels change too — that is the expected effect
        // of the fix, not a regression.
        let knownPlatformFingerprints = [
            "9f0c892e2602f4d4f9c541be1d93963e14d46e76f3ef24b46cd2dfbc25a22d1d", // macOS 26 CI, artworkCenterX anchor
            "0ef6d483e344f6056fa3799f9f33bac0092246e3dbfbb3619a4666d7e9e9c190", // macOS 27 local, artworkCenterX anchor
        ]
        #expect(knownPlatformFingerprints.contains(fingerprint))
    }

    @Test func nonChargingBatteryIgnoresSuppliedChargingPhase() throws {
        let staticPixels = try renderPixels(snapshot: staticSnapshot, phase: nil)
        let animatedPixels = try renderPixels(
            snapshot: staticSnapshot,
            phase: .init(step: 7, stepsPerCycle: 36, kind: .steady)
        )

        #expect(animatedPixels.bytes == staticPixels.bytes)
    }

    @Test func activePhaseChangesPixelsOnlyInsideTheBatteryRegion() throws {
        let snapshot = chargingSnapshot
        let staticPixels = try renderPixels(snapshot: snapshot, phase: nil)
        let animatedPixels = try renderPixels(
            snapshot: snapshot,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        )
        let changedPixels = differingPixelIndices(staticPixels.bytes, animatedPixels.bytes)
        let pixelsPerSVGUnit = 20 * 2 / StatusIconGeometry.canvas.width
        let batteryBounds = StatusIconGeometry.batteryTrack(hasTopGap: false)
            .boundingBoxOfPath.insetBy(dx: -16, dy: -16)

        #expect(!changedPixels.isEmpty)
        #expect(changedPixels.allSatisfy { index in
            let x = CGFloat(index % staticPixels.width)
            let y = CGFloat(index / staticPixels.width)
            let point = CGPoint(
                x: (x + 0.5) / pixelsPerSVGUnit,
                y: (y + 0.5) / pixelsPerSVGUnit
            )
            return batteryBounds.contains(point)
        })
    }

    @Test func chargingWithoutAnIndicatorDrawsTheNoGapFullArcEffect() throws {
        let options = BatteryIconOptions(
            showsPercentage: false,
            showsChargingIndicator: false
        )
        let staticPixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: nil
        )
        let phasePixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        )

        #expect(phasePixels.bytes != staticPixels.bytes)
    }

    @Test func chargingBoltMakesOnePulseWhileTheEffectCrossesItsGap() throws {
        let boltRegion = CGRect(x: 45, y: 0, width: 29, height: 35)
        func boltInk(at step: Int) throws -> Int {
            try renderPixels(
                snapshot: chargingSnapshot,
                phase: .init(step: step, stepsPerCycle: 36, kind: .steady)
            ).alphaSum(inSVGRect: boltRegion, size: 20, scale: 2)
        }

        let frames = (0..<36).compactMap { step in
            ChargingEffectPolicy.frame(
                progress: 0.76,
                phase: .init(step: step, stepsPerCycle: 36, kind: .steady),
                hasTopGap: true
            )
        }
        let scales = frames.map(\.boltScale)
        let crossingSteps = scales.indices.filter { scales[$0] > 1 }
        let firstCrossingStep = try #require(crossingSteps.first)
        let lastCrossingStep = try #require(crossingSteps.last)
        let peakStep = try #require(crossingSteps.max { scales[$0] < scales[$1] })

        let entry = try boltInk(at: firstCrossingStep - 1)
        let center = try boltInk(at: peakStep)
        let exit = try boltInk(at: lastCrossingStep + 1)
        #expect(center > entry)
        #expect(center > exit)

        func boltColor(at step: Int) throws -> (
            red: UInt8,
            green: UInt8,
            blue: UInt8,
            alpha: UInt8
        ) {
            try renderPixels(
                snapshot: chargingSnapshot,
                phase: .init(step: step, stepsPerCycle: 36, kind: .steady)
            ).rgba(atSVGPoint: CGPoint(x: 61, y: 11), size: 20, scale: 2)
        }
        let foregroundColor = (
            red: UInt8(255),
            green: UInt8(255),
            blue: UInt8(255),
            alpha: UInt8(255)
        )
        let entryColor = try boltColor(at: firstCrossingStep - 1)
        let transitionColor = try boltColor(at: peakStep - 2)
        let peakColor = try boltColor(at: peakStep)
        let exitColor = try boltColor(at: lastCrossingStep + 1)
        let settledColor = try boltColor(at: lastCrossingStep + 2)
        #expect(rgbDistance(entryColor, foregroundColor) < 0.12)
        #expect(rgbDistance(transitionColor, foregroundColor) > 0.02)
        #expect(rgbDistance(transitionColor, foregroundColor) < rgbDistance(peakColor, foregroundColor))
        #expect(rgbDistance(exitColor, foregroundColor) < 0.12)
        #expect(rgbDistance(settledColor, foregroundColor) < 0.12)

        let darkForeground = CGColor(gray: 0, alpha: 1)
        let darkMenuBarPixels = try renderPixels(
            snapshot: chargingSnapshot,
            foreground: darkForeground,
            phase: .init(step: peakStep, stepsPerCycle: 36, kind: .steady)
        )
        let darkPeakColor = darkMenuBarPixels.rgba(
            atSVGPoint: CGPoint(x: 61, y: 11),
            size: 20,
            scale: 2
        )
        let darkBaselineColor = try renderPixels(
            snapshot: chargingSnapshot,
            foreground: darkForeground,
            phase: nil
        ).rgba(atSVGPoint: CGPoint(x: 61, y: 11), size: 20, scale: 2)
        #expect(relativeLuminance(darkPeakColor) > relativeLuminance(darkBaselineColor) + 0.1)

        let monochromePixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: BatteryIconOptions(usesStatusColors: false),
            phase: .init(step: peakStep, stepsPerCycle: 36, kind: .steady)
        )
        let monochromePeakColor = monochromePixels.rgba(
            atSVGPoint: CGPoint(x: 61, y: 11),
            size: 20,
            scale: 2
        )
        #expect(rgbDistance(monochromePeakColor, foregroundColor) < 0.12)

        #expect(scales[firstCrossingStep - 1] == 1)
        #expect(scales[lastCrossingStep + 1] == 1)
        let maximumScale = scales[peakStep]
        #expect(maximumScale > 1.18)
        #expect(maximumScale <= 1.2)
        #expect(crossingSteps.filter { scales[$0] == maximumScale }.count <= 2)
        #expect((firstCrossingStep...peakStep).allSatisfy { $0 == firstCrossingStep || scales[$0] >= scales[$0 - 1] })
        #expect((peakStep...lastCrossingStep).allSatisfy { $0 == lastCrossingStep || scales[$0] >= scales[$0 + 1] })
    }

    @Test func disablingBoltHeartbeatKeepsArcAnimationAndStaticForegroundBolt() throws {
        let stationaryOptions = BatteryIconOptions(
            showsChargingEffect: false,
            showsChargingBoltHeartbeat: false
        )
        let arcEffectOptions = BatteryIconOptions(showsChargingBoltHeartbeat: false)
        let staticPixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: stationaryOptions,
            phase: nil
        )
        let animatedPixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: arcEffectOptions,
            phase: .init(step: 24, stepsPerCycle: 36, kind: .steady)
        )
        let boltPoint = CGPoint(x: 61, y: 11)
        let boltBounds = CGRect(x: 51.3, y: 2.1, width: 15.9, height: 19.9)

        #expect(animatedPixels.bytes != staticPixels.bytes)
        #expect(
            animatedPixels.alphaSum(inSVGRect: boltBounds, size: 20, scale: 2)
                == staticPixels.alphaSum(inSVGRect: boltBounds, size: 20, scale: 2)
        )
        #expect(rgbDistance(
            animatedPixels.rgba(atSVGPoint: boltPoint, size: 20, scale: 2),
            staticPixels.rgba(atSVGPoint: boltPoint, size: 20, scale: 2)
        ) < 0.03)
    }

    @Test func chargingBoltHeartbeatReachesTheRevisedTwentyPercentScale() throws {
        let frames = (0..<36).compactMap { step in
            ChargingEffectPolicy.frame(
                progress: 0.76,
                phase: .init(step: step, stepsPerCycle: 36, kind: .steady),
                hasTopGap: true
            )
        }

        let maximumScale = try #require(frames.map(\.boltScale).max())
        #expect(maximumScale > 1.18)
        #expect(maximumScale <= 1.2)
    }

    @Test func enlargedBoltKeepsItsTopTipInsideTheIconCanvas() {
        let normal = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath
        let enlarged = StatusIconGeometry.batteryChargingBolt(scale: 1.2).boundingBoxOfPath

        #expect(enlarged.minY >= normal.minY)
        #expect(enlarged.minY > StatusIconGeometry.canvas.minY)
        #expect(enlarged.maxY < StatusIconGeometry.canvas.maxY)
    }

    @Test func animatedBoltZoomStaysCenteredAndInsideTheCanvasAtMaximumSize() {
        let defaultScale = StatusIconRenderer.batteryChargingBoltScale(
            textScale: BatteryIconOptions.defaultTextScale
        )
        let defaultBase = StatusIconGeometry.batteryChargingBolt(scale: defaultScale).boundingBoxOfPath
        let defaultPeak = StatusIconGeometry.batteryChargingBolt(
            basePath: StatusIconGeometry.batteryChargingBolt(scale: defaultScale),
            centeredScale: 1.2,
            fitting: StatusIconGeometry.canvas
        ).boundingBoxOfPath
        let maximumScale = StatusIconRenderer.batteryChargingBoltScale(textScale: 3)
        let base = StatusIconGeometry.batteryChargingBolt(scale: maximumScale)
        let baseBounds = base.boundingBoxOfPath
        let verticalScale = min(
            1.2,
            min(
                baseBounds.midY / (baseBounds.midY - baseBounds.minY),
                (StatusIconGeometry.canvas.maxY - baseBounds.midY)
                    / (baseBounds.maxY - baseBounds.midY)
            )
        )
        let enlargedBounds = StatusIconGeometry.batteryChargingBolt(
            basePath: base,
            centeredScale: 1.2,
            fitting: StatusIconGeometry.canvas
        ).boundingBoxOfPath

        #expect(defaultPeak.minY >= StatusIconGeometry.canvas.minY - 0.01)
        #expect(abs(defaultPeak.midY - defaultBase.midY) < 0.01)
        #expect(enlargedBounds.minY >= StatusIconGeometry.canvas.minY - 0.01)
        #expect(enlargedBounds.maxY <= StatusIconGeometry.canvas.maxY)
        #expect(abs(enlargedBounds.width - baseBounds.width * 1.2) < 0.01)
        #expect(abs(enlargedBounds.height - baseBounds.height * verticalScale) < 0.01)
        #expect(abs(enlargedBounds.midX - baseBounds.midX) < 0.01)
        #expect(abs(enlargedBounds.midY - baseBounds.midY) < 0.01)
    }

    @MainActor @Test func dockRendererProducesStaticChargingArtwork() throws {
        let status = MenuBarStatus(snapshot: chargingSnapshot)
        let image = try #require(renderDockFixture(
                status: status))
        #expect(image.size == NSSize(width: 256, height: 256))
    }

    @Test func disablingTheEffectKeepsTheStaticPixels() throws {
        let options = BatteryIconOptions(showsChargingEffect: false)
        let staticPixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: nil
        )
        let phasePixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        )

        #expect(phasePixels.bytes == staticPixels.bytes)
    }

    @Test func effectOptionDefaultsToEnabled() {
        #expect(BatteryIconOptions.standard.showsChargingEffect)
        #expect(BatteryIconOptions().showsChargingEffect)
    }

    private var staticSnapshot: StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: nil)
        )
    }

    private var chargingSnapshot: StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: nil)
        )
    }

    private func renderPixels(
        snapshot: StatusSnapshot,
        options: BatteryIconOptions = .standard,
        foreground: CGColor = CGColor(gray: 1, alpha: 1),
        phase: ChargingEffectPhase?
    ) throws -> PixelBuffer {
        let image = try #require(renderMenuBarFixture(
                snapshot: snapshot,
            size: 20,
            scale: 2,
            foreground: foreground,
            options: options,
            phase: phase
        ))
        return try PixelBuffer(image: image)
    }

    private func differingPixelIndices(_ lhs: [UInt8], _ rhs: [UInt8]) -> Set<Int> {
        Set(lhs.indices.compactMap { byteIndex in
            guard lhs[byteIndex] != rhs[byteIndex] else { return nil }
            return byteIndex / 4
        })
    }

    private func rgbDistance(
        _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) -> Double {
        func straightColor(
            _ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
        ) -> (Double, Double, Double) {
            let alpha = max(1, Double(color.alpha))
            return (
                min(255, Double(color.red) * 255 / alpha) / 255,
                min(255, Double(color.green) * 255 / alpha) / 255,
                min(255, Double(color.blue) * 255 / alpha) / 255
            )
        }
        let left = straightColor(lhs)
        let right = straightColor(rhs)
        let red = left.0 - right.0
        let green = left.1 - right.1
        let blue = left.2 - right.2
        return sqrt(red * red + green * green + blue * blue)
    }

    private func relativeLuminance(
        _ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let alpha = max(1, Double(color.alpha))
        let red = min(255, Double(color.red) * 255 / alpha) / 255
        let green = min(255, Double(color.green) * 255 / alpha) / 255
        let blue = min(255, Double(color.blue) * 255 / alpha) / 255
        return 0.2126 * linearize(red)
            + 0.7152 * linearize(green)
            + 0.0722 * linearize(blue)
    }

}
