import SwiftUI

@MainActor
struct HighEnergyAppsView: View {
    @Environment(\.statusPanelBoldTextEnabled) private var panelBoldText
    let ranking: ApplicationEnergyRanking
    @EnvironmentObject private var localization: Localization
    @Environment(\.displayScale) private var displayScale
    private let iconCache: ApplicationEnergyIconCache

    /// The clicked row, frozen in place so the refreshing ranking cannot change
    /// or move this one row while the user aims at the ×. Other rows keep
    /// updating, mirroring Stats' single-row lock.
    @State private var armed: ArmedEnergy?
    @State private var pendingQuit: ForceQuitTarget?
    @State private var failedQuitName: String?

    private struct ArmedEnergy {
        let appID: String
        let app: EnergyApplication
        let valueText: String?
        /// The position the frozen row keeps until it is released.
        let index: Int
        let target: ForceQuitTarget

        init(_ app: EnergyApplication, _ valueText: String?, _ index: Int, _ target: ForceQuitTarget) {
            self.appID = app.id
            self.app = app
            self.valueText = valueText
            self.index = index
            self.target = target
        }
    }

    init(
        ranking: ApplicationEnergyRanking,
        iconCache: ApplicationEnergyIconCache = .shared
    ) {
        self.ranking = ranking
        self.iconCache = iconCache
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localization.string(.batteryHighEnergyApps)).font(.caption.weight(panelBoldText ? .semibold : .regular))
            if ranking.phase == .sampling {
                Text(localization.string(.batteryDetailsCollecting)).foregroundStyle(.secondary)
            } else if ranking.phase == .unavailable {
                Text(localization.string(.batteryDetailsUnavailable)).foregroundStyle(.secondary)
            } else if ranking.apps.isEmpty {
                Text(localization.string(.batteryEnergyAppsEmpty)).foregroundStyle(.secondary)
            } else {
                ForEach(displayApps) { app in
                    row(for: app, ranking: ranking)
                }
                if let failedQuitName {
                    Text(localization.format(.appForceQuitFailed, failedQuitName))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Force quit only, like Stats' popup kill, with a Cancel-defaulted
        // confirmation because it drops unsaved work.
        .alert(
            pendingQuit.map { localization.format(.appForceQuitConfirmTitle, $0.displayName) } ?? "",
            isPresented: Binding(
                get: { pendingQuit != nil },
                set: { if !$0 { pendingQuit = nil } }
            ),
            presenting: pendingQuit
        ) { target in
            Button(localization.string(.appForceQuitConfirmAction), role: .destructive) {
                performQuit(target)
            }
            Button(localization.string(.commonCancel), role: .cancel) { pendingQuit = nil }
        } message: { _ in
            Text(localization.string(.appForceQuitConfirmMessage))
        }
    }

    private func row(for app: EnergyApplication, ranking: ApplicationEnergyRanking) -> some View {
        let isArmed = armed?.appID == app.id
        return HStack(alignment: .center, spacing: 6) {
            leadingSlot(for: app, isArmed: isArmed)
            Button {
                toggleArm(app, ranking: ranking)
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    Text(app.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let text = valueText(for: app, ranking: ranking) {
                        Text(text)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel(for: app, ranking: ranking))
                .help(app.name)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            if isArmed {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
            }
        }
    }

    /// The 16pt leading slot: the app icon normally, or the force-quit × once the
    /// row is clicked when a safe target resolves. Non-app rows never show the ×.
    @ViewBuilder
    private func leadingSlot(for app: EnergyApplication, isArmed: Bool) -> some View {
        if isArmed, let target = armed?.target {
            Button {
                pendingQuit = target
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localization.format(.appForceQuitAction, target.displayName))
            .accessibilityLabel(localization.format(.appForceQuitAction, target.displayName))
        } else {
            applicationIcon(for: app)
        }
    }

    private func toggleArm(_ app: EnergyApplication, ranking: ApplicationEnergyRanking) {
        if armed?.appID == app.id {
            armed = nil
            return
        }
        guard let target = AppQuitter.target(forApplicationPath: app.id, name: app.name,
                                             running: AppQuitter.currentRunningApps()) else {
            armed = nil
            return
        }
        let index = ranking.apps.firstIndex { $0.id == app.id } ?? 0
        let frozenValue = valueText(for: app, ranking: ranking)
        armed = ArmedEnergy(app, frozenValue, index, target)
        failedQuitName = nil
    }

    private func performQuit(_ target: ForceQuitTarget) {
        pendingQuit = nil
        let succeeded = AppQuitter.forceQuit(target)
        failedQuitName = succeeded ? nil : target.displayName
        armed = nil
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

    private func rowAccessibilityLabel(for app: EnergyApplication, ranking: ApplicationEnergyRanking) -> String {
        guard let text = valueText(for: app, ranking: ranking) else { return app.name }
        return app.name + ", " + text
    }

    /// Live rows, with the armed row's frozen snapshot pinned at its original
    /// index. Only that one row is held still; the rest update in place.
    private var displayApps: [EnergyApplication] {
        guard let armed else { return ranking.apps }
        var result = ranking.apps.filter { $0.id != armed.appID }
        let index = min(max(armed.index, 0), result.count)
        result.insert(armed.app, at: index)
        return result
    }

    /// The displayed value for a row: the frozen text for the armed row, else
    /// the live ranking value.
    private func valueText(for app: EnergyApplication, ranking: ApplicationEnergyRanking) -> String? {
        if armed?.appID == app.id {
            return armed?.valueText
        }
        guard let value = ranking.values[app] else { return nil }
        return ApplicationEnergyPresentation.valueText(
            for: value,
            basis: ranking.basis,
            localization: localization
        )
    }
}
