import XCTest
@testable import StatusTrioCore

final class TelemetryLanguageTagTests: XCTestCase {
    func testNormalizesEachKnownSystemLanguageTag() {
        let cases: [(String, String)] = [
            ("th", "th"), ("th-TH", "th"), ("vi-VN", "vi"),
            ("sr-Latn", "sr-Latn"), ("sr-Latn-RS", "sr-Latn"),
            ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"),
            ("zh-CN", "zh-Hans"), ("pt-BR", "pt-BR"),
            ("pt-PT", "pt"), ("pt", "pt"), ("en-GB", "en"), ("de-DE", "de")
        ]

        for (raw, expected) in cases {
            XCTAssertEqual(TelemetryLanguageTag.osLanguageTag(preferred: [raw]), expected, raw)
        }
    }

    func testNormalizesUnknownLanguageWithScriptAndUnderscores() {
        XCTAssertEqual(TelemetryLanguageTag.osLanguageTag(preferred: ["az_Cyrl_AZ"]), "az-Cyrl")
    }

    func testKnownScriptWinsOverConflictingRegion() {
        XCTAssertEqual(TelemetryLanguageTag.osLanguageTag(preferred: ["zh-Hans-TW"]), "zh-Hans")
    }

    func testAcceptsServerValidPrimaryAndSingleCharacterSubtag() {
        XCTAssertEqual(TelemetryLanguageTag.osLanguageTag(preferred: ["abcde-x"]), "abcde")
    }

    func testOnlyTheFirstPreferredLanguageIsConsidered() {
        XCTAssertNil(TelemetryLanguageTag.osLanguageTag(preferred: ["en-garbage!", "fr-FR"]))
    }

    func testRejectsMalformedAndOversizedLanguageTags() {
        let invalid = [
            "", "-en", "en-", "en--US", "en-!bad", "中文", "x", "abcdefghx",
            "en-\(String(repeating: "a", count: 17))"
        ]

        for raw in invalid {
            XCTAssertNil(TelemetryLanguageTag.osLanguageTag(preferred: [raw]), raw)
        }
    }
}
