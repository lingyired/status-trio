import XCTest
@testable import StatusTrioCore

/// Guards the shipped translations. Every `*.lproj/Localizable.strings` must
/// declare exactly the same keys as the English base file and keep the same
/// format placeholders, so a half-translated language cannot ship silently.
final class LocalizationParityTests: XCTestCase {
    private struct Entry: Equatable {
        let key: String
        let value: String
        let line: Int
    }

    private enum LocalizationError: Error, CustomStringConvertible {
        case unreadable(URL)
        case unparsableLine(language: String, line: Int, text: String)
        case duplicatedKey(language: String, key: String)

        var description: String {
            switch self {
            case .unreadable(let url):
                "cannot read \(url.path)"
            case .unparsableLine(let language, let line, let text):
                "\(language).lproj line \(line) is not a key/value pair: \(text)"
            case .duplicatedKey(let language, let key):
                "\(language).lproj declares \(key) more than once"
            }
        }
    }

    private static var pairPattern: Regex<(Substring, Substring, Substring)> {
        /^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$/
    }

    private static var placeholderPattern: Regex<Substring> {
        /%[@dfs]|%%/
    }

    // MARK: - Tests

    func testEveryLanguageDeclaresExactlyTheEnglishKeys() throws {
        let baseKeys = try entries(for: .english).map(\.key)
        XCTAssertFalse(baseKeys.isEmpty, "en.lproj must define the base key list")
        let baseSet = Set(baseKeys)

        for language in AppLanguage.allCases where language != .english {
            let keys = try entries(for: language).map(\.key)
            let missing = baseSet.subtracting(keys)
            let extra = Set(keys).subtracting(baseSet)
            XCTAssertTrue(
                missing.isEmpty,
                "\(language.rawValue).lproj is missing \(missing.sorted())"
            )
            XCTAssertTrue(
                extra.isEmpty,
                "\(language.rawValue).lproj declares unknown keys \(extra.sorted())"
            )
            XCTAssertEqual(
                keys.count,
                baseKeys.count,
                "\(language.rawValue).lproj declares \(keys.count) keys, expected \(baseKeys.count)"
            )
        }
    }

    func testEveryLanguageKeepsTheEnglishFormatPlaceholders() throws {
        let base = try entries(for: .english)

        for language in AppLanguage.allCases where language != .english {
            let translated = Dictionary(
                try entries(for: language).map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )

            for entry in base {
                guard let value = translated[entry.key] else { continue }
                XCTAssertEqual(
                    placeholders(in: value),
                    placeholders(in: entry.value),
                    "\(language.rawValue).lproj changes the placeholders of \(entry.key)"
                )
            }
        }
    }

