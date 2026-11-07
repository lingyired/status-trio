import XCTest
@testable import StatusTrioCore

final class InputSourceStateTests: XCTestCase {
    func testDrawingResolutionKeepsApplePinyinScriptLabelsAndThirdPartyIcons() {
        let iconURL = URL(fileURLWithPath: "/fixture/menu_icon.pdf")
        for (id, label) in [("com.apple.inputmethod.SCIM.ITABC", "简"),
                            ("com.apple.inputmethod.TCIM.Pinyin", "繁")] {
            let source = InputSourceDescriptor(
                id: id, localizedName: "Pinyin", primaryLanguage: "zh",
                iconURL: iconURL, shortLabel: label
            )
            let drawing = source.resolvedForDrawing(fileExists: { _ in true })
            XCTAssertNil(drawing.iconURL)
            XCTAssertEqual(drawing.shortLabel, label)
            XCTAssertEqual(drawing.id, source.id)
        }

        let thirdParty = InputSourceDescriptor(
            id: "com.example.pinyin", localizedName: "Pinyin", primaryLanguage: "zh-Hans",
            iconURL: iconURL, shortLabel: "简"
        )
        XCTAssertEqual(thirdParty.resolvedForDrawing(fileExists: { _ in true }), thirdParty)
    }

    func testResolvedKeepsOnlyEnabledSelectCapableSourcesInOrder() {
        let state = InputSourceState.resolved(
            selectedID: "com.apple.keylayout.ABC",
            rawSources: [
                raw(id: "com.apple.keylayout.ABC"),
                raw(id: "com.example.disabled", isEnabled: false),
                raw(id: "com.example.mode", isSelectCapable: false),
                raw(id: "com.example.pinyin")
            ]
        )

        XCTAssertEqual(state.sources.map(\.id), ["com.apple.keylayout.ABC", "com.example.pinyin"])
    }

    func testResolvedCarriesIconAndLanguageMetadata() throws {
        let url = URL(fileURLWithPath: "/Library/Input Methods/Example.app/Contents/Resources/menu_icon.pdf")
        let state = InputSourceState.resolved(
            selectedID: "com.example.pinyin",
            rawSources: [
                raw(id: "com.example.pinyin", languages: ["zh-Hans"], iconURL: url)
            ]
        )

        let descriptor = try XCTUnwrap(state.selectedDescriptor)
        XCTAssertEqual(descriptor.primaryLanguage, "zh-Hans")
        XCTAssertEqual(descriptor.iconURL, url)
        XCTAssertEqual(descriptor.shortLabel, "简")
    }

    func testSelectedDescriptorIsNilWhenSelectionIsNotInTheEnabledList() {
        let state = InputSourceState.resolved(
            selectedID: "com.example.hidden",
            rawSources: [raw(id: "com.apple.keylayout.ABC")]
        )

        XCTAssertNil(state.selectedDescriptor)
    }

    private func raw(
        id: String,
        localizedName: String = "Example",
        languages: [String] = [],
        iconURL: URL? = nil,
        isEnabled: Bool = true,
        isSelectCapable: Bool = true
    ) -> RawInputSource {
        RawInputSource(
            id: id,
            localizedName: localizedName,
            languages: languages,
            iconImageURL: iconURL,
            isEnabled: isEnabled,
            isSelectCapable: isSelectCapable
        )
    }
}
