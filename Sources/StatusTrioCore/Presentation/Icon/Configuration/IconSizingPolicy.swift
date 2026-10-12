import Foundation

/// Shared sizing contract for every item occupying the center of a status icon.
/// Percentages describe measured visible ink height, not the renderer's raw
/// point-size multiplier.
enum IconCenterSizingPolicy {
    static let percentageRange: ClosedRange<Double> = 1.0...1.8
    static let percentageStep = 0.05
    /// Shared raster calibration selected from v1.4.0 Wi-Fi scale-1.0 and
    /// scale-1.8 menu-bar/Dock ink bounds; explicit percentages share it.
    static let baselineVisibleHeight = 31.1
    /// Ignore subpixel antialias fringes so different glyph renderers share a stable ink edge.
    static let visibleInkAlphaThreshold: UInt8 = 128
    static let legacyPersistedPercentageRange: ClosedRange<Double> = 0.5...1.8
    static let legacyPercentageVisibleHeightAtRendererScaleOne = 31.0
    static let legacyWiFiVisibleHeightAtRendererScaleOne = 34.0
    /// Historical normalizedPercentageScale conversion, intentionally decoupled
    /// from the newer shared visible-size baseline above.
    private static let legacyNormalizedPercentageBaselineVisibleHeight = 28.0
    static let legacyPercentageRendererScale =
        legacyNormalizedPercentageBaselineVisibleHeight / legacyPercentageVisibleHeightAtRendererScaleOne
    static let legacyWiFiRendererScale =
        legacyNormalizedPercentageBaselineVisibleHeight / legacyWiFiVisibleHeightAtRendererScaleOne
    static let persistedScaleRange = legacyPersistedPercentageRange
    static let commonVisibleHeight = baselineVisibleHeight
    static let percentageVisibleHeightAtRendererScaleOne = legacyPercentageVisibleHeightAtRendererScaleOne
    static let wifiVisibleHeightAtRendererScaleOne = legacyWiFiVisibleHeightAtRendererScaleOne
    static let percentageScaleForCommonSize = legacyPercentageRendererScale
    static let wifiScaleForCommonPercentageSize = legacyWiFiRendererScale

    static func normalizedPercentage(_ value: Double) -> Double {
        guard value.isFinite else { return percentageRange.lowerBound }
        return min(percentageRange.upperBound, max(percentageRange.lowerBound, value))
    }

    static func drawingMultiplier(percentage: Double, referenceVisibleHeight: Double) -> Double {
        guard referenceVisibleHeight.isFinite, referenceVisibleHeight > 0 else { return 1 }
        return baselineVisibleHeight * normalizedPercentage(percentage) / referenceVisibleHeight
    }
}

/// Designer percentages are relative to the historical regular stroke while
/// persisted raw scales remain untouched for backward compatibility.
enum IconStrokeSizingPolicy {
    static let persistedScaleRange: ClosedRange<Double> = 0.5...2.5
    static let interactiveScaleRange: ClosedRange<Double> = 0.8...1.2
    static let percentageStep = 0.05
    static let baselineScale = RingStrokeStyle.regular.scale

    static func strokeScale(for percentage: Double) -> Double {
        let bounded = percentage.isFinite
            ? min(interactiveScaleRange.upperBound, max(interactiveScaleRange.lowerBound, percentage))
            : 1
        return baselineScale * bounded
    }

    static func percentage(for strokeScale: Double) -> Double {
        guard strokeScale.isFinite else { return 1 }
        return strokeScale / baselineScale
    }

    static func sliderValue(for strokeScale: Double) -> Double {
        let percentage = percentage(for: strokeScale)
        return min(interactiveScaleRange.upperBound, max(interactiveScaleRange.lowerBound, percentage))
    }

    static func label(for strokeScale: Double) -> String {
        guard strokeScale.isFinite else { return "100%" }
        return String(format: "%.0f%%", percentage(for: strokeScale) * 100)
    }
}

typealias CenterPercentageScaleCalibration = IconCenterSizingPolicy
