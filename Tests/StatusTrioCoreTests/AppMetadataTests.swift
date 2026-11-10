import XCTest
@testable import StatusTrioCore

final class AppMetadataTests: XCTestCase {
    func testNameUsesDisplayNameFirst() {
        let name = AppMetadata.name(from: [
            "CFBundleDisplayName": "Localized Name",
            "CFBundleName": "Bundle Name"
        ])

        XCTAssertEqual(name, "Localized Name")
    }

    func testNameFallsBackToBundleName() {
        let name = AppMetadata.name(from: [
            "CFBundleName": "Bundle Name"
        ])

        XCTAssertEqual(name, "Bundle Name")
    }

    func testNameFallsBackToDefault() {
        XCTAssertEqual(AppMetadata.name(from: [:]), "Status Trio")
    }

    func testDevelopmentCodenameUsesNonEmptyInfoValue() {
        XCTAssertEqual(
            AppMetadata.developmentCodename(from: ["STDevelopmentCodename": "Fix Issues"]),
            "Fix Issues"
        )
        XCTAssertNil(AppMetadata.developmentCodename(from: ["STDevelopmentCodename": "   "]))
        XCTAssertNil(AppMetadata.developmentCodename(from: [:]))
    }

    // Developer-only Settings rows (the listening-mode preview) key off the
    // `STDevelopmentCodename` marker: a development bundle carries it, a
    // packaged release must not, so the test-only preview switch cannot leak
    // into a release build's Settings.
    func testDevelopmentCodenameMarksADevelopmentBuild() {
        let info: [String: Any] = ["STDevelopmentCodename": "Fix Issue 271"]
        XCTAssertTrue(AppMetadata.isDevelopmentBuild(from: info))
        XCTAssertEqual(AppMetadata.developmentCodename(from: info), "Fix Issue 271")
    }

    func testReleaseInfoDictionaryIsNotADevelopmentBuild() {
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.lingsmbp.StatusTrio",
            "CFBundleShortVersionString": "1.9.2"
        ]
        XCTAssertFalse(AppMetadata.isDevelopmentBuild(from: info))
    }

    func testBlankCodenameDoesNotCountAsADevelopmentBuild() {
        XCTAssertFalse(
            AppMetadata.isDevelopmentBuild(from: ["STDevelopmentCodename": "   "])
        )
        XCTAssertFalse(AppMetadata.isDevelopmentBuild(from: [:]))
    }

    func testIncludesPrivilegedHelperReadsTheInfoFlag() {
        XCTAssertTrue(
            AppMetadata.includesPrivilegedHelper(from: ["STIncludesPrivilegedHelper": true])
        )
        XCTAssertFalse(
            AppMetadata.includesPrivilegedHelper(from: ["STIncludesPrivilegedHelper": false])
        )
        // A build that predates the flag, or one that stripped it, must read as
        // "no helper" so the UI never offers a control it cannot honour.
        XCTAssertFalse(AppMetadata.includesPrivilegedHelper(from: [:]))
    }

    func testVersionDisplayStringCombinesVersionAndBuild() {
        XCTAssertEqual(
            AppMetadata.versionDisplayString(from: [
                "CFBundleShortVersionString": "1.3.0",
                "CFBundleVersion": "11"
            ]),
            "1.3.0 (11)"
        )
    }

    func testVersionDisplayStringFallsBackWhenKeysAreMissing() {
        XCTAssertEqual(AppMetadata.versionDisplayString(from: [:]), "1.0.0 (1)")
    }

    func testVersionShortStringDropsTheBuildNumber() {
        XCTAssertEqual(
            AppMetadata.versionShortString(from: [
                "CFBundleShortVersionString": "1.3.0",
                "CFBundleVersion": "11"
            ]),
            "1.3.0"
        )
    }

    func testVersionShortStringFallsBackWhenTheVersionKeyIsMissing() {
        XCTAssertEqual(AppMetadata.versionShortString(from: [:]), "1.0.0")
    }

    func testProjectHomepageURL() {
        XCTAssertEqual(
            AppMetadata.projectHomepageURL.absoluteString,
            "https://statustrio.lingai.net/"
        )
    }

    func testGitHubMarkLoadsFromResourceBundle() {
        XCTAssertNotNil(AboutIcon.githubMark)
    }
}
