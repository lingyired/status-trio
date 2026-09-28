import Foundation
import XCTest

@testable import StatusTrioCore

@MainActor
final class BatteryActionPresentationTests: XCTestCase {
    func testActionLabelsUseTargetNamesInEnglishAndSimplifiedChinese() throws {
        let context = try makeLocalization()
        defer { context.defaults.removePersistentDomain(forName: context.domain) }
        let localization = context.localization

        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: .systemSettings, localization: localization),
            "Open Battery Settings"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: .knownApp(.alDente), localization: localization),
            "Open AlDente"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: .knownApp(.batFi), localization: localization),
            "Open BatFi"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(
                for: .customApp(.init(
                    displayName: "My Charging App",
                    bundleIdentifier: nil,
                    fallbackPath: nil
                )),
                localization: localization
            ),
            "Open My Charging App"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(
                for: .customURL("raycast://battery"),
                localization: localization
            ),
            "Open Custom Link"
        )

        localization.setPreference(.language(.simplifiedChinese))
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: .systemSettings, localization: localization),
            "打开电源设置"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: .knownApp(.alDente), localization: localization),
            "打开AlDente"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: .knownApp(.batFi), localization: localization),
            "打开BatFi"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(
                for: .customApp(.init(
                    displayName: "自选工具",
                    bundleIdentifier: nil,
                    fallbackPath: nil
                )),
                localization: localization
            ),
            "打开自选工具"
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(
                for: .customURL("raycast://battery"),
                localization: localization
            ),
            "打开自定义链接"
        )
    }

    func testSelectionNamesAndLongApplicationNamesRemainUnabridged() throws {
        let context = try makeLocalization()
        defer { context.defaults.removePersistentDomain(forName: context.domain) }
        let localization = context.localization
        let longName = String(repeating: "Long application name ", count: 10)
        let target = BatteryActionTarget.customApp(.init(
            displayName: longName,
            bundleIdentifier: "com.example.LongApp",
            fallbackPath: "/Applications/Long App.app"
        ))

        XCTAssertEqual(
            BatteryActionPresentation.selectionName(for: .systemSettings, localization: localization),
            "Battery Settings"
        )
        XCTAssertEqual(
            BatteryActionPresentation.selectionName(for: .knownApp(.alDente), localization: localization),
            "AlDente"
        )
        XCTAssertEqual(
            BatteryActionPresentation.selectionName(for: target, localization: localization),
            longName
        )
        XCTAssertEqual(
            BatteryActionPresentation.openLabel(for: target, localization: localization),
            "Open \(longName)"
        )
        XCTAssertEqual(
            BatteryActionPresentation.selectionName(
                for: .customURL("raycast://battery"),
                localization: localization
            ),
            "Custom Link"
        )
    }

    func testBatteryActionLocalizationKeysExistInAllTwelveBundles() throws {
        let keys: [LocalizationKey] = [
            .settingsBatteryActionTitle,
            .settingsBatteryActionDescription,
            .batteryActionSystemSettings,
            .batteryActionCustomApplication,
            .batteryActionCustomURL,
            .batteryActionChooseTarget,
            .batteryActionChangeTarget,
            .batteryActionUnavailable,
            .batteryActionInvalidURL,
            .batteryActionOpenTarget,
            .batteryActionCustomLink
        ]

        XCTAssertEqual(AppLanguage.allCases.count, 12)
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            for key in keys {
                let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) has an empty value for \(key.rawValue)")
                XCTAssertNotEqual(value, key.rawValue, "\(language.rawValue) is missing \(key.rawValue)")
            }
        }
    }

    private func makeLocalization() throws -> (localization: Localization, defaults: UserDefaults, domain: String) {
        let domain = "BatteryActionPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.english))
        return (localization, defaults, domain)
    }
}
