import Foundation

/// The value shown on the battery details page's High Power Mode row. Kept pure
/// so the "supported / off / unsupported / cannot read" branches are covered
/// without constructing the whole detail page.
enum BatteryHighPowerRowPresentation {
    @MainActor
    static func value(
        hasProbed: Bool,
        isSupported: Bool,
        isHighPowerMode: Bool,
        showsControl: Bool,
        localization: Localization
    ) -> String {
        if hasProbed {
            guard isSupported else {
                return localization.string(.batteryDetailsHighPowerUnsupported)
            }
            return localization.string(
                isHighPowerMode ? .batteryDetailsOn : .batteryDetailsOff
            )
        }
        return localization.string(
            showsControl ? .batteryDetailsLoading : .batteryDetailsHighPowerDisabled
        )
    }
}
