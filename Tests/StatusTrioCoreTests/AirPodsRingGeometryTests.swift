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

    func testCaseOnlyIsUnavailableAndDualSingleEarMirrorsIntoFixedArcs() throws {
        XCTAssertNil(AirPodsRingMapper.resolve(snapshot: snapshot(main: nil, left: nil, right: nil, caseLevel: 88), behavior: .single, now: now))
        XCTAssertNil(AirPodsRingMapper.resolve(snapshot: snapshot(main: nil, left: nil, right: nil, caseLevel: 88), behavior: .dual, now: now))

        let leftOnly = try state(main: nil, left: 35, right: nil, behavior: .dual)
        XCTAssertEqual(leftOnly.layout, .leftRight)
        XCTAssertEqual(leftOnly.segments.map(\.position), [.left, .right])
        XCTAssertEqual(leftOnly.segments.map(\.progress), [0.35, 0.35])
        XCTAssertEqual(leftOnly.segments.map(\.color), [.bluetooth, .primary])
        XCTAssertEqual(leftOnly.gap, .closed)
        XCTAssertTrue(leftOnly.isPartial)
        XCTAssertNil(leftOnly.effect)

        let rightOnly = try state(main: nil, left: nil, right: 42, behavior: .dual)
        XCTAssertEqual(rightOnly.layout, .leftRight)
        XCTAssertEqual(rightOnly.segments.map(\.position), [.left, .right])
        XCTAssertEqual(rightOnly.segments.map(\.progress), [0.42, 0.42])
        XCTAssertEqual(rightOnly.segments.map(\.color), [.bluetooth, .primary])
        XCTAssertEqual(rightOnly.gap, .closed)
        XCTAssertTrue(rightOnly.isPartial)
        XCTAssertNil(rightOnly.effect)

        let leftPlusMain = try state(main: 80, left: 35, right: nil, behavior: .dual)
        XCTAssertEqual(leftPlusMain.segments.map(\.progress), [0.35, 0.35], "The known ear must take precedence over the conflicting main value.")
        let rightPlusMain = try state(main: 80, left: nil, right: 42, behavior: .dual)
        XCTAssertEqual(rightPlusMain.segments.map(\.progress), [0.42, 0.42], "Known-ear precedence must be symmetric.")

        let mainOnly = try state(main: 31, left: nil, right: nil, behavior: .dual)
        XCTAssertEqual(mainOnly.layout, .standard)
        XCTAssertEqual(mainOnly.segments.map(\.progress), [0.31])
        XCTAssertFalse(mainOnly.isPartial)
        XCTAssertNil(AirPodsRingMapper.resolve(snapshot: snapshot(main: nil, left: -1, right: 101), behavior: .dual, now: now))
        XCTAssertEqual(try state(main: 47, left: -1, right: 101, behavior: .dual).segments.map(\.progress), [0.47],
                       "Invalid ear levels are unavailable, so the existing main-only fallback remains.")
        for boundary in [0, 100] {
            let mirrored = try state(main: nil, left: boundary, right: nil, behavior: .dual)
            XCTAssertEqual(mirrored.segments.map(\.progress), [Double(boundary) / 100, Double(boundary) / 100])
            XCTAssertTrue(mirrored.isPartial)
        }
        XCTAssertEqual(try state(main: 80, left: 35, right: nil).segments.map(\.progress), [0.8],
                       "Single mode must preserve main-battery priority.")
    }

    func testDualKeepsLeftAndRightInFixedPositionsWithIndependentColors() throws {
        let ring = try state(main: nil, left: 24, right: 76, behavior: .dual)
        XCTAssertEqual(ring.layout, .leftRight)
        XCTAssertEqual(ring.segments.map(\.position), [.left, .right])
        XCTAssertEqual(ring.segments.map(\.progress), [0.24, 0.76])
        XCTAssertNotEqual(ring.segments[0].color, ring.segments[1].color)
        XCTAssertEqual(ring.gap, .closed)
        XCTAssertNil(ring.effect, "AirPods rings remain static and do not inherit Mac charging effects.")
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

    func testSingleEarDualRingRendersMirroredArcsInMenuBarAndDockAndInvalidatesDockCache() throws {
        let leftOnly = try state(main: nil, left: 35, right: nil, behavior: .dual)
        let rightOnly = try state(main: nil, left: nil, right: 35, behavior: .dual)
        let expected = OuterRingState(
            segments: [RingSegmentState(progress: 0.35, color: .bluetooth, position: .left),
                       RingSegmentState(progress: 0.35, color: .primary, position: .right)],
            gap: .closed,
            layout: .leftRight,
            isPartial: true
        )
        let expectedScene = IconSceneState(outerRing: expected)
        let leftScene = IconSceneState(outerRing: leftOnly)
        let rightScene = IconSceneState(outerRing: rightOnly)
        let environment = StatusIconRenderEnvironment(
            size: 120,
            scale: 4,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )

        let expectedMenu = try XCTUnwrap(StatusIconRenderer.render(scene: expectedScene, environment: environment))
        let leftMenu = try XCTUnwrap(StatusIconRenderer.render(scene: leftScene, environment: environment))
        let rightMenu = try XCTUnwrap(StatusIconRenderer.render(scene: rightScene, environment: environment))
        XCTAssertEqual(try PixelBuffer(image: leftMenu).bytes, try PixelBuffer(image: expectedMenu).bytes)
        XCTAssertEqual(try PixelBuffer(image: rightMenu).bytes, try PixelBuffer(image: expectedMenu).bytes)

        let expectedDock = try dockPixels(for: expectedScene)
        XCTAssertEqual(try dockPixels(for: leftScene).bytes, expectedDock.bytes)
        XCTAssertEqual(try dockPixels(for: rightScene).bytes, expectedDock.bytes)

        let initialKey = DockIconRenderKey(scene: leftScene, backgroundStyle: .dark, pixelLength: 256)
        let updatedRing = try state(main: 80, left: 36, right: nil, behavior: .dual)
        let updatedKey = DockIconRenderKey(scene: IconSceneState(outerRing: updatedRing), backgroundStyle: .dark, pixelLength: 256)
        var cache = DockIconRenderCache()
        XCTAssertTrue(cache.needsRender(initialKey))
        cache.recordSuccessfulRender(initialKey)
        XCTAssertFalse(cache.needsRender(initialKey))
        XCTAssertTrue(cache.needsRender(updatedKey), "Changing the available ear must invalidate the mirrored Dock raster.")
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

    private func dockPixels(for scene: IconSceneState) throws -> PixelBuffer {
        let image = try XCTUnwrap(DockIconRenderer.image(scene: scene, pixelLength: 256))
        var rect = CGRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return try PixelBuffer(image: cgImage)
    }

    private func state(main: Int?, left: Int?, right: Int?, behavior: AirPodsRingBehavior = .single) throws -> OuterRingState {
        try XCTUnwrap(AirPodsRingMapper.resolve(snapshot: snapshot(main: main, left: left, right: right), behavior: behavior, now: now))
    }

    private func snapshot(main: Int?, left: Int?, right: Int?, caseLevel: Int? = nil, observedAt: Date? = nil) -> AirPodsBatteryIconSnapshot {
        AirPodsBatteryIconSnapshot(deviceAddress: "AA:BB:CC:DD:EE:FF", model: .airPodsPro, main: main, left: left, right: right, caseLevel: caseLevel, observedAt: observedAt ?? now)
    }
}
