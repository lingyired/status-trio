import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import StatusTrioCore

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

    @Test func chargingBoltBeatsTwiceWhileTheEffectCrossesItsGap() throws {
        let boltRegion = CGRect(x: 45, y: 0, width: 29, height: 35)
        func boltInk(at step: Int) throws -> Int {
            try renderPixels(
                snapshot: chargingSnapshot,
                phase: .init(step: step, stepsPerCycle: 36, kind: .steady)
            ).alphaSum(inSVGRect: boltRegion, size: 20, scale: 2)
        }

        let resting = try boltInk(at: 12)
        let firstBeat = try boltInk(at: 17)
        let pause = try boltInk(at: 18)
        let secondBeat = try boltInk(at: 20)
        let settled = try boltInk(at: 24)

        #expect(firstBeat > resting)
        #expect(firstBeat > pause)
        #expect(secondBeat > pause)
        #expect(settled == resting)
    }

    @MainActor @Test func dockRendererProducesStaticChargingArtwork() throws {
        let status = MenuBarStatus(snapshot: chargingSnapshot)
        let image = try #require(DockIconRenderer.image(status: status))
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
        phase: ChargingEffectPhase?
    ) throws -> PixelBuffer {
        let image = try #require(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
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
}
