import XCTest
@testable import StatusTrioCore

@MainActor
final class ShortcutRecordingLocalizationTests: XCTestCase {
    func testDescriptionsExplainInputMethodAndAppConflictsInEveryLanguage() throws {
        let requiredTerms: [AppLanguage: (inputMethod: String, otherApp: String)] = [
            .english: ("input method", "another app"),
            .simplifiedChinese: ("输入法", "其他 App"),
            .traditionalChinese: ("輸入法", "其他 App"),
            .japanese: ("入力方式", "他のアプリ"),
            .korean: ("입력기", "다른 앱"),
            .spanish: ("método de entrada", "otra app"),
            .french: ("méthode de saisie", "autre app"),
            .german: ("Eingabemethode", "anderen App"),
            .italian: ("metodo di input", "altra app"),
            .brazilianPortuguese: ("método de entrada", "outro app"),
            .russian: ("методом ввода", "другим приложением"),
            .arabic: ("طريقة الإدخال", "تطبيق آخر")
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            let description = bundle.localizedString(
                forKey: LocalizationKey.settingsShortcutDescription.rawValue,
                value: nil,
                table: nil
            )
            let terms = try XCTUnwrap(requiredTerms[language])

            XCTAssertTrue(
                description.contains(terms.inputMethod),
                "\(language.rawValue) shortcut description is missing the input-method caveat"
            )
            XCTAssertTrue(
                description.contains(terms.otherApp),
                "\(language.rawValue) shortcut description is missing the other-app caveat"
            )
        }
    }

    func testFeedbackMapsToDistinctLocalizationKeys() {
        XCTAssertEqual(
            GlobalShortcutFeedback.invalidCombination.localizationKey,
            .settingsShortcutInvalid
        )
        XCTAssertEqual(
            GlobalShortcutFeedback.inputMethodConflict.localizationKey,
            .settingsShortcutInputMethodConflict
        )
        XCTAssertEqual(
            GlobalShortcutFeedback.conflict.localizationKey,
            .settingsShortcutUnavailable
        )
        XCTAssertEqual(
            GlobalShortcutFeedback.registrationFailed.localizationKey,
            .settingsShortcutRegistrationFailed
        )
        XCTAssertEqual(
            GlobalShortcutFeedback.restorationFailed.localizationKey,
            .settingsShortcutRestorationFailed
        )
    }
}
