@MainActor
enum IconGuideOnboardingPolicy {
    static func consumeIfNeeded(settings: SettingsStore) -> Bool {
        guard !settings.hasCompletedIconGuideOnboarding else { return false }
        settings.hasCompletedIconGuideOnboarding = true
        return true
    }

    static func shouldPresentGuide(settings: SettingsStore) -> Bool {
        let isNewGuide = consumeIfNeeded(settings: settings)
        return isNewGuide || settings.telemetryConsentVersion == 0
    }
}

struct TelemetryConsentDraft {
    var sharesAnalytics = true

    @MainActor func acknowledge(settings: SettingsStore) {
        guard settings.telemetryConsentVersion == 0 else { return }
        settings.completeTelemetryConsent(sharesAnalytics: sharesAnalytics)
    }
}
