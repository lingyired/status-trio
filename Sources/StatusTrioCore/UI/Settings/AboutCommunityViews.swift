import AppKit
import SwiftUI

/// "Follow the Author" group: a wrapping row of social chips. X is always
/// present; the Chinese-only networks come from `AboutContentCatalog`.
struct AboutSocialLinksView: View {
    @EnvironmentObject private var localization: Localization

    var body: some View {
        let links = AboutContentCatalog.socialLinks(for: localization.resolvedLanguage)
        WrappingHStack(spacing: 8, rowSpacing: 8) {
            ForEach(links) { link in
                Link(destination: link.url) {
                    HStack(spacing: 5) {
                        glyph(for: link)
                        Text(label(for: link))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func glyph(for link: AboutSocialLink) -> some View {
        switch link.glyph {
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .bold))
        case .systemImage(let name):
            Image(systemName: name)
        }
    }

    private func label(for link: AboutSocialLink) -> String {
        if let key = link.titleKey {
            return localization.string(key)
        }
        return "@lingyired"
    }
}

/// "Join the Community" group (Chinese only): the QQ group number with a copy
/// button, and the WeChat group QR code.
struct AboutCommunityView: View {
    @EnvironmentObject private var localization: Localization

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            qqRow
            SettingsDivider(inset: SettingsMetrics.rowPaddingH)
            weChatRow
        }
    }

    private var qqRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string(.settingsAboutCommunityQQ))
                    .font(.system(size: 13, weight: .semibold))
                Text(localization.string(.settingsAboutCommunityQQDescription))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(AppMetadata.qqGroupNumber)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        copyGroupNumber()
                    } label: {
                        Text(
                            localization.string(
                                copied
                                    ? LocalizationKey.settingsAboutCommunityCopied
                                    : LocalizationKey.settingsAboutCommunityCopy
                            )
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Spacer(minLength: 8)

            qrTile(
                AboutAssets.qqQRCode,
                label: localization.string(.settingsAboutCommunityQQ)
            )
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 12)
    }

    private var weChatRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.string(.settingsAboutCommunityWeChat))
                    .font(.system(size: 13, weight: .semibold))
                Text(localization.string(.settingsAboutCommunityWeChatDescription))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            qrTile(
                AboutAssets.weChatQRCode,
                label: localization.string(.settingsAboutCommunityWeChat)
            )
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func qrTile(_ image: NSImage?, label: String) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }

    private func copyGroupNumber() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppMetadata.qqGroupNumber, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }
}

/// "More Apps" group: a tappable list of the author's other apps.
struct AboutMoreAppsView: View {
    @EnvironmentObject private var localization: Localization

    var body: some View {
        let apps = AboutContentCatalog.apps(for: localization.resolvedLanguage)
        VStack(spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                AboutAppRow(app: app)
                if index < apps.count - 1 {
                    SettingsDivider(inset: SettingsMetrics.rowPaddingH)
                }
            }
        }
    }
}

private struct AboutAppRow: View {
    @EnvironmentObject private var localization: Localization

    let app: AboutAppLink

    var body: some View {
        Link(destination: app.url) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(localization.string(app.subtitleKey))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(localization.string(.settingsAboutMoreAppsOpen))
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }
            .contentShape(Rectangle())
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(app.name) — \(localization.string(.settingsAboutMoreAppsOpen))")
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AboutAssets.appIcon(for: app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        }
    }
}
