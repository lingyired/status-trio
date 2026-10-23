import Carbon
import XCTest
@testable import StatusTrioCore

@MainActor
final class ShortcutKeyLabelTests: XCTestCase {
    func testPrintsModifiersInNativeOrderAndUppercasesLayoutCharacters() throws {
        let shortcut = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: 0,
                modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
            )
        )

        XCTAssertEqual(
            ShortcutKeyLabel.string(
                for: shortcut,
                layoutCharacterProvider: { _ in "a" }
            ),
            "⌃⌥⇧⌘A"
        )
    }

    func testUsesReadableNamesForSpecialKeys() throws {
        let combos: [(UInt32, UInt32, String)] = [
            (36, UInt32(cmdKey), "⌘↩"),
            (48, UInt32(optionKey), "⌥⇥"),
            (49, UInt32(cmdKey), "⌘␣"),
            (51, UInt32(cmdKey), "⌘⌫"),
            (53, UInt32(controlKey), "⌃⎋"),
            (123, UInt32(optionKey), "⌥←"),
            (126, UInt32(controlKey), "⌃↑"),
            (122, UInt32(cmdKey), "⌘F1")
        ]

        for (keyCode, modifiers, expected) in combos {
            let shortcut = try XCTUnwrap(
                StatusPanelShortcut(keyCode: keyCode, modifiers: modifiers)
            )
            XCTAssertEqual(
                ShortcutKeyLabel.string(
                    for: shortcut,
                    layoutCharacterProvider: { _ in nil }
                ),
                expected
            )
        }
    }

    func testUnknownLayoutCharacterFallsBackWithoutCrashing() throws {
        let shortcut = try XCTUnwrap(
            StatusPanelShortcut(keyCode: 127, modifiers: UInt32(cmdKey))
        )

        XCTAssertEqual(
            ShortcutKeyLabel.string(
                for: shortcut,
                layoutCharacterProvider: { _ in nil }
            ),
            "⌘⌨127"
        )
    }

    func testCurrentKeyboardLayoutLookupReturnsAReadableResult() throws {
        for keyCode: UInt32 in [0, 1, 12, 36, 49, 126] {
            let shortcut = try XCTUnwrap(
                StatusPanelShortcut(keyCode: keyCode, modifiers: UInt32(cmdKey))
            )
            XCTAssertFalse(ShortcutKeyLabel.string(for: shortcut).isEmpty)
        }
    }
}
