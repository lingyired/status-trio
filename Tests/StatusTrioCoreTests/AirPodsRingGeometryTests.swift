import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class AirPodsRingGeometryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSingleUsesMainThenBothEarMeanThenAvailableSingleEarAndAcceptsZero() throws {
        let main = try state(main: 42, left: 80, right: 60)
        XCTAssertEqual(main.segments.map(\.progress), [0.42])
        XCTAssertEqual(try state(main: nil, left: 80, right: 60).segments.map(\.progress), [0.7])
        XCTAssertEqual(try state(main: nil, left: 80, right: 61).segments.map(\.progress), [0.705])
        XCTAssertEqual(try state(main: nil, left: 0, right: nil).segments.map(\.progress), [0])
        XCTAssertEqual(try state(main: 0, left: 80, right: 60).segments.map(\.progress), [0])
    }

    func testCaseOnlyIsUnavailableAndDualPartialNeverInventsMissingEar() throws {
        XCTAssertNil(AirPodsRingMapper.resolve(snapshot: snapshot(main: nil, left: nil, right: nil, caseLevel: 88), behavior: .single, now: now))
        let leftOnly = try XCTUnwrap(AirPodsRingMapper.resolve(snapshot: snapshot(main: nil, left: 35, right: nil), behavior: .dual, now: now))
        XCTAssertEqual(leftOnly.layout, .standard)
        XCTAssertEqual(leftOnly.segments.map(\.progress), [0.35])
        XCTAssertTrue(leftOnly.isPartial)
        let mainOnly = try state(main: 31, left: nil, right: nil, behavior: .dual)
        XCTAssertEqual(mainOnly.segments.map(\.progress), [0.31])
        XCTAssertFalse(mainOnly.isPartial)
    }

    func testDualKeepsLeftAndRightInFixedPositionsWithIndependentColors() throws {
        let ring = try state(main: nil, left: 24, right: 76, behavior: .dual)
        XCTAssertEqual(ring.layout, .leftRight)
        XCTAssertEqual(ring.segments.map(\.position), [.left, .right])
        XCTAssertEqual(ring.segments.map(\.progress), [0.24, 0.76])
        XCTAssertNotEqual(ring.segments[0].color, ring.segments[1].color)
    }

    func testExpiredAirPodsSnapshotIsUnavailableForResolverFallback() throws {
        let stale = snapshot(main: 50, left: 50, right: 50, observedAt: now.addingTimeInterval(-AirPodsBatteryIconSnapshot.freshnessInterval - 1))
        var inputs = IconResolutionInputs(system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil), sources: IconSourceSnapshot(availability: [:], airPodsBattery: stale))
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        let resolved = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)
        XCTAssertEqual(resolved.trace.outerRing.selectedSourceID, RingSource.systemBattery.rawValue)
        XCTAssertNotNil(resolved.scene.outerRing)
        inputs.sources.availability[RingSource.systemBattery.rawValue] = .unavailable(.disconnected)
        XCTAssertNil(IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now).scene.outerRing)
    }

    func testLeftRightGeometryLeavesAVisibleGapAndFitsRingBounds() {
        let left = StatusIconGeometry.airPodsArc(position: .left, progress: 1, gapWidth: 10)
        let right = StatusIconGeometry.airPodsArc(position: .right, progress: 1, gapWidth: 10)
        XCTAssertFalse(left.isEmpty)
        XCTAssertFalse(right.isEmpty)
        XCTAssertGreaterThan(left.boundingBox.width, 0)
        XCTAssertGreaterThan(right.boundingBox.width, 0)
        XCTAssertLessThanOrEqual(left.boundingBox.maxX, StatusIconGeometry.canvas.maxX)
        XCTAssertLessThanOrEqual(right.boundingBox.maxX, StatusIconGeometry.canvas.maxX)
        XCTAssertNotEqual(left.boundingBox, right.boundingBox)
    }

    func testMenuBarAndDockBothRenderTheExplicitDualLayout() throws {
        let ring = try state(main: nil, left: 0, right: 100, behavior: .dual)
        let scene = IconSceneState(outerRing: ring)
        let menu = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: .init(size: 32, scale: 2, foreground: CGColor(gray: 1, alpha: 1), criticalColor: StatusIconRenderer.defaultCriticalColor)))
        let dock = try XCTUnwrap(DockIconRenderer.image(scene: scene, pixelLength: 128))
        XCTAssertEqual(menu.width, 64)
        XCTAssertEqual(dock.size, NSSize(width: 64, height: 64))
        let equivalent = DockIconRenderKey(scene: IconSceneState(outerRing: ring), backgroundStyle: .dark, pixelLength: 128)
        XCTAssertEqual(DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128), equivalent)
        let changedLeft = OuterRingState(segments: [
            RingSegmentState(progress: 0.01, color: ring.segments[0].color, position: .left),
            ring.segments[1]
        ], gap: ring.gap, layout: ring.layout)
        let key = DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128)
        XCTAssertNotEqual(key, DockIconRenderKey(scene: IconSceneState(outerRing: changedLeft), backgroundStyle: .dark, pixelLength: 128))
        let recolored = OuterRingState(segments: [
            RingSegmentState(progress: ring.segments[0].progress, color: .critical, position: .left),
            ring.segments[1]
        ], gap: ring.gap, layout: ring.layout)
        XCTAssertNotEqual(key, DockIconRenderKey(scene: IconSceneState(outerRing: recolored), backgroundStyle: .dark, pixelLength: 128))
        let partial = OuterRingState(segments: ring.segments, gap: ring.gap, layout: ring.layout, isPartial: true)
        XCTAssertNotEqual(key, DockIconRenderKey(scene: IconSceneState(outerRing: partial), backgroundStyle: .dark, pixelLength: 128))
    }

    func testGeometryClampsUnsafeGapWidthAndRejectsNonfiniteProgress() {
        for position in [RingSegmentPosition.left, .right] {
            let tinyGap = StatusIconGeometry.airPodsArc(position: position, progress: 1, gapWidth: -100)
            let hugeGap = StatusIconGeometry.airPodsArc(position: position, progress: 1, gapWidth: 1_000)
            let nonfiniteGap = StatusIconGeometry.airPodsArc(position: position, progress: 1, gapWidth: .infinity)
            XCTAssertFalse(tinyGap.isEmpty)
            XCTAssertFalse(hugeGap.isEmpty)
            XCTAssertFalse(nonfiniteGap.isEmpty)
            XCTAssertLessThanOrEqual(tinyGap.boundingBox.maxX, StatusIconGeometry.canvas.maxX)
            XCTAssertLessThanOrEqual(hugeGap.boundingBox.maxY, StatusIconGeometry.canvas.maxY)
            XCTAssertTrue(StatusIconGeometry.airPodsArc(position: position, progress: .infinity).isEmpty)
        }
    }

    func testMenuBarAndDockDrawBothFixedSegmentsWithTheirOwnColors() throws {
        let red = IconColorRole.custom(IconRGBA(red: 1, green: 0, blue: 0, alpha: 1))
        let blue = IconColorRole.custom(IconRGBA(red: 0, green: 0, blue: 1, alpha: 1))
        let scene = IconSceneState(outerRing: OuterRingState(
            segments: [RingSegmentState(progress: 1, color: red, position: .left),
                       RingSegmentState(progress: 1, color: blue, position: .right)],
            gap: .closed, layout: .leftRight
        ))
        let menu = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: .init(
            size: 120, scale: 4, foreground: CGColor(gray: 1, alpha: 1), criticalColor: StatusIconRenderer.defaultCriticalColor
        )))
        let menuPixels = try PixelBuffer(image: menu)

        XCTAssertTrue(menuPixels.containsColor(red: 1, green: 0, blue: 0, tolerance: 0.24, minimumAlpha: 0.9))
        XCTAssertTrue(menuPixels.containsColor(red: 0, green: 0, blue: 1, tolerance: 0.24, minimumAlpha: 0.9))

        let dock = try XCTUnwrap(DockIconRenderer.image(scene: scene, pixelLength: 256))
        var rect = CGRect(origin: .zero, size: dock.size)
        let dockCGImage = try XCTUnwrap(dock.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let dockPixels = try PixelBuffer(image: dockCGImage)
        XCTAssertTrue(dockPixels.containsColor(red: 1, green: 0, blue: 0, tolerance: 0.24, minimumAlpha: 0.9))
        XCTAssertTrue(dockPixels.containsColor(red: 0, green: 0, blue: 1, tolerance: 0.24, minimumAlpha: 0.9))
    }

    func testDualLayoutKeepsMaximumStrokeInsideCanvas() throws {
        let ring = OuterRingState(
            segments: [RingSegmentState(progress: 1, color: .primary, position: .left),
                       RingSegmentState(progress: 1, color: .bluetooth, position: .right)],
            gap: .closed,
            layout: .leftRight,
            strokeScale: 2.5
        )
        let image = try XCTUnwrap(StatusIconRenderer.render(
            scene: IconSceneState(outerRing: ring),
            environment: .init(size: 120, scale: 4, foreground: CGColor(gray: 1, alpha: 1),
                                criticalColor: StatusIconRenderer.defaultCriticalColor)
        ))
        XCTAssertEqual(try PixelBuffer(image: image).maximumAlphaOnEdges, 0)
        XCTAssertGreaterThan(StatusIconGeometry.airPodsGapWidth, 12)
    }

    func testClassicSingleRingSceneKeepsItsDefaultLayoutAndCacheIdentity() throws {
        let snapshot = StatusSnapshot.placeholder
        let scene = IconPresentationMapper.scene(inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil), configuration: .standard)
        XCTAssertEqual(scene.outerRing?.layout, .standard)
        XCTAssertEqual(DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128),
                       DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128))
    }

    private func state(main: Int?, left: Int?, right: Int?, behavior: AirPodsRingBehavior = .single) throws -> OuterRingState {
        try XCTUnwrap(AirPodsRingMapper.resolve(snapshot: snapshot(main: main, left: left, right: right), behavior: behavior, now: now))
    }

    private func snapshot(main: Int?, left: Int?, right: Int?, caseLevel: Int? = nil, observedAt: Date? = nil) -> AirPodsBatteryIconSnapshot {
        AirPodsBatteryIconSnapshot(deviceAddress: "AA:BB:CC:DD:EE:FF", model: .airPodsPro, main: main, left: left, right: right, caseLevel: caseLevel, observedAt: observedAt ?? now)
    }
}
