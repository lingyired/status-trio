import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Covers the About page's language gating: which author links and companion
/// apps appear for each resolved language.
@MainActor
final class AboutContentTests: XCTestCase {
    func testEnglishShowsOnlyXAmongSocialLinks() {
        let links = AboutContentCatalog.socialLinks(for: .english)
        XCTAssertEqual(links.map(\.network), [.x])
        XCTAssertTrue(links.allSatisfy { !$0.chineseOnly })
    }

    func testChineseShowsEverySocialLink() {
        let expected: [AboutSocialLink.Network] = [.x, .douyin, .xiaohongshu, .bilibili, .blog]
        XCTAssertEqual(AboutContentCatalog.socialLinks(for: .simplifiedChinese).map(\.network), expected)
        XCTAssertEqual(AboutContentCatalog.socialLinks(for: .traditionalChinese).map(\.network), expected)
    }

    func testNonChineseLanguagesHideChineseOnlySocialLinks() {
        for language in AppLanguage.allCases where !language.isChinese {
            XCTAssertEqual(
                AboutContentCatalog.socialLinks(for: language).map(\.network),
                [.x],
                "\(language.rawValue) should only show X"
            )
        }
    }

    func testEnglishShowsOnlyCrossLanguageApps() {
        XCTAssertEqual(
            AboutContentCatalog.apps(for: .english).map(\.identity),
            [.newtab01, .noLazyload]
        )
    }

    func testChineseAddsFund01() {
        let expected: [AboutAppLink.Identity] = [.newtab01, .noLazyload, .fund01]
        XCTAssertEqual(AboutContentCatalog.apps(for: .simplifiedChinese).map(\.identity), expected)
        XCTAssertEqual(AboutContentCatalog.apps(for: .traditionalChinese).map(\.identity), expected)
    }

    func testNonChineseLanguagesHideFund01() {
        for language in AppLanguage.allCases where !language.isChinese {
            XCTAssertEqual(
                AboutContentCatalog.apps(for: language).map(\.identity),
                [.newtab01, .noLazyload],
                "\(language.rawValue) must not show fund01"
            )
        }
    }

    func testAllCatalogURLsAreAbsolute() {
        let urls = AboutContentCatalog.socialLinks(for: .simplifiedChinese).map(\.url)
            + AboutContentCatalog.apps(for: .simplifiedChinese).map(\.url)
        for url in urls {
            XCTAssertNotNil(url.scheme)
            XCTAssertNotNil(url.host)
        }
    }

    func testBundledAboutImagesArePresent() {
        XCTAssertNotNil(AboutAssets.weChatQRCode, "missing bundled WeChat QR")
        XCTAssertNotNil(AboutAssets.qqQRCode, "missing bundled QQ QR")
        for app in AboutContentCatalog.apps(for: .simplifiedChinese) {
            XCTAssertNotNil(AboutAssets.appIcon(for: app), "missing bundled icon \(app.iconResource)")
        }
    }

    func testChineseAppsListRendersTallerThanEnglish() throws {
        let suite = "StatusTrioCoreTests.AboutContent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }

        let width: CGFloat = 454

        let chinese = Localization(
            defaults: defaults,
            preferredLanguages: [AppLanguage.simplifiedChinese.rawValue]
        )
        let english = Localization(
            defaults: defaults,
            preferredLanguages: [AppLanguage.english.rawValue]
        )

        let chineseHeight = renderedHeight(
            AboutMoreAppsView().environmentObject(chinese),
            width: width
        )
        let englishHeight = renderedHeight(
            AboutMoreAppsView().environmentObject(english),
            width: width
        )

        XCTAssertGreaterThan(
            chineseHeight,
            englishHeight,
            "The Chinese-only fund01 row should add height"
        )
    }

    @MainActor
    private func renderedHeight<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let hostingView = NSHostingView(rootView: view.frame(width: width))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }
}
