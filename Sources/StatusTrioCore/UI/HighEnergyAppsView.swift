import SwiftUI

@MainActor
struct HighEnergyAppsView: View {
    let ranking: ApplicationEnergyRanking
    @EnvironmentObject private var localization: Localization
    @Environment(\.displayScale) private var displayScale
    private let iconCache: ApplicationEnergyIconCache

    init(
        ranking: ApplicationEnergyRanking,
        iconCache: ApplicationEnergyIconCache = .shared
    ) {
        self.ranking = ranking
        self.iconCache = iconCache
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localization.string(.batteryHighEnergyApps)).font(.caption.weight(.semibold))
            if ranking.phase == .sampling {
                Text(localization.string(.batteryDetailsCollecting)).foregroundStyle(.secondary)
            } else if ranking.phase == .unavailable {
                Text(localization.string(.batteryDetailsUnavailable)).foregroundStyle(.secondary)
            } else if ranking.apps.isEmpty {
                Text(localization.string(.batteryEnergyAppsEmpty)).foregroundStyle(.secondary)
            } else {
                ForEach(ranking.apps) { app in
                    HStack(alignment: .center, spacing: 6) {
                        applicationIcon(for: app)
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let value = ranking.values[app] {
                            Text(ApplicationEnergyPresentation.valueText(
                                for: value,
                                basis: ranking.basis,
                                localization: localization
                            ))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(rowAccessibilityLabel(for: app))
                        .help(app.name)
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func applicationIcon(for app: EnergyApplication) -> some View {
        if let image = iconCache.image(for: app.id, pixelLength: iconPixelLength) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var iconPixelLength: Int {
        max(1, Int((16 * displayScale).rounded(.up)))
    }

    private func rowAccessibilityLabel(for app: EnergyApplication) -> String {
        guard let value = ranking.values[app] else { return app.name }
        return app.name + ", " + ApplicationEnergyPresentation.valueText(
            for: value,
            basis: ranking.basis,
            localization: localization
        )
    }
}
