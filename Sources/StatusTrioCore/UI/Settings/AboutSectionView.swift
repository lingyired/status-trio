import AppKit
import SwiftUI

struct AboutSectionView: View {
    @ObservedObject var updaterManager: UpdateStateFacade
    let capabilityPolicy: DistributionCapabilityPolicy
    @EnvironmentObject private var localization: Localization

    init(
        updaterManager: UpdateStateFacade = UpdateStateFacade(service: SystemManagedUpdateService()),
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault
    ) {
        self.updaterManager = updaterManager
        self.capabilityPolicy = capabilityPolicy
    }

    var body: some View {
        SettingsPage {
            SettingsGroup {
                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 18) {
                        Image(nsImage: AppIconImage.bundled() ?? NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(AppMetadata.name)
                                    .font(.system(size: 18, weight: .bold))

                                Text("v\(AppMetadata.versionDisplayString)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(0.06))
                                    )
                            }

                            Text(localization.string(.settingsAboutDescription))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(localization.string(.settingsAboutCopyright))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SettingsDivider(inset: 0)

                    AboutActionsView(
                        canCheckForUpdates: updaterManager.canCheckForUpdates,
                        showsProjectHomepage: capabilityPolicy.channel == .direct,
                        onCheckForUpdates: { updaterManager.checkForUpdates() }
                    )

                    SettingsDivider(inset: 0)

                    distributionFooter
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.vertical, 14)
            }
        }
    }

    private var distributionFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(localization.string(.settingsDistributionTitle))
                    .fontWeight(.semibold)

                Text(capabilityPolicy.channel.displayIdentity)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)

            Text(localization.string(.settingsDistributionDescription))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.tertiary)

            Text(localization.string(.settingsDistributionIndependentSettings))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.tertiary)

            Link(destination: AppMetadata.repositoryURL) {
                Label(
                    localization.string(.settingsDistributionProject),
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
        }
        .font(.system(size: 10.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AboutActionsView: View {
    @EnvironmentObject private var localization: Localization

    let canCheckForUpdates: Bool
    var showsProjectHomepage = true
    let onCheckForUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrappingHStack(spacing: 8, rowSpacing: 8) {
                Link(destination: AppMetadata.repositoryURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(localization.string(.settingsAboutStarOnGitHub))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if showsProjectHomepage {
                    Link(destination: AppMetadata.projectHomepageURL) {
                        Label(localization.string(.settingsAboutProject), systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Link(destination: AppMetadata.authorURL) {
                    Label(AppMetadata.authorName, systemImage: "person.crop.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canCheckForUpdates {
                Button(localization.string(.settingsUpdatesCheck)) {
                    onCheckForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
