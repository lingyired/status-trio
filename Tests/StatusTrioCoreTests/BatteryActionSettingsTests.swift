import Foundation
import XCTest

@testable import StatusTrioCore

@MainActor
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

    func testBatteryActionTargetDefaultsToSystemAndPersistsEveryCase() throws {
        let domain = "BatteryActionSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        XCTAssertEqual(SettingsStore.batteryActionTargetDefaultsKey, "batteryActionTarget.v1")
        let first = SettingsStore(defaults: defaults)
        XCTAssertEqual(first.batteryActionTarget, .systemSettings)

        let targets: [BatteryActionTarget] = [
            .systemSettings,
            .knownApp(.alDente),
            .knownApp(.batFi),
            .customApp(.init(
                displayName: "Tool",
                bundleIdentifier: "com.example.Tool",
                fallbackPath: "/Applications/Tool.app"
            )),
            .customURL("raycast://battery")
        ]

        for target in targets {
            first.batteryActionTarget = target
            XCTAssertEqual(SettingsStore(defaults: defaults).batteryActionTarget, target)
        }
    }

    func testBatteryActionTargetCorruptDataFallsBackToSystemSettings() throws {
        let domain = "BatteryActionSettingsTests.Corrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let corruptValues = [
            Data("not JSON".utf8),
            Data(#"{"type":"alien"}"#.utf8),
            Data(#"{"type":"knownApp","knownAppID":"missing"}"#.utf8)
        ]

        for value in corruptValues {
            defaults.set(value, forKey: SettingsStore.batteryActionTargetDefaultsKey)
            XCTAssertEqual(SettingsStore(defaults: defaults).batteryActionTarget, .systemSettings)
        }
    }
}
