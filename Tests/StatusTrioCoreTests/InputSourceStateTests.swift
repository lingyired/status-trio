import XCTest
@testable import StatusTrioCore

final class InputSourceStateTests: XCTestCase {
    func testDrawingResolutionKeepsSystemIconUntilAMarkerStyleIsChosen() {
        let iconURL = URL(fileURLWithPath: "/fixture/menu_icon.pdf")
        for (id, label) in [("com.apple.inputmethod.SCIM.ITABC", "简"),
                            ("com.apple.inputmethod.TCIM.Pinyin", "繁")] {
            let source = InputSourceDescriptor(
                id: id, localizedName: "Pinyin", primaryLanguage: "zh",
                iconURL: iconURL, shortLabel: label
            )

            // Default (system icon): the source keeps its own image, exactly
            // like before #297.
            let system = source.resolvedForDrawing(style: .systemIcon, fileExists: { _ in true })
            XCTAssertEqual(system.iconURL, iconURL)
            XCTAssertEqual(system.shortLabel, label)

            // 简/繁: the system image is replaced by the script marker.
            let script = source.resolvedForDrawing(style: .script, fileExists: { _ in true })
            XCTAssertNil(script.iconURL)
            XCTAssertEqual(script.shortLabel, label)
            XCTAssertEqual(script.id, source.id)

            // 中: both scripts collapse to a single 中 glyph.
            let zhong = source.resolvedForDrawing(style: .zhong, fileExists: { _ in true })
            XCTAssertNil(zhong.iconURL)
            XCTAssertEqual(zhong.shortLabel, "中")
        }

        let thirdParty = InputSourceDescriptor(
            id: "com.example.pinyin", localizedName: "Pinyin", primaryLanguage: "zh-Hans",
            iconURL: iconURL, shortLabel: "简"
        )
        XCTAssertEqual(thirdParty.resolvedForDrawing(style: .script, fileExists: { _ in true }), thirdParty)
    }

    /// The override is decided by the stable input-source ID, not by the marker
    /// text, so changing the label mapping cannot silently disable it.
    func testSystemIconOverrideIsDecidedByIDNotMarkerText() {
        let iconURL = URL(fileURLWithPath: "/fixture/menu_icon.pdf")

        let apple = InputSourceDescriptor(
            id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "Pinyin",
            primaryLanguage: "zh", iconURL: iconURL, shortLabel: "拼"
        )
        XCTAssertTrue(apple.overridesSystemIcon)
        XCTAssertEqual(apple.drawingIconURL(style: .systemIcon, fileExists: { _ in true }), iconURL)
        XCTAssertNil(apple.drawingIconURL(style: .script, fileExists: { _ in true }))
        XCTAssertNil(apple.resolvedForDrawing(style: .script, fileExists: { _ in true }).iconURL)

        let thirdParty = InputSourceDescriptor(
            id: "com.example.pinyin", localizedName: "Pinyin",
            primaryLanguage: "zh-Hans", iconURL: iconURL, shortLabel: "简"
        )
        XCTAssertFalse(thirdParty.overridesSystemIcon)
        XCTAssertEqual(thirdParty.drawingIconURL(style: .script, fileExists: { _ in true }), iconURL)
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
