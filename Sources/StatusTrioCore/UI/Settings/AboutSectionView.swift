import AppKit
import SwiftUI

struct AboutSectionView: View {
    @ObservedObject private var updaterManager: UpdaterManager = .shared
    @EnvironmentObject private var localization: Localization

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

                    HStack(spacing: 8) {
                        Link(destination: AppMetadata.repositoryURL) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text(localization.string(.settingsAboutStarOnGitHub))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Link(destination: AppMetadata.repositoryURL) {
                            Label(localization.string(.settingsAboutRepository), systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Link(destination: AppMetadata.authorURL) {
                            Label(AppMetadata.authorName, systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        if updaterManager.canCheckForUpdates {
                            Button(localization.string(.settingsUpdatesCheck)) {
                                updaterManager.checkForUpdates()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.vertical, 14)
            }
        }
    }
}
