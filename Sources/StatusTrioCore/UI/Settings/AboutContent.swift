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

/// One row in the About page's "More Apps" list. Each app can offer several
/// install links (one per store), so the row renders a small link per platform
/// instead of a single "open" action.
struct AboutAppLink: Identifiable, Equatable {
    enum Identity: String, CaseIterable {
        case newtab01
        case noLazyload
        case fund01
    }

    /// A link label: a fixed brand name (store names are not translated) or a
    /// localization key (e.g. the fund01 project homepage).
    enum LinkLabel: Equatable {
        case literal(String)
        case key(LocalizationKey)
    }

    /// A tiny leading glyph for a store link: a bundled brand PNG or an SF Symbol.
    enum StoreIcon: Equatable {
        case asset(String)
        case systemImage(String)
    }

    struct StoreLink: Equatable {
        let label: LinkLabel
        let url: URL
        let icon: StoreIcon?
    }

    let identity: Identity
    let name: String
    let subtitleKey: LocalizationKey
    /// Base name (without extension) of the bundled app icon PNG.
    let iconResource: String
    let chineseOnly: Bool
    let links: [StoreLink]

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
                iconResource: "AboutAppNewtab01",
                chineseOnly: false,
                links: [
                    .init(label: .literal("Chrome"), url: AppMetadata.newtab01ChromeURL, icon: .asset("AboutStoreChrome")),
                    .init(label: .literal("Edge"), url: AppMetadata.newtab01EdgeURL, icon: .asset("AboutStoreEdge")),
                ]
            ),
            AboutAppLink(
                identity: .noLazyload,
                name: "No lazyload",
                subtitleKey: .settingsAboutMoreAppsNoLazyloadDescription,
                iconResource: "AboutAppNoLazyload",
                chineseOnly: false,
                links: [
                    .init(label: .literal("Chrome"), url: AppMetadata.noLazyloadChromeURL, icon: .asset("AboutStoreChrome")),
                    .init(label: .literal("Edge"), url: AppMetadata.noLazyloadEdgeURL, icon: .asset("AboutStoreEdge")),
                    .init(label: .literal("Firefox"), url: AppMetadata.noLazyloadFirefoxURL, icon: .asset("AboutStoreFirefox")),
                    .init(label: .literal("App Store"), url: AppMetadata.noLazyloadAppStoreURL, icon: .asset("AboutStoreAppStore")),
                ]
            ),
        ]

        guard language.isChinese else { return apps }

        apps.append(
            AboutAppLink(
                identity: .fund01,
                name: "fund01",
                subtitleKey: .settingsAboutMoreAppsFund01Description,
                iconResource: "AboutAppFund01",
                chineseOnly: true,
                links: [
                    .init(
                        label: .key(.settingsAboutProject),
                        url: AppMetadata.fund01URL,
                        icon: .systemImage("globe")
                    )
                ]
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

    static func storeIcon(named name: String) -> NSImage? {
        image(named: name)
    }

    /// Crops a fetched README poster (group name + QR + validity notice) down to
    /// its QR card so the in-app tile keeps the square shape. A roughly square
    /// image (i.e. already just the QR) is returned unchanged.
    static func normalizedWeChatQR(_ image: NSImage) -> NSImage {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return image
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > width * 1.2 else { return image }
        let rect = CGRect(
            x: 0.1333 * width,
            y: 0.3391 * height,
            width: 0.7334 * width,
            height: 0.4827 * height
        ).integral
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    private static func image(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
