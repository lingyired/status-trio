import Foundation

/// Projects a `BrightnessStatus` into panel-ready rows.
@MainActor
enum BrightnessPanelMapper {
    static func map(
        _ status: BrightnessStatus,
        localization: Localization
    ) -> BrightnessPanelState {
        let rows = status.displays.map { display in
            let percentageText = display.scalar.map(percentText) ?? ""
            let unavailableText = display.canAdjust
                ? nil
                : unavailableText(for: display.source, localization: localization)
            let accessibility: String
            if display.canAdjust {
                accessibility = localization.format(
                    .brightnessRowAccessibility,
                    display.name,
                    percentageText
                )
            } else {
                accessibility = localization.format(
                    .brightnessRowAccessibilityUnavailable,
                    display.name,
                    unavailableText ?? ""
                )
            }
            return BrightnessRowState(
                id: display.id,
                name: display.name,
                isBuiltin: display.isBuiltin,
                scalar: display.canAdjust ? display.scalar : nil,
                canAdjust: display.canAdjust,
                backend: display.backend,
                source: display.source,
                percentageText: percentageText,
                accessibilityLabel: accessibility,
                unavailableText: unavailableText
            )
        }
        return BrightnessPanelState(
            rows: rows,
            transitionGeneration: status.transitionGeneration
        )
    }

    static func percentText(_ scalar: Double) -> String {
        let clamped = min(1, max(0, scalar))
        return "\(Int((clamped * 100).rounded()))%"
    }

    private static func unavailableText(
        for source: BrightnessControlSource,
        localization: Localization
    ) -> String {
        switch source {
        case .directDDC, .displayServices, .betterDisplay:
            // Adjustable sources never reach here; keep a safe fallback.
            return localization.string(.brightnessUnavailable)
        case .unavailable(let reason):
            switch reason {
            case .appAbsent:
                return localization.string(.brightnessAppAbsent)
            case .noBackend:
                return localization.string(.brightnessNoBackend)
            case .writeNotConfirmed, .unresponsive:
                return localization.string(.brightnessUnresponsive)
            case .resolveFailed, .readFailed, .timeout, .unsupportedVCP:
                return localization.string(.brightnessUnavailable)
            }
        }
    }
}
