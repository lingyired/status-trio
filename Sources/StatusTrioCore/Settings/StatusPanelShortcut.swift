import AppKit
import Carbon
import Foundation

struct StatusPanelShortcut: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumKeyCode: UInt32 = 127
    static let primaryModifiers = UInt32(cmdKey | controlKey | optionKey)
    static let supportedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    private static let modifierKeyCodes: Set<UInt32> = [
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

    let keyCode: UInt32
    let modifiers: UInt32

    init?(keyCode: UInt32, modifiers: UInt32) {
        guard keyCode <= Self.maximumKeyCode,
              !Self.modifierKeyCodes.contains(keyCode),
              modifiers != 0,
              modifiers & ~Self.supportedModifiers == 0,
              modifiers & Self.primaryModifiers != 0 else {
            return nil
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        self.init(
            keyCode: keyCode,
            modifiers: Self.carbonModifiers(from: modifierFlags)
        )
    }

    var isKnownInputMethodConflict: Bool {
        // WeType and some other input methods consume Option-Space before a
        // Carbon hot key can receive it. Carbon registration still reports
        // success, so this known semantic conflict has to be rejected here.
        keyCode == UInt32(kVK_Space) && modifiers == UInt32(optionKey)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case keyCode
        case modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        let modifiers = try container.decode(UInt32.self, forKey: .modifiers)
        guard version == Self.currentSchemaVersion,
              let shortcut = Self(keyCode: keyCode, modifiers: modifiers) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid status panel shortcut payload"
                )
            )
        }
        self = shortcut
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .version)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
    }
}
