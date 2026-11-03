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
        case .asset(let name):
            if let image = AboutAssets.socialIcon(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            }
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
    @State private var weChatImage: NSImage?
    @State private var isRefreshingWeChat = false
    @State private var weChatRefreshFailed = false

    var body: some View {
        VStack(spacing: 0) {
            qqRow
            SettingsDivider(inset: SettingsMetrics.rowPaddingH)
            weChatRow
        }
    }

    private var qqRow: some View {
        HStack(alignment: .center, spacing: 14) {
            qrTile(
                AboutAssets.qqQRCode,
                label: localization.string(.settingsAboutCommunityQQ)
            )

            VStack(alignment: .leading, spacing: 5) {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
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
                .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 12)
    }

    private var weChatRow: some View {
        HStack(alignment: .center, spacing: 14) {
            qrTile(
                weChatImage ?? AboutAssets.weChatQRCode,
                label: localization.string(.settingsAboutCommunityWeChat)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(localization.string(.settingsAboutCommunityWeChat))
                    .font(.system(size: 13, weight: .semibold))
                Text(localization.string(.settingsAboutCommunityWeChatDescription))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        refreshWeChatQR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text(localization.string(.settingsAboutCommunityRefresh))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRefreshingWeChat)

                    if isRefreshingWeChat {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.top, 1)

                if weChatRefreshFailed {
                    Text(localization.string(.settingsAboutCommunityRefreshFailed))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
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
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
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

    /// Pulls the latest README-hosted QR so the owner can rotate the group QR
    /// in the repository without shipping a new build. Network access happens
    /// only on this explicit tap — no polling.
    private func refreshWeChatQR() {
        guard !isRefreshingWeChat else { return }
        isRefreshingWeChat = true
        weChatRefreshFailed = false
        Task { @MainActor in
            defer { isRefreshingWeChat = false }
            for url in AppMetadata.weChatGroupImageURLs {
                if let image = await Self.fetchImage(url) {
                    weChatImage = AboutAssets.normalizedWeChatQR(image)
                    return
                }
            }
            weChatRefreshFailed = true
        }
    }

    private static func fetchImage(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let image = NSImage(data: data)
            else {
                return nil
            }
            return image
        } catch {
            return nil
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
        HStack(alignment: .top, spacing: 12) {
            icon
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(localization.string(app.subtitleKey))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                WrappingHStack(spacing: 6, rowSpacing: 6) {
                    ForEach(Array(app.links.enumerated()), id: \.offset) { _, link in
                        Link(destination: link.url) {
                            HStack(spacing: 4) {
                                storeGlyph(link.icon)
                                Text(title(for: link.label))
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("\(app.name) — \(title(for: link.label))")
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 11)
    }

    private func title(for label: AboutAppLink.LinkLabel) -> String {
        switch label {
        case .literal(let text):
            return text
        case .key(let key):
            return localization.string(key)
        }
    }

    @ViewBuilder
    private func storeGlyph(_ icon: AboutAppLink.StoreIcon?) -> some View {
        if let icon {
            switch icon {
            case .asset(let name):
                if let image = AboutAssets.storeIcon(named: name) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                }
            case .systemImage(let name):
                Image(systemName: name)
                    .font(.system(size: 11))
            }
        }
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
