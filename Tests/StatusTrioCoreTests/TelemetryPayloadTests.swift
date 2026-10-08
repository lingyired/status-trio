import Foundation
import XCTest
@testable import StatusTrioCore

final class TelemetryPayloadTests: XCTestCase {
    func testPayloadUsesOnlyAllowedFieldsAndIconPlacementAttribute() throws {
        let context = TelemetryContext(
            appVersion: "2.0.0",
            build: "103",
            osName: "macOS",
            osVersion: "15.4.1",
            architecture: "arm64",
            distribution: "direct",
            osLanguage: "en-GB",
            appLanguage: "zh-Hans",
            appIconPlacement: .both
        )
        let heartbeat = TelemetryHeartbeat(
            installID: "d7b71d45-32d4-4910-bf96-a2ab2e4b9e50",
            context: context,
            configuration: TelemetryConfiguration(endpoint: URL(string: "https://example.invalid/ping")!)
        )
        let data = try JSONEncoder().encode(heartbeat)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let required: Set<String> = ["schema_version", "app_id", "install_id", "app_version"]
        let allowed = required.union([
            "build", "os_name", "os_version", "arch", "distribution",
            "os_language", "app_language", "attributes"
        ])

        XCTAssertTrue(required.isSubset(of: Set(json.keys)))
        XCTAssertTrue(Set(json.keys).isSubset(of: allowed))
        XCTAssertNil(json["first_app_version"])
        XCTAssertEqual(json["build"] as? String, "103")
        XCTAssertEqual(json["app_version"] as? String, "2.0.0")
        XCTAssertEqual(json["os_version"] as? String, "15.4")
        XCTAssertEqual(json["os_language"] as? String, "en")
        XCTAssertEqual(json["app_language"] as? String, "zh-Hans")
        let attributes = try XCTUnwrap(json["attributes"] as? [String: Any])
        XCTAssertEqual(Set(attributes.keys), ["app_icon_placement"])
        XCTAssertEqual(attributes["app_icon_placement"] as? String, "both")
        XCTAssertEqual(Set(AppIconPlacement.allCases.map(\.rawValue)), ["menuBar", "dock", "both"])
    }

    func testOptionalInvalidLanguagesAreOmittedAndBuildIsIndependent() throws {
        let context = TelemetryContext(
            appVersion: "2.0.0",
            build: nil,
            osName: "macOS",
            osVersion: "14",
            architecture: "x86_64",
            distribution: nil,
            osLanguage: "en-garbage!",
            appLanguage: "中文",
            appIconPlacement: nil
        )
        let heartbeat = TelemetryHeartbeat(
            installID: "install",
            context: context,
            configuration: TelemetryConfiguration(endpoint: URL(string: "https://example.invalid/ping")!)
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(heartbeat)) as? [String: Any])
        XCTAssertNil(json["build"])
        XCTAssertNil(json["os_language"])
        XCTAssertNil(json["app_language"])
        XCTAssertNil(json["attributes"])
        XCTAssertEqual(json["app_version"] as? String, "2.0.0")
        XCTAssertEqual(json["os_version"] as? String, "14")
    }
}
