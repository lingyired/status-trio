import Foundation

struct KnownBatteryAppDefinition: Equatable {
    let id: KnownBatteryAppID
    let displayName: String
    let bundleIdentifiers: [String]
    let deepLink: URL?
}

enum KnownBatteryApps {
    private static let alDente = KnownBatteryAppDefinition(
        id: .alDente,
        displayName: "AlDente",
        bundleIdentifiers: ["com.apphousekitchen.aldente-pro"],
        deepLink: nil
    )

    private static let batFi = KnownBatteryAppDefinition(
        id: .batFi,
        displayName: "BatFi",
        bundleIdentifiers: ["software.micropixels.BatFi"],
        deepLink: nil
    )

    static let all = [alDente, batFi]

    static func definition(for id: KnownBatteryAppID) -> KnownBatteryAppDefinition {
        switch id {
        case .alDente: alDente
        case .batFi: batFi
        }
    }
}
