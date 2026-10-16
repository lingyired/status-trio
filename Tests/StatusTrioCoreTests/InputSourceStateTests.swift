import XCTest
@testable import StatusTrioCore

final class InputSourceStateTests: XCTestCase {
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
        XCTAssertEqual(descriptor.shortLabel, "拼")
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