    func testPersonalHotspotSectionIsLocalizedInEveryLanguage() throws {
        let key = LocalizationKey.wifiPersonalHotspot.rawValue
        for language in AppLanguage.allCases {
            let values = Dictionary(uniqueKeysWithValues: try entries(for: language).map { ($0.key, $0.value) })
            XCTAssertFalse(
                (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(language.rawValue).lproj must translate \(key)"
            )
        }
    }

    func testAudioInputTranslationsAreNotEmpty() throws {
        let keys = LocalizationKey.allCases.map(\.rawValue).filter {
            $0.hasPrefix("audioInput.") || $0 == "settings.popup.order.audioInput"
        }
        XCTAssertFalse(keys.isEmpty)
        XCTAssertEqual(keys.count, 22, "Expected the audio-input order key and all 21 audioInput keys")
        for language in AppLanguage.allCases {
            let values = Dictionary(uniqueKeysWithValues: try entries(for: language).map { ($0.key, $0.value) })
            for key in keys {
                XCTAssertFalse(
                    (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue).lproj: \(key) is empty"
                )
            }
        }
    }

    func testTelemetryConsentTranslationsArePresentInEveryLanguage() throws {
        let keys = [
            "settings.analytics.title",
            "settings.analytics.description",
            "settings.analytics.privacyDetails",
            "onboarding.analytics.title",
            "onboarding.analytics.description",
            "onboarding.analytics.toggle"
        ]

        for language in AppLanguage.allCases {
            let values = Dictionary(uniqueKeysWithValues: try entries(for: language).map { ($0.key, $0.value) })
            for key in keys {
                XCTAssertFalse(
                    (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue).lproj: \(key) is missing or empty"
                )
            }
        }
    }

    func testTelemetryConsentControlAndPrivacyLinkUseTheirOwnCopy() throws {
        let expected: [String: (toggle: String, privacy: String)] = [
            "ar": ("مشاركة بيانات الاستخدام المجهولة", "التفاصيل"),
            "de": ("Anonyme Nutzungsdaten teilen", "Datenschutzhinweise"),
            "en": ("Share anonymous usage data", "Privacy details"),
            "es": ("Compartir datos de uso anónimos", "Detalles de privacidad"),
            "fr": ("Partager des données d’utilisation anonymes", "Détails sur la confidentialité"),
            "it": ("Condividi dati di utilizzo anonimi", "Dettagli sulla privacy"),
            "ja": ("匿名の利用状況データを共有", "プライバシーの詳細"),
            "ko": ("익명 사용 데이터 공유", "개인정보 세부 정보"),
            "pt-BR": ("Compartilhar dados de uso anônimos", "Detalhes de privacidade"),
            "ru": ("Делиться анонимными данными об использовании", "Подробнее о конфиденциальности"),
            "zh-Hans": ("分享匿名使用数据", "隐私详情"),
            "zh-Hant": ("分享匿名使用資料", "隱私權詳細資料")
        ]

        for language in AppLanguage.allCases {
            let values = Dictionary(uniqueKeysWithValues: try entries(for: language).map { ($0.key, $0.value) })
            let copy = try XCTUnwrap(expected[language.rawValue])
            XCTAssertEqual(values["onboarding.analytics.toggle"], copy.toggle, "\(language.rawValue) toggle copy")
            XCTAssertEqual(values["settings.analytics.privacyDetails"], copy.privacy, "\(language.rawValue) privacy link copy")
        }
    }

    func testIconDesignerControlTranslationsArePresentInEveryLanguage() throws {
        let keys = LocalizationKey.allCases.map(\.rawValue).filter { $0.hasPrefix("iconDesigner.control.") }
        XCTAssertGreaterThanOrEqual(keys.count, 30, "Designer control labels must be explicitly catalogued")
        for language in AppLanguage.allCases {
            let values = Dictionary(uniqueKeysWithValues: try entries(for: language).map { ($0.key, $0.value) })
            for key in keys {
                XCTAssertFalse(
                    (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue).lproj: \(key) is missing or empty"
                )
            }
        }
    }

    func testEveryLocalizedValueDiffersFromItsKeyPlaceholder() throws {
        for language in AppLanguage.allCases {
            for entry in try entries(for: language) {
                XCTAssertNotEqual(
                    entry.value,
                    entry.key,
                    "\(language.rawValue).lproj leaves \(entry.key) as a raw key at line \(entry.line)"
                )
            }
        }
    }

    // MARK: - Parsing

    private func entries(for language: AppLanguage) throws -> [Entry] {
        let url = Self.resourcesDirectory
            .appendingPathComponent("\(language.rawValue).lproj")
            .appendingPathComponent("Localizable.strings")

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw LocalizationError.unreadable(url)
        }

        var result: [Entry] = []
        var seen = Set<String>()

        for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("/*") || line.hasPrefix("*") || line.hasPrefix("//") {
                continue
            }

            guard let match = line.wholeMatch(of: Self.pairPattern) else {
                throw LocalizationError.unparsableLine(
                    language: language.rawValue,
                    line: index + 1,
                    text: line
                )
            }

            let key = String(match.output.1)
            guard seen.insert(key).inserted else {
                throw LocalizationError.duplicatedKey(language: language.rawValue, key: key)
            }

            result.append(Entry(key: key, value: String(match.output.2), line: index + 1))
        }

        return result
    }

    private func placeholders(in value: String) -> [String] {
        value.matches(of: Self.placeholderPattern).map { String(value[$0.range]) }.sorted()
    }

    private static var resourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/Resources")
    }
}
