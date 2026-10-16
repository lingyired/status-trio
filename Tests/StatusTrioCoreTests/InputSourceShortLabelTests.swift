import XCTest
@testable import StatusTrioCore

final class InputSourceShortLabelTests: XCTestCase {
    func testASCIILayoutsCollapseToASingleLetter() {
        XCTAssertEqual(InputSourceShortLabel.make(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"]), "A")
        XCTAssertEqual(InputSourceShortLabel.make(id: "com.apple.keylayout.US", localizedName: "U.S.", languages: ["en"]), "A")
        XCTAssertEqual(InputSourceShortLabel.make(id: "com.apple.keylayout.British", localizedName: "British", languages: ["en"]), "B")
    }

    func testKnownIMEKindsUseTheirMarker() {
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.tencent.inputmethod.wetype.pinyin", localizedName: "微信输入法", languages: ["zh-Hans"]),
            "拼"
        )
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.apple.inputmethod.TCIM.Zhuyin", localizedName: "注音", languages: ["zh-Hant"]),
            "注"
        )
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", localizedName: "日文", languages: []),
            "あ"
        )
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.apple.inputmethod.Korean.2SetKorean", localizedName: "2-Set Korean", languages: []),
            "한"
        )
        XCTAssertEqual(InputSourceShortLabel.make(id: "com.sogou.inputmethod.sogou.wubi", localizedName: "搜狗五笔", languages: ["zh-Hans"]), "五")
        XCTAssertEqual(InputSourceShortLabel.make(id: "com.apple.inputmethod.TCIM.Cangjie", localizedName: "倉頡", languages: ["zh-Hant"]), "倉")
    }

    func testLanguageTagFallsBackToCJKIdeographMarker() {
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.example.ja.ime", localizedName: "Example", languages: ["ja"]),
            "あ"
        )
    }

    func testUnknownSourcesUseTheFirstNameGrapheme() {
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.example.thirdparty", localizedName: "微信输入法", languages: []),
            "微"
        )
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.example.thirdparty", localizedName: "France", languages: []),
            "F"
        )
    }

    func testGraphemeClustersAreNeverSplit() {
        // A flag emoji is one user-perceived grapheme across two scalars; the
        // label must carry it whole rather than half of a regional indicator.
        XCTAssertEqual(
            InputSourceShortLabel.make(id: "com.example.flag", localizedName: "🇨🇳 Keyboard", languages: []),
            "🇨🇳"
        )
    }

    func testBlankNamesProduceNoLabel() {
        XCTAssertNil(InputSourceShortLabel.make(id: "com.example.blank", localizedName: "   ", languages: []))
        XCTAssertNil(InputSourceShortLabel.make(id: "com.example.empty", localizedName: "", languages: []))
    }
}
