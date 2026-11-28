import Foundation

@MainActor
enum ApplicationEnergyPresentation {
    static func valueText(
        for value: Double,
        basis: ApplicationEnergyRanking.Basis,
        localization: Localization
    ) -> String {
        guard value.isFinite else { return "—" }
        let locale = localization.resolvedLanguage.locale

        switch basis {
        case .cpuAndGPU, .cpuEnergy, .gpuEnergy:
            if value >= 1 {
                return value.formatted(
                    .number.precision(.fractionLength(2)).locale(locale)
                ) + " W"
            }
            return (value * 1_000).formatted(
                .number.precision(.fractionLength(1)).locale(locale)
            ) + " mW"
        case .cpuActivity:
            return (value * 100).formatted(
                .number.precision(.fractionLength(1)).locale(locale)
            ) + "%"
        }
    }

    static func titleKey(for basis: ApplicationEnergyRanking.Basis) -> LocalizationKey {
        switch basis {
        case .cpuAndGPU: return .batteryEnergyAppsTitle
        case .cpuEnergy: return .batteryEnergyCPUAppsTitle
        case .gpuEnergy: return .batteryEnergyGPUAppsTitle
        case .cpuActivity: return .batteryEnergyActivityTitle
        }
    }
}
