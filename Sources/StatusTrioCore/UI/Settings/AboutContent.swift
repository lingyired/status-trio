import AppKit
import Foundation

/// One chip in the About page's "Follow the Author" group.
///
/// `X` is shown in every language; the Chinese-only networks are appended when
/// the resolved app language is Chinese. Keeping this as data (not inline view
/// code) lets the gating be unit-tested without rendering SwiftUI.
struct AboutSocialLink: Identifiable, Equatable {
    enum Network: String, CaseIterable {
        case x
        case douyin
        case xiaohongshu
        case bilibili
        case blog
    }

    /// A tiny leading mark for the chip. SF Symbols are not available for every
    /// Chinese network, so those use a short native-language monogram instead.
    enum Glyph: Equatable {
        case text(String)
        case systemImage(String)
    }

    let network: Network
    let url: URL
    /// `nil` for X, whose label is the fixed literal `"X · @lingyired"`.
    let titleKey: LocalizationKey?
    let glyph: Glyph
    let chineseOnly: Bool

    var id: Network { network }
}

/// One row in the About page's "More Apps" list.
struct AboutAppLink: Identifiable, Equatable {
    enum Identity: String, CaseIterable {
        case newtab01
        case noLazyload
        case fund01
    }

    let identity: Identity
    let name: String
    let subtitleKey: LocalizationKey
    let url: URL
    /// Base name (without extension) of the bundled app icon PNG.
    let iconResource: String
    let chineseOnly: Bool

    var id: Identity { identity }
}

/// The About page's dynamic content: which author links and companion apps to
/// show for a given language. The Chinese-only entries follow the product rule
/// that the QQ/WeChat community, the Chinese social networks, the Chinese blog
/// and fund01 are only relevant to Chinese-speaking users.
enum AboutContentCatalog {
    static func socialLinks(for language: AppLanguage) -> [AboutSocialLink] {
        var links: [AboutSocialLink] = [
            AboutSocialLink(
                network: .x,
                url: AppMetadata.authorXURL,
                titleKey: nil,
                glyph: .text("𝕏"),
                chineseOnly: false
            )
        ]

        guard language.isChinese else { return links }

        links.append(
            AboutSocialLink(
                network: .douyin,
                url: AppMetadata.authorDouyinURL,
                titleKey: .settingsAboutSocialDouyin,
                glyph: .text("抖"),
                chineseOnly: true
            )
        )
        links.append(
            AboutSocialLink(
                network: .xiaohongshu,
                url: AppMetadata.authorXiaohongshuURL,
                titleKey: .settingsAboutSocialXiaohongshu,
                glyph: .text("红"),
                chineseOnly: true
            )
        )
        links.append(
            AboutSocialLink(
                network: .bilibili,
                url: AppMetadata.authorBilibiliURL,
                titleKey: .settingsAboutSocialBilibili,
                glyph: .text("B"),
                chineseOnly: true
            )
        )
        links.append(
            AboutSocialLink(
                network: .blog,
                url: AppMetadata.authorWebsiteURL,
                titleKey: .settingsAboutSocialBlog,
                glyph: .systemImage("globe"),
                chineseOnly: true
            )
        )
        return links
    }

    static func apps(for language: AppLanguage) -> [AboutAppLink] {
        var apps: [AboutAppLink] = [
            AboutAppLink(
                identity: .newtab01,
                name: "newtab01",
                subtitleKey: .settingsAboutMoreAppsNewtab01Description,
                url: AppMetadata.newtab01URL,
                iconResource: "AboutAppNewtab01",
                chineseOnly: false
            ),
            AboutAppLink(
                identity: .noLazyload,
                name: "No lazyload",
                subtitleKey: .settingsAboutMoreAppsNoLazyloadDescription,
                url: AppMetadata.noLazyloadURL,
                iconResource: "AboutAppNoLazyload",
                chineseOnly: false
            ),
        ]

        guard language.isChinese else { return apps }

        apps.append(
            AboutAppLink(
                identity: .fund01,
                name: "fund01",
                subtitleKey: .settingsAboutMoreAppsFund01Description,
                url: AppMetadata.fund01URL,
                iconResource: "AboutAppFund01",
                chineseOnly: true
            )
        )
        return apps
    }
}

/// Loads the About page's bundled raster assets.
///
/// Update workflow: when a group QR changes, replace the matching README image
/// (`screenshots/status-trio-wechat-group.png` or `screenshots/status-trio-qq-group.png`)
/// and regenerate the bundled square derivative (`Resources/AboutWeChatQR.png` or
/// `Resources/AboutQQQR.png`) shown here.
enum AboutAssets {
    static var weChatQRCode: NSImage? {
        image(named: "AboutWeChatQR")
    }

    static var qqQRCode: NSImage? {
        image(named: "AboutQQQR")
    }

    static func appIcon(for app: AboutAppLink) -> NSImage? {
        image(named: app.iconResource)
    }

    private static func image(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
