import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class LocalizationTests: XCTestCase {
    func testLanguageChangeRefreshesAfterResolvedLanguageIsUpdated() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        var observedLanguages: [AppLanguage] = []
        let cancellable = localization.objectWillChange.sink {
            observedLanguages.append(localization.resolvedLanguage)
        }
        defer { cancellable.cancel() }

        localization.setPreference(.language(.german))

        XCTAssertEqual(observedLanguages.last, .german)
    }

    func testManualLanguagePersistsAndResolves() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.german))

        XCTAssertEqual(localization.resolvedLanguage, .german)
        XCTAssertEqual(
            Localization(defaults: suite.defaults, preferredLanguages: ["en"]).resolvedLanguage,
            .german
        )
    }

    func testSystemLanguageFollowsInjectedPreferences() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(
            defaults: suite.defaults,
            preferredLanguages: ["zh-TW", "en-US"]
        )

        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.resolvedLanguage, .traditionalChinese)
    }

    func testInvalidStoredLanguageFallsBackToSystem() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set("not-a-language", forKey: Localization.defaultsKey)

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["ja-JP"])

        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.resolvedLanguage, .japanese)
    }

    func testEveryLanguageHasEveryNonEmptyKey() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            for key in LocalizationKey.allCases {
                let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) missing \(key.rawValue)")
                XCTAssertNotEqual(value, key.rawValue, "\(language.rawValue) missing \(key.rawValue)")
            }
        }
    }

    func testAppleDeviceBatteryCopyDescribesNearbyNamedRowsWithoutConsentInEveryLanguage() throws {
        let english = try XCTUnwrap(Localization.resourceBundle(for: .english))
        let description = english.localizedString(
            forKey: LocalizationKey.settingsAppleDevicesAndBatteryDescription.rawValue,
            value: nil,
            table: nil
        )
        XCTAssertTrue(description.localizedCaseInsensitiveContains("nearby"))
        XCTAssertTrue(description.localizedCaseInsensitiveContains("named"))
        XCTAssertTrue(description.localizedCaseInsensitiveContains("apple"))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("authorized"))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("allow battery"))

        let chinese = try XCTUnwrap(Localization.resourceBundle(for: .simplifiedChinese))
        let chineseDescription = chinese.localizedString(
            forKey: LocalizationKey.settingsAppleDevicesAndBatteryDescription.rawValue,
            value: nil,
            table: nil
        )
        for term in ["Apple", "附近", "名称"] {
            XCTAssertTrue(chineseDescription.contains(term), "Simplified Chinese copy is missing \(term)")
        }
        XCTAssertEqual(
            chinese.localizedString(forKey: LocalizationKey.settingsAppleDevicesAndBattery.rawValue, value: nil, table: nil),
            "显示苹果设备与电量"
        )

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            let localized = bundle.localizedString(
                forKey: LocalizationKey.settingsAppleDevicesAndBatteryDescription.rawValue,
                value: nil,
                table: nil
            )
            XCTAssertFalse(localized.localizedCaseInsensitiveContains("authorized"), "\(language.rawValue) still describes BLE authorization")
            XCTAssertFalse(localized.localizedCaseInsensitiveContains("allow battery"), "\(language.rawValue) still describes BLE authorization")
        }
    }

    func testNaturalScrollingDescriptionMentionsThirdPartyScrollApps() throws {
        let requiredMentions = ["MOS", "Scroll Reverser", "LinearMouse", "Status Trio"]
        let requiredGuidance: [AppLanguage: (scope: String, remedy: String)] = [
            .english: ("after turning this on", "exception/ignore list"),
            .simplifiedChinese: ("如果开启后", "例外/忽略列表"),
            .traditionalChinese: ("如果開啟後", "例外/忽略清單"),
            .japanese: ("オンにした後も", "例外/無視リスト"),
            .korean: ("이 옵션을 켠 후에도", "예외/무시 목록"),
            .spanish: ("tras activar esta opción", "lista de excepciones/omisiones"),
            .french: ("après avoir activé cette option", "liste d’exceptions/d’ignorés"),
            .german: ("nach dem Aktivieren dieser Option", "Ausnahme-/Ignorierliste"),
            .italian: ("dopo aver attivato questa opzione", "elenco di eccezioni/ignorati"),
            .brazilianPortuguese: ("depois de ativar esta opção", "lista de exceções/ignorados"),
            .russian: ("после включения этой опции", "список исключений/игнорирования"),
            .arabic: ("بعد تشغيل هذا الخيار", "قائمة استثناءات/تجاهل")
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            let value = bundle.localizedString(
                forKey: LocalizationKey.settingsPopupVolumeScrollNaturalDescription.rawValue,
                value: nil,
                table: nil
            )

            for mention in requiredMentions {
                XCTAssertTrue(
                    value.contains(mention),
                    "\(language.rawValue) natural-scrolling description missing \(mention)"
                )
            }

            let guidance = try XCTUnwrap(requiredGuidance[language])
            XCTAssertTrue(
                value.contains(guidance.scope),
                "\(language.rawValue) natural-scrolling description is not scoped to the enabled state"
            )
            XCTAssertTrue(
                value.contains(guidance.remedy),
                "\(language.rawValue) natural-scrolling description is missing exception guidance"
            )
        }
    }

    func testEveryParameterizedKeyUsesMatchingPlaceholders() throws {
        let expectedPlaceholderCounts: [LocalizationKey: Int] = [
            .wifiSummaryBand: 1,
            .wifiSummarySignal: 1,
            .wifiSummaryBandAndSignal: 2,
            .menuVersion: 1,
            .menuAbout: 1,
            .menuHide: 1,
            .settingsIconSizeAccessibilityValue: 1,
            .settingsRefreshIntervalValue: 1,
            .settingsAboutVersion: 1,
            .batteryTitle: 1,
            .batteryTimeToFullMinutes: 1,
            .batteryTimeToFullHours: 1,
            .batteryTimeToFullHoursMinutes: 2,
            .batteryAccessibilityValue: 1,
            .commonParenthetical: 2,
            .commonLabelValue: 2,
            .wifiValueBars: 1,
            .wifiAccessibilityWithSSID: 2,
            .volumeTitle: 1,
            .volumeValue: 2,
            .volumeOutputSwitchTo: 1,
            .accessibilityStatus: 3,
            .accessibilityBattery: 1,
            .accessibilityVolume: 1
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            for (key, expectedCount) in expectedPlaceholderCounts {
                let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                XCTAssertEqual(
                    placeholderCount(in: value),
                    expectedCount,
                    "\(language.rawValue) has wrong placeholders for \(key.rawValue)"
                )
            }
        }
    }

    func testFormattedStringUsesSelectedLanguageLocale() {
        let suite = makeSuite()
        defer { clear(suite) }
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))

        XCTAssertEqual(
            localization.format(.batteryTitle, 68),
            String(format: "电池 · %d%%", locale: Locale(identifier: "zh-Hans"), 68)
        )
    }

    func testResolvedBundlesAreCachedPerLanguage() {
        let suite = makeSuite()
        defer { clear(suite) }
        var lookupCount = 0
        let localization = Localization(
            defaults: suite.defaults,
            preferredLanguages: ["en"],
            bundleProvider: { language in
                lookupCount += 1
                return Localization.resourceBundle(for: language)
            }
        )

        _ = localization.string(.menuSettings)
        _ = localization.string(.menuQuit)

        XCTAssertEqual(lookupCount, 1)
    }

    func testGermanResourceOverridesEnglish() {
        let suite = makeSuite()
        defer { clear(suite) }
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.german))

        XCTAssertEqual(localization.string(.menuSettings), "Einstellungen…")
    }

    func testOnlyChineseLanguagesUseTheExtendedAboutLinks() {
        let detected = Set(AppLanguage.allCases.filter(\.isChinese))

        XCTAssertEqual(detected, [.simplifiedChinese, .traditionalChinese])
    }

    func testAboutLinkLabelsStayCompact() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            let repository = bundle.localizedString(
                forKey: LocalizationKey.settingsAboutRepository.rawValue,
                value: nil,
                table: nil
            )
            XCTAssertEqual(
                repository,
                "GitHub",
                "\(language.rawValue) repository label should stay short"
            )

            let project = bundle.localizedString(
                forKey: LocalizationKey.settingsAboutProject.rawValue,
                value: nil,
                table: nil
            )
            XCTAssertLessThanOrEqual(
                project.count,
                10,
                "\(language.rawValue) project label is too long: \(project)"
            )
        }
    }

    func testAppIconPlacementLabelsStayCompact() throws {
        let optionKeys: [LocalizationKey] = [
            .settingsAppIconPlacementMenuBar,
            .settingsAppIconPlacementDock,
            .settingsAppIconPlacementBoth
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            for key in optionKeys {
                let value = bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) missing \(key.rawValue)")
                XCTAssertLessThanOrEqual(
                    value.count,
                    24,
                    "\(language.rawValue) \(key.rawValue) is too long: \(value)"
                )
            }
        }
    }

    func testDockIconBackgroundLabelsStayCompact() throws {
        let optionKeys: [LocalizationKey] = [
            .settingsDockIconBackgroundSystem,
            .settingsDockIconBackgroundDark,
            .settingsDockIconBackgroundLight
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            for key in optionKeys {
                let value = bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) missing \(key.rawValue)")
                XCTAssertLessThanOrEqual(
                    value.count,
                    24,
                    "\(language.rawValue) \(key.rawValue) is too long: \(value)"
                )
            }
        }
    }

    private func placeholderCount(in value: String) -> Int {
        let pattern = #"%(?:\d+\$)?[-+#0 ]*\d*(?:\.\d+)?[d@%]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.numberOfMatches(in: value, range: range)
            - value.components(separatedBy: "%%").count + 1
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removeTestSuite(named: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removeTestSuite(named: suite.name)
    }
}
