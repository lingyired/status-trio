import Carbon
import Foundation

@MainActor
enum ShortcutKeyLabel {
    static func string(
        for shortcut: StatusPanelShortcut,
        layoutCharacterProvider: ((UInt32) -> String?)? = nil
    ) -> String {
        let lookup: (UInt32) -> String?
        if let layoutCharacterProvider {
            lookup = layoutCharacterProvider
        } else {
            lookup = { keyCode in
                currentLayoutCharacter(for: keyCode)
            }
        }
        let layoutCharacter = lookup(shortcut.keyCode)?
            .uppercased(with: Locale.current)
        let keyName =
            specialKeyName(for: shortcut.keyCode)
            ?? layoutCharacter
            ?? "⌨\(shortcut.keyCode)"
        return modifierSymbols(for: shortcut.modifiers) + keyName
    }

    private static func modifierSymbols(for modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 {
            symbols += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            symbols += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            symbols += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            symbols += "⌘"
        }
        return symbols
    }

    private static func specialKeyName(for keyCode: UInt32) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "␣"
        case 51: return "⌫"
        case 53: return "⎋"
        case 64: return "F17"
        case 76: return "⌤"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "↘"
        case 120: return "F2"
        case 121: return "⇟"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }

    private static func currentLayoutCharacter(for keyCode: UInt32) -> String? {
        guard keyCode <= UInt32(UInt16.max),
              let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?
                  .takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(
                  inputSource,
                  kTISPropertyUnicodeKeyLayoutData
              ) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        return withExtendedLifetime(inputSource) {
            withExtendedLifetime(layoutData) {
                let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(
                    to: UCKeyboardLayout.self
                )
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let result = characters.withUnsafeMutableBufferPointer { buffer in
                    UCKeyTranslate(
                        keyboardLayout,
                        UInt16(keyCode),
                        UInt16(kUCKeyActionDisplay),
                        0,
                        UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        buffer.count,
                        &length,
                        buffer.baseAddress!
                    )
                }
                guard result == noErr, length > 0 else { return nil }
                let value = String(
                    decoding: characters.prefix(length),
                    as: UTF16.self
                )
                let trimmed = value.trimmingCharacters(in: .controlCharacters)
                guard !trimmed.isEmpty else { return nil }
                return trimmed.uppercased(with: Locale.current)
            }
        }
    }
}
