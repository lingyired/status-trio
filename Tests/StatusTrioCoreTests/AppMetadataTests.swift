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
