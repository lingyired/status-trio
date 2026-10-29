@MainActor
enum IconGuideOnboardingPolicy {
    static func consumeIfNeeded(settings: SettingsStore) -> Bool {
        guard !settings.hasCompletedIconGuideOnboarding else { return false }
        settings.hasCompletedIconGuideOnboarding = true
        return true
    }

    static func shouldPresentGuide(
        settings: SettingsStore,
        channel: DistributionChannel = .current
    ) -> Bool {
        let isNewGuide = consumeIfNeeded(settings: settings)
        return isNewGuide || showsTelemetryConsent(settings: settings, channel: channel)
    }

    static func showsTelemetryConsent(
        settings: SettingsStore,
        channel: DistributionChannel
    ) -> Bool {
        channel == .direct && settings.telemetryConsentVersion == 0
    }
}

struct TelemetryConsentDraft {
    var sharesAnalytics = false

    @MainActor func acknowledge(
        settings: SettingsStore,
        allowsTelemetryConsent: Bool = true
    ) {
        guard allowsTelemetryConsent else { return }
        guard settings.telemetryConsentVersion == 0 else { return }
        settings.completeTelemetryConsent(sharesAnalytics: sharesAnalytics)
    }
}
