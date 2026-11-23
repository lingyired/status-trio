import Foundation

@MainActor
extension SettingsStore {
    /// Direct keeps the migration marker Sparkle writes. Store calls the shared
    /// initializer with its own channel-specific marker instead.
    convenience init(
        defaults: UserDefaults = .standard,
        chargeLimitProvider: any SystemChargeLimitProviding = SystemChargeLimitReader()
    ) {
        self.init(
            defaults: defaults,
            chargeLimitProvider: chargeLimitProvider,
            legacyInstallationMarker: { defaults in
                defaults.bool(forKey: "SUHasLaunchedBefore")
            }
        )
    }
}
