import Foundation

enum BatteryActionChoice: Hashable, Identifiable {
    case systemSettings
    case knownApp(KnownBatteryAppID)
    case customApplication
    case customURL

    var id: Self { self }
}
