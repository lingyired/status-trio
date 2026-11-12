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

/// The first-launch choice about joining Wi-Fi networks from the panel. It
/// starts unchecked, and is recorded once so no later guide asks again.
struct WiFiJoinChoiceDraft {
    var joinsInApp = false

    @MainActor func acknowledge(settings: SettingsStore) {
        guard !settings.hasAnsweredWiFiJoinPrompt else { return }
        settings.completeWiFiJoinPrompt(joinsInApp: joinsInApp)
    }
}

struct TelemetryConsentDraft {
    var sharesAnalytics = false

    @MainActor func acknowledge(settings: SettingsStore) {
        guard settings.telemetryConsentVersion == 0 else { return }
        settings.completeTelemetryConsent(sharesAnalytics: sharesAnalytics)
    }
}
