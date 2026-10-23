import AppKit
import Carbon
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusPanelShortcutTests: XCTestCase {
    func testShortcutStartsUnassignedAndClearSurvivesReload() throws {
        let suiteName = "StatusPanelShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        XCTAssertNil(first.statusPanelShortcut)

        first.statusPanelShortcut = try XCTUnwrap(
            StatusPanelShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            SettingsStore(defaults: defaults).statusPanelShortcut,
            first.statusPanelShortcut
        )

        first.statusPanelShortcut = nil
        XCTAssertNil(SettingsStore(defaults: defaults).statusPanelShortcut)
    }

    func testModifierNormalizationAcceptsSupportedPrimaryModifiers() throws {
        let accepted: [(NSEvent.ModifierFlags, UInt32)] = [
            ([.command], UInt32(cmdKey)),
            ([.control], UInt32(controlKey)),
            ([.option], UInt32(optionKey)),
            ([.command, .shift], UInt32(cmdKey | shiftKey)),
            ([.control, .option, .shift], UInt32(controlKey | optionKey | shiftKey))
        ]

        for (flags, expectedModifiers) in accepted {
            let shortcut = try XCTUnwrap(
                StatusPanelShortcut(keyCode: 0, modifierFlags: flags)
            )
            XCTAssertEqual(shortcut.keyCode, 0)
            XCTAssertEqual(shortcut.modifiers, expectedModifiers)
        }
    }

    func testModifierNormalizationIgnoresCapsLockButRejectsInvalidPrimaryCombinations() throws {
        let shortcut = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: 1,
                modifierFlags: [.command, .shift, .capsLock, .numericPad, .function]
            )
        )
        XCTAssertEqual(shortcut.modifiers, UInt32(cmdKey | shiftKey))

        XCTAssertNil(StatusPanelShortcut(keyCode: 0, modifierFlags: []))
        XCTAssertNil(StatusPanelShortcut(keyCode: 0, modifierFlags: [.shift]))
        XCTAssertNil(StatusPanelShortcut(keyCode: 0, modifierFlags: [.shift, .capsLock]))
    }

    func testValidationRejectsModifierKeysAndUnsupportedBits() {
        let modifierKeyCodes: [UInt32] = [
            UInt32(kVK_RightCommand),
            UInt32(kVK_Command),
            UInt32(kVK_Shift),
            UInt32(kVK_CapsLock),
            UInt32(kVK_Option),
            UInt32(kVK_Control),
            UInt32(kVK_RightShift),
            UInt32(kVK_RightOption),
            UInt32(kVK_RightControl),
            UInt32(kVK_Function)
        ]
        for modifierKeyCode in modifierKeyCodes {
            XCTAssertNil(
                StatusPanelShortcut(
                    keyCode: modifierKeyCode,
                    modifiers: UInt32(cmdKey)
                )
            )
        }

        XCTAssertNil(
            StatusPanelShortcut(
                keyCode: 0,
                modifiers: UInt32(cmdKey | 0x0000_0001)
            )
        )
        XCTAssertNil(
            StatusPanelShortcut(
                keyCode: UInt32(UInt16.max) + 1,
                modifiers: UInt32(cmdKey)
            )
        )
    }

    func testOptionSpaceIsMarkedAsAKnownInputMethodConflict() throws {
        let optionSpace = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey)
            )
        )
        XCTAssertTrue(optionSpace.isKnownInputMethodConflict)
        XCTAssertFalse(
            StatusPanelShortcut(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: UInt32(optionKey)
            )?.isKnownInputMethodConflict == true
        )
    }

    func testCodablePayloadRequiresTheCurrentSchemaAndValidatedValues() throws {
        let shortcut = try XCTUnwrap(
            StatusPanelShortcut(keyCode: 12, modifiers: UInt32(cmdKey | optionKey))
        )
        let encoded = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(StatusPanelShortcut.self, from: encoded), shortcut)

        let invalidPayloads = [
            #"{"version":2,"keyCode":12,"modifiers":2560}"#,
            #"{"version":1,"keyCode":70000,"modifiers":2560}"#,
            #"{"version":1,"keyCode":12,"modifiers":1}"#,
            #"{"version":1,"keyCode":55,"modifiers":256}"#,
            #"{"version":1,"keyCode":54,"modifiers":256}"#,
            #"{"keyCode":12,"modifiers":2560}"#
        ]

        for payload in invalidPayloads {
            XCTAssertNil(
                try? JSONDecoder().decode(
                    StatusPanelShortcut.self,
                    from: Data(payload.utf8)
                ),
                payload
            )
        }
    }

    func testSettingsStoreIgnoresCorruptStoredPayload() throws {
        let suiteName = "StatusPanelShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            Data(#"{"version":1,"keyCode":70000,"modifiers":256}"#.utf8),
            forKey: SettingsStore.statusPanelShortcutDefaultsKey
        )

        XCTAssertNil(SettingsStore(defaults: defaults).statusPanelShortcut)
    }
}
