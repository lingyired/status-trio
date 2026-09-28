import Foundation
import XCTest

@testable import StatusTrioCore

final class BatteryActionSettingsTests: XCTestCase {
    func testTargetCodableCasesUseStableDiscriminatorsAndKeys() throws {
        let application = ExternalApplicationTarget(
            displayName: "Tool",
            bundleIdentifier: "com.example.Tool",
            fallbackPath: "/Applications/Tool.app"
        )
        let targets: [(BatteryActionTarget, [String: String])] = [
            (.systemSettings, ["type": "systemSettings"]),
            (.knownApp(.alDente), ["type": "knownApp", "knownAppID": "alDente"]),
            (.customApp(application), [
                "type": "customApp",
                "application.displayName": "Tool",
                "application.bundleIdentifier": "com.example.Tool",
                "application.fallbackPath": "/Applications/Tool.app"
            ]),
            (.customURL("raycast://battery"), ["type": "customURL", "url": "raycast://battery"])
        ]

        for (target, expected) in targets {
            let data = try JSONEncoder().encode(target)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["type"] as? String, expected["type"])

            for (key, value) in expected where key != "type" {
                let nested = key.split(separator: ".")
                let actual: String?
                if nested.count == 2,
                   let child = object[String(nested[0])] as? [String: Any] {
                    actual = child[String(nested[1])] as? String
                } else {
                    actual = object[key] as? String
                }
                XCTAssertEqual(actual, value, "Unexpected JSON value for \(key)")
            }

            XCTAssertEqual(try JSONDecoder().decode(BatteryActionTarget.self, from: data), target)
        }
    }

    func testUnknownTargetDiscriminatorThrows() {
        let data = Data(#"{"type":"alien"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BatteryActionTarget.self, from: data))
    }
}
