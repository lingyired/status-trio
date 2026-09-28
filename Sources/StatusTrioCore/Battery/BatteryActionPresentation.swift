import Foundation

@MainActor
enum BatteryActionPresentation {
    static func openLabel(for target: BatteryActionTarget, localization: Localization) -> String {
        switch target {
        case .systemSettings:
            localization.string(.batteryActionOpenSettings)
        case .knownApp, .customApp, .customURL:
            localization.format(
                .batteryActionOpenTarget,
                selectionName(for: target, localization: localization)
            )
        }
    }

    static func selectionName(for target: BatteryActionTarget, localization: Localization) -> String {
        switch target {
        case .systemSettings:
            localization.string(.batteryActionSystemSettings)
        case .knownApp(let id):
            KnownBatteryApps.definition(for: id).displayName
        case .customApp(let application):
            application.displayName
        case .customURL:
            localization.string(.batteryActionCustomLink)
        }
    }
}
