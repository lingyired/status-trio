import XCTest
@testable import StatusTrioCore

final class TelemetryAppMetadataTests: XCTestCase {
    func testMissingOrEmptyBundleVersionSkipsTelemetryContext() {
        XCTAssertNil(TelemetryAppMetadata.snapshot(
            appVersion: nil,
            build: "103",
            osVersion: "15.4.2",
            preferredLanguages: ["th-TH"],
            appLanguage: .english,
            appIconPlacement: .both
        ))
        XCTAssertNil(TelemetryAppMetadata.snapshot(
            appVersion: "  ",
            build: nil,
            osVersion: "15.4.2",
            preferredLanguages: ["th-TH"],
            appLanguage: .english,
            appIconPlacement: .both
        ))
    }

    func testSnapshotUsesProductionMetadataAndMajorMinorOSVersion() throws {
        let context = try XCTUnwrap(TelemetryAppMetadata.snapshot(
            appVersion: "2.0.0",
            build: nil,
            osVersion: "15.4.2",
            preferredLanguages: ["th-TH"],
            appLanguage: .traditionalChinese,
            appIconPlacement: .dock
        ))

        XCTAssertEqual(context.appVersion, "2.0.0")
        XCTAssertNil(context.build)
        XCTAssertEqual(context.osName, "macOS")
        XCTAssertEqual(context.osVersion, "15.4")
        XCTAssertEqual(context.architecture, TelemetryAppMetadata.currentArchitecture)
        XCTAssertEqual(context.distribution, "github")
        XCTAssertEqual(context.osLanguage, "th")
        XCTAssertEqual(context.appLanguage, "zh-Hant")
        XCTAssertEqual(context.appIconPlacement, .dock)
    }

    func testUnsupportedArchitectureDoesNotInventIdentifier() {
        XCTAssertTrue(["arm64", "x86_64"].contains(TelemetryAppMetadata.currentArchitecture ?? ""))
    }
}
