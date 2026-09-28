import CoreGraphics
import Foundation

enum StatusIconGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 120, height: 120)

    /// The x coordinate every element of the icon is centred on.
    ///
    /// This is deliberately **not** `canvas.midX`. The artwork is drawn on a
    /// 119-unit-wide box: `status-menubar.svg` runs the battery arc from
    /// `x = 15.5` to `x = 103.5`, so `(15.5 + 103.5) / 2 = 59.5`. The canvas is
    /// 120 wide, making `canvas.midX = 60.0`. Anchoring anything to the canvas
    /// midpoint instead of this constant shifts it half a unit right of all the
    /// hand-drawn art, which is what shipped in 1.3.x and is issue #30.
    static let artworkCenterX: CGFloat = 59.5

    // Derived from the SVG battery endpoints and radius.
    private static let batteryRadius: CGFloat = 51.5
    private static let batteryCenter = CGPoint(x: artworkCenterX, y: 61.48715261785473)
    private static let batteryStart: CGFloat = 148.69008689281117 * .pi / 180
    private static let batterySweep: CGFloat = 242.6198262143777 * .pi / 180
    static let batteryValueTopGapWidth: CGFloat = 64
    static let batteryChargingBoltTopGapWidth: CGFloat = 50

    static let batteryValueBaseFontSize: CGFloat = 20
    static let batteryChargingBoltCalibration: CGFloat = 220.0 / 180.0

    /// SF Symbol drawn in the top gap when the battery is connected to power
    /// without charging.
    static let batteryPlugSymbolName = "powerplug.portrait.fill"

    /// Optical size of the plug relative to the bolt. The plug's strokes are
    /// thinner than the bolt's solid body, so it is drawn slightly taller to
    /// carry the same visual weight in the gap.
    static let batteryPlugHeightScale: CGFloat = 1.2

    /// The bolt scales away from its tip, so any other glyph in the top gap
    /// shares the scaled bolt's center to stay optically aligned with it.
    static func batteryTopIndicatorCenter(boltScale: CGFloat) -> CGPoint {
        let bolt = batteryChargingBolt().boundingBoxOfPath
        let pivot = batteryChargingBoltPivot
        return CGPoint(
            x: pivot.x + (bolt.midX - pivot.x) * boltScale,
            y: pivot.y + (bolt.midY - pivot.y) * boltScale
        )
    }

    static func batteryValueBaseline(fontSize: CGFloat) -> CGPoint {
        let referenceFontSize: CGFloat = 20
        let referenceBaseline: CGFloat = 17
        let currentFontSize: CGFloat = 32
        let currentBaseline: CGFloat = 24
        let slope = (currentBaseline - referenceBaseline) / (currentFontSize - referenceFontSize)
        return CGPoint(
            x: artworkCenterX,
            y: referenceBaseline + (fontSize - referenceFontSize) * slope
        )
    }

    private static let wifiOuterCenter = CGPoint(x: artworkCenterX, y: 78.3)
    private static let wifiOuterRadius: CGFloat = 31
    private static let wifiOuterStart: CGFloat = 227.35 * .pi / 180
    private static let wifiOuterEnd: CGFloat = 312.65 * .pi / 180

    static func batteryPoint(forProgress progress: Double) -> CGPoint {
        let clampedProgress = clampedUnit(progress)
        let angle = batteryStart + batterySweep * CGFloat(clampedProgress)
        return CGPoint(
            x: batteryCenter.x + batteryRadius * cos(angle),
            y: batteryCenter.y + batteryRadius * sin(angle)
        )
    }

    static func batteryTrack(
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        batteryArc(
            from: 0,
            to: 1,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
    }

    static func batteryFill(
        progress: Double,
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        batteryArc(
            from: 0,
            to: progress,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
    }

    /// A visible segment of the battery's progress-space arc. Progress inside
    /// the top gap is intentionally absent from the returned path.
    static func batteryHighlight(
        from start: Double,
        to end: Double,
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        batteryArc(
            from: start,
            to: end,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
    }

    /// Maps battery progress to the normalized length of its visible arc. All
    /// progress values inside a gap share the midpoint because no point there
    /// is visible; round trips are defined on the visible segments.
    static func visibleFraction(
        forProgress progress: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> Double {
        let clampedProgress = clampedUnit(progress)
        guard hasTopGap else { return clampedProgress }

        let gap = batteryGapFraction(topGapWidth: topGapWidth)
        let gapStart = (1 - gap) / 2
        let gapEnd = gapStart + gap
        if clampedProgress <= gapStart {
            return clampedProgress
        }
        if clampedProgress >= gapEnd {
            return clampedProgress - gap
        }
        return gapStart
    }

    /// Maps a normalized visible-arc coordinate back to progress space. At the
    /// exact midpoint, the left edge is selected deterministically.
    static func progress(
        forVisibleFraction fraction: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> Double {
        let clampedFraction = clampedUnit(fraction)
        guard hasTopGap else { return clampedFraction }

        let gap = batteryGapFraction(topGapWidth: topGapWidth)
        let visibleLength = 1 - gap
        guard visibleLength > 0 else { return 0 }

        let visibleCoordinate = min(visibleLength, clampedFraction)
        let gapStart = visibleLength / 2
        if visibleCoordinate <= gapStart {
            return visibleCoordinate
        }
        return visibleCoordinate + gap
    }

    /// Stops the charging-effect endpoint at the left edge if the battery fill
    /// currently ends inside the top gap.
    static func lastVisibleProgress(
        forProgress progress: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> Double {
        let clampedProgress = clampedUnit(progress)
        guard hasTopGap else { return clampedProgress }

        let gap = batteryGapFraction(topGapWidth: topGapWidth)
        let gapStart = (1 - gap) / 2
        let gapEnd = gapStart + gap
        guard clampedProgress > gapStart, clampedProgress < gapEnd else {
            return clampedProgress
        }
        return gapStart
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func batteryGapFraction(topGapWidth: CGFloat) -> Double {
        guard topGapWidth.isFinite, topGapWidth > 0 else { return 0 }
        let arcLength = batteryRadius * batterySweep
        guard arcLength.isFinite, arcLength > 0 else { return 0 }
        return min(1, max(0, Double(topGapWidth / arcLength)))
    }

    static func batteryChargingBolt(scale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 62.1, y: 2.2))
        path.addQuadCurve(
            to: CGPoint(x: 62.6, y: 3.3),
            control: CGPoint(x: 62.8, y: 2.5)
        )
        path.addLine(to: CGPoint(x: 61.2, y: 7.8))
        path.addLine(to: CGPoint(x: 65.9, y: 7.8))
        path.addQuadCurve(
            to: CGPoint(x: 67.3, y: 8.6),
            control: CGPoint(x: 66.9, y: 7.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: 67, y: 10),
            control: CGPoint(x: 67.6, y: 9.3)
        )
        path.addLine(to: CGPoint(x: 57, y: 21.3))
        path.addQuadCurve(
            to: CGPoint(x: 55.6, y: 21.6),
            control: CGPoint(x: 56.4, y: 22)
        )
        path.addQuadCurve(
            to: CGPoint(x: 55.3, y: 20.5),
            control: CGPoint(x: 55, y: 21.3)
        )
        path.addLine(to: CGPoint(x: 57.4, y: 14.1))
        path.addLine(to: CGPoint(x: 52.9, y: 14.1))
        path.addQuadCurve(
            to: CGPoint(x: 51.6, y: 13.3),
            control: CGPoint(x: 52, y: 14.1)
        )
        path.addQuadCurve(
            to: CGPoint(x: 51.9, y: 12),
            control: CGPoint(x: 51.3, y: 12.6)
        )
        path.addLine(to: CGPoint(x: 61.1, y: 2.7))
        path.addQuadCurve(
            to: CGPoint(x: 62.1, y: 2.2),
            control: CGPoint(x: 61.6, y: 2.1)
        )
        path.closeSubpath()

        guard scale.isFinite, scale > 0, scale != 1 else { return path }
        let pivot = batteryChargingBoltPivot
        var transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: pivot.x * (1 - scale),
            ty: pivot.y * (1 - scale)
        )
        return path.copy(using: &transform) ?? path
    }

    static func batteryChargingBolt(
        basePath: CGPath,
        centeredScale scale: CGFloat,
        fitting canvas: CGRect
    ) -> CGPath {
        guard scale.isFinite, scale > 0, scale != 1 else { return basePath }
        let bounds = basePath.boundingBoxOfPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let verticalScale = min(
            scale,
            min(
                (center.y - canvas.minY) / (center.y - bounds.minY),
                (canvas.maxY - center.y) / (bounds.maxY - center.y)
            )
        )
        var transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: verticalScale,
            tx: center.x * (1 - scale),
            ty: center.y * (1 - verticalScale)
        )
        return basePath.copy(using: &transform) ?? basePath
    }

    static let batteryChargingBoltPivot = CGPoint(x: artworkCenterX, y: 2.1)

    static func wifiArcs(level: Int) -> [CGPath] {
        let bars = min(3, max(0, level))
        let middle = arc(
            center: CGPoint(x: artworkCenterX, y: 78.89),
            radius: 18.5,
            start: 227.5 * .pi / 180,
            end: 312.5 * .pi / 180
        )

        switch bars {
        case 3:
            return [wifiOuterArc(), middle]
        case 2:
            return [middle]
        case 1:
            // Level 1 intentionally returns no arcs because the dot is drawn separately.
            return []
        default:
            return []
        }
    }

    static func wifiOuterArc() -> CGPath {
        arc(
            center: wifiOuterCenter,
            radius: wifiOuterRadius,
            start: wifiOuterStart,
            end: wifiOuterEnd
        )
    }

    static let ethernetStrokeWidth: CGFloat = 4.886659979939819
    static let ethernetDotRadius: CGFloat = 2.4433299899699095

    private static let ethernetSourceBounds = CGRect(
        x: 56.132,
        y: 75.812,
        width: 87.736,
        height: 46.376
    )
    private static let ethernetTargetBounds = CGRect(
        x: 31.5,
        y: 51.19959879638917,
        width: 56,
        height: 29.60080240722166
    )

    static func ethernetChevrons() -> [CGPath] {
        let left = ethernetPolyline([
            CGPoint(x: 79.32, y: 79.64),
            CGPoint(x: 59.96, y: 99),
            CGPoint(x: 79.32, y: 118.36)
        ])
        let right = ethernetPolyline([
            CGPoint(x: 120.68, y: 79.64),
            CGPoint(x: 140.04, y: 99),
            CGPoint(x: 120.68, y: 118.36)
        ])
        return [left, right]
    }

    static func ethernetDots() -> [CGPoint] {
        [
            ethernetPoint(x: 84.688, y: 99),
            ethernetPoint(x: 100, y: 99),
            ethernetPoint(x: 115.312, y: 99)
        ]
    }

    private static func ethernetPolyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: ethernetPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: ethernetPoint(x: point.x, y: point.y))
        }
        return path
    }

    private static func ethernetPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        let scaleX = ethernetTargetBounds.width / ethernetSourceBounds.width
        let scaleY = ethernetTargetBounds.height / ethernetSourceBounds.height
        return CGPoint(
            x: ethernetTargetBounds.minX + (x - ethernetSourceBounds.minX) * scaleX,
            y: ethernetTargetBounds.minY + (y - ethernetSourceBounds.minY) * scaleY
        )
    }

    static func temporaryWedge() -> CGPath {
        let path = CGMutablePath()
        path.addPath(wifiOuterArc())
        path.addLine(to: CGPoint(x: artworkCenterX, y: 77.45))
        path.closeSubpath()
        return path
    }

    static func temporaryScreenOutline() -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: 50.5, y: 53.5, width: 18, height: 12),
            cornerWidth: 2.5,
            cornerHeight: 2.5
        )
        return path
    }

    static func temporaryScreenStand() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 57.5, y: 65.5))
        path.addLine(to: CGPoint(x: 61.5, y: 65.5))
        path.addLine(to: CGPoint(x: 61.5, y: 67.5))
        path.addLine(to: CGPoint(x: 63, y: 67.5))
        path.addLine(to: CGPoint(x: 63, y: 70.5))
        path.addLine(to: CGPoint(x: 56, y: 70.5))
        path.addLine(to: CGPoint(x: 56, y: 67.5))
        path.addLine(to: CGPoint(x: 57.5, y: 67.5))
        path.closeSubpath()
        return path
    }

    static func sharedWedge() -> CGPath {
        temporaryWedge()
    }

    static func sharedArrowCutout() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: artworkCenterX, y: 51.5))
        path.addLine(to: CGPoint(x: 67.5, y: 59.5))
        path.addLine(to: CGPoint(x: 63, y: 59.5))
        path.addLine(to: CGPoint(x: 63, y: 72.5))
        path.addLine(to: CGPoint(x: 56, y: 72.5))
        path.addLine(to: CGPoint(x: 56, y: 59.5))
        path.addLine(to: CGPoint(x: 51.5, y: 59.5))
        path.closeSubpath()
        return path
    }

    static func wifiDot() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: artworkCenterX, y: 69.9))
        path.addCurve(to: CGPoint(x: 66.5, y: 73), control1: CGPoint(x: 61.0, y: 69.9), control2: CGPoint(x: 65.2, y: 70.8))
        path.addCurve(to: CGPoint(x: 66.5, y: 75), control1: CGPoint(x: 66.7, y: 73.8), control2: CGPoint(x: 66.7, y: 74.3))
        path.addCurve(to: CGPoint(x: artworkCenterX, y: 80.95), control1: CGPoint(x: 63.8, y: 78.8), control2: CGPoint(x: 61.15, y: 80.95))
        path.addCurve(to: CGPoint(x: 52.5, y: 75), control1: CGPoint(x: 57.85, y: 80.95), control2: CGPoint(x: 55.2, y: 78.8))
        path.addCurve(to: CGPoint(x: 52.5, y: 73), control1: CGPoint(x: 52.3, y: 74.3), control2: CGPoint(x: 52.3, y: 73.8))
        path.addCurve(to: CGPoint(x: artworkCenterX, y: 69.9), control1: CGPoint(x: 53.8, y: 70.8), control2: CGPoint(x: 58.0, y: 69.9))
        path.closeSubpath()
        return path
    }

    static func wifiOffSlash() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 39, y: 46))
        path.addLine(to: CGPoint(x: 81, y: 79))
        return path
    }

    static func noInternetOverlay() -> (stem: CGPath, dot: CGPath) {
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: artworkCenterX, y: 54.5))
        stem.addLine(to: CGPoint(x: artworkCenterX, y: 67))

        let dot = CGMutablePath()
        dot.addEllipse(in: CGRect(x: 56.9, y: 72.9, width: 5.2, height: 5.2))
        return (stem, dot)
    }

    static func hotspotOverlay() -> [CGPath] {
        let left = CGMutablePath()
        left.move(to: CGPoint(x: 53, y: 66))
        left.addLine(to: CGPoint(x: 49, y: 66))
        left.addArc(center: CGPoint(x: 49, y: 58), radius: 8, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        left.addLine(to: CGPoint(x: 54, y: 50))

        let right = CGMutablePath()
        right.move(to: CGPoint(x: 66, y: 50))
        right.addLine(to: CGPoint(x: 70, y: 50))
        right.addArc(center: CGPoint(x: 70, y: 58), radius: 8, startAngle: 3 * .pi / 2, endAngle: 5 * .pi / 2, clockwise: false)
        right.addLine(to: CGPoint(x: 65, y: 66))

        let bridge = CGMutablePath()
        bridge.move(to: CGPoint(x: 51, y: 58))
        bridge.addLine(to: CGPoint(x: 68, y: 58))
        return [left, right, bridge]
    }

    static func volumeDots() -> [CGPoint] {
        [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8)
        ]
    }

    static let volumeDotRadius: CGFloat = 5.5

    static let volumeArcStartAngle: CGFloat = 121.82 * .pi / 180
    static let volumeArcEndAngle: CGFloat = 59.12 * .pi / 180

    static func volumeArcTrack() -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: batteryCenter,
            radius: batteryRadius,
            startAngle: volumeArcStartAngle,
            endAngle: volumeArcEndAngle,
            clockwise: true
        )
        return path
    }

    static func volumeArcFill(progress: Double) -> CGPath {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return CGMutablePath() }
        let sweep = volumeArcStartAngle - volumeArcEndAngle
        let end = volumeArcStartAngle - sweep * CGFloat(clamped)
        let path = CGMutablePath()
        path.addArc(
            center: batteryCenter,
            radius: batteryRadius,
            startAngle: volumeArcStartAngle,
            endAngle: end,
            clockwise: true
        )
        return path
    }

    static func batteryArc(
        from start: Double,
        to end: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat
    ) -> CGPath {
        guard start.isFinite, end.isFinite else { return CGMutablePath() }
        let clampedStart = clampedUnit(start)
        let clampedEnd = clampedUnit(end)
        guard clampedEnd > clampedStart else { return CGMutablePath() }

        let path = CGMutablePath()
        guard hasTopGap else {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(clampedStart),
                end: batteryStart + batterySweep * CGFloat(clampedEnd)
            ))
            return path
        }

        let gapFraction = batteryGapFraction(topGapWidth: topGapWidth)
        let gapStartProgress = (1 - gapFraction) / 2
        let gapEndProgress = gapStartProgress + gapFraction

        let firstSegmentEnd = min(clampedEnd, gapStartProgress)
        if firstSegmentEnd > clampedStart {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(clampedStart),
                end: batteryStart + batterySweep * CGFloat(firstSegmentEnd)
            ))
        }

        let secondSegmentStart = max(clampedStart, gapEndProgress)
        if clampedEnd > secondSegmentStart {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(secondSegmentStart),
                end: batteryStart + batterySweep * CGFloat(clampedEnd)
            ))
        }
        return path
    }

    private static func arc(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}
