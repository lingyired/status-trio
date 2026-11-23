import Foundation

enum AppMetadata {
    static let defaultName = "Status Trio"
    private static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]
    private static let developmentCodenameKey = "STDevelopmentCodename"

    static var name: String {
        for key in nameKeys {
            if let value = validName(Bundle.main.object(forInfoDictionaryKey: key)) {
                return value
            }
        }
        return defaultName
    }

    static func name(from infoDictionary: [String: Any]) -> String {
        for key in nameKeys {
            if let value = validName(infoDictionary[key]) {
                return value
            }
        }
        return defaultName
    }

    static var developmentCodename: String? {
        developmentCodename(from: Bundle.main.infoDictionary ?? [:])
    }

    /// A development bundle carries `STDevelopmentCodename`; a release bundle
    /// must not (see AGENTS.md). Developer-only Settings rows key off this flag
    /// so a packaged release never offers them.
    static var isDevelopmentBuild: Bool {
        isDevelopmentBuild(from: Bundle.main.infoDictionary ?? [:])
    }

    static func isDevelopmentBuild(from infoDictionary: [String: Any]) -> Bool {
        developmentCodename(from: infoDictionary) != nil
    }

    static func developmentCodename(from infoDictionary: [String: Any]) -> String? {
        validName(infoDictionary[developmentCodenameKey])
    }

    /// Whether this build bundled the privileged power helper.
    ///
    /// `build-app.sh` writes this from the `PRIVILEGED_HELPER` switch, so an
    /// App-Store-style build sets it false and the app hides the feature rather
    /// than offering a toggle that cannot work. Missing key reads as false.
    private static let includesPrivilegedHelperKey = "STIncludesPrivilegedHelper"

    static var includesPrivilegedHelper: Bool {
        includesPrivilegedHelper(from: Bundle.main.infoDictionary ?? [:])
    }

    static func includesPrivilegedHelper(from infoDictionary: [String: Any]) -> Bool {
        infoDictionary[includesPrivilegedHelperKey] as? Bool ?? false
    }

    private static func validName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    static let repositoryDisplayName = "github.com/lingyired/status-trio"
    static let repositoryURL = URL(string: "https://github.com/lingyired/status-trio")!
    static let projectHomepageURL = URL(string: "https://statustrio.lingai.net/")!
    static let authorName = "lingyired"
    static let authorURL = URL(string: "https://github.com/lingyired")!
    static let authorWebsiteURL = URL(string: "https://lingai.net/")!

    // MARK: About — author social channels

    static let authorXURL = URL(string: "https://x.com/lingyired")!
    static let authorDouyinURL = URL(
        string: "https://www.douyin.com/user/MS4wLjABAAAAbiTboFKa6VcEX08y_0tIkUxZV-ZGP_901qOtVNX5bC4Xs87wdBmAPOENobXVVEoW"
    )!
    static let authorXiaohongshuURL = URL(
        string: "https://www.xiaohongshu.com/user/profile/60a479d30000000001006e88"
    )!
    static let authorBilibiliURL = URL(string: "https://space.bilibili.com/103021226")!

    // MARK: About — Chinese community

    static let qqGroupNumber = "735856753"

    /// The README-hosted WeChat group QR (a poster). The Community card can
    /// refresh the in-app QR from this URL so the owner can rotate the group QR
    /// in the repository without rebuilding the app.
    ///
    /// Candidates are tried in order: the current file name first, then the old
    /// dated name as a transition fallback until the rename reaches `main`.
    static let weChatGroupImageURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/lingyired/status-trio/main/screenshots/status-trio-wechat-group.png")!,
        URL(string: "https://raw.githubusercontent.com/lingyired/status-trio/main/screenshots/status-trio-wechat-group-2026-10-31.png")!,
    ]

    // MARK: About — other apps by the author
    //
    // Store listings are preferred over the project homepages because the
    // homepages are not localized; the stores follow the user's language.
    // fund01 stays on its project homepage because it is Chinese-only.

    static let newtab01ChromeURL = URL(
        string: "https://chromewebstore.google.com/detail/newtab01/nlecfkdndodablijmfcjbnannkgmpegj"
    )!
    static let newtab01EdgeURL = URL(
        string: "https://microsoftedge.microsoft.com/addons/detail/fpeecbmmlohilnpndglclffekddafele"
    )!
    static let noLazyloadChromeURL = URL(
        string: "https://chromewebstore.google.com/detail/no-lazyload-disable-image/gdaoomgmekonglmdeaoengblkjeopall"
    )!
    static let noLazyloadEdgeURL = URL(
        string: "https://microsoftedge.microsoft.com/addons/detail/fmemfkecmbfpmodcmfalihhknaohjefp"
    )!
    static let noLazyloadFirefoxURL = URL(
        string: "https://addons.mozilla.org/firefox/addon/no-lazyload/"
    )!
    /// The Safari build is distributed through the Mac App Store, so the label
    /// says "Safari" to keep the row's browser list consistent.
    static let noLazyloadSafariURL = URL(
        string: "https://apps.apple.com/app/id6825400530?mt=12"
    )!
    static let fund01URL = URL(string: "https://lingai.net/fund01/")!

    static var versionDisplayString: String {
        versionDisplayString(from: Bundle.main.infoDictionary ?? [:])
    }

    static func versionDisplayString(from infoDictionary: [String: Any]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = infoDictionary["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Just the marketing version, without the build number. The Settings
    /// sidebar shows this one short line so a long development codename can
    /// never wrap or truncate there; the About pane keeps the full identity.
    static var versionShortString: String {
        versionShortString(from: Bundle.main.infoDictionary ?? [:])
    }

    static func versionShortString(from infoDictionary: [String: Any]) -> String {
        infoDictionary["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
