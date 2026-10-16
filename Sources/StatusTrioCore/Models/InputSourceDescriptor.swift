import Foundation

/// One enabled, user-selectable macOS input source, shaped for the icon and the
/// status panel.
///
/// A pure value: no `TISInputSource` refs and no `NSImage`s, so it can travel
/// through `Sendable` snapshots and be compared for render-cache identity.
struct InputSourceDescriptor: Equatable, Hashable, Sendable {
    /// The stable Input Source ID (`com.apple.keylayout.ABC`). Selection always
    /// goes through this, never through the localized name.
    let id: String
    let localizedName: String
    let primaryLanguage: String?
    /// `kTISPropertyIconImageURL` when the source ships one. The renderer
    /// falls back to `shortLabel` and then to a keyboard symbol without it.
    let iconURL: URL?
    /// The 1-2 grapheme marker drawn when there is no usable icon.
    let shortLabel: String?
}

extension InputSourceDescriptor {
    /// The descriptor as the icon is allowed to draw it.
    ///
    /// An input source whose icon file is gone must degrade to its short label,
    /// never to a keyboard glyph behind a broken image. Resolution lives on the
    /// value so the live menu bar and Dock, which own the source publisher, and
    /// the settings previews, which resolve their own inputs, all degrade the
    /// same way instead of depending on which path assembled the inputs.
    func resolvedForDrawing(
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> InputSourceDescriptor {
        guard let iconURL, !fileExists(iconURL) else { return self }
        return InputSourceDescriptor(
            id: id,
            localizedName: localizedName,
            primaryLanguage: primaryLanguage,
            iconURL: nil,
            shortLabel: shortLabel
        )
    }
}

/// Pure rules for the marker drawn when an input source has no icon.
///
/// The label is derived from the stable ID plus the source's own language
/// metadata, so it never depends on one third-party IME's display name. Swift
/// `Character`s are user-perceived graphemes, so even emoji or composed CJK
/// glyphs are only ever sliced at safe boundaries.
enum InputSourceShortLabel {
    static func make(id: String, localizedName: String, languages: [String]) -> String? {
        let normalizedID = id.lowercased()

        if let layout = appleLayoutLabel(normalizedID) {
            return layout
        }
        if normalizedID.contains("pinyin") || localizedName.contains("拼音") {
            return "拼"
        }
        if normalizedID.contains("zhuyin") || localizedName.contains("注音")
            || localizedName.contains("注音輸入") {
            return "注"
        }
        if normalizedID.contains("japanese") || languages.contains("ja")
            || normalizedID.hasPrefix("com.apple.inputmethod.kotoeri") {
            return "あ"
        }
        if normalizedID.contains("korean") || languages.contains("ko") {
            return "한"
        }
        if normalizedID.contains("wubi") || localizedName.contains("五笔") {
            return "五"
        }
        if normalizedID.contains("cangjie") || localizedName.contains("倉頡")
            || localizedName.contains("仓颉") {
            return "倉"
        }

        let trimmed = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, !first.isWhitespace else { return nil }
        return String(first)
    }

    /// ASCII keyboard layouts read best as a single upper-case initial: the
    /// system menu bar shows `A` for ABC, and the identifier's suffix carries
    /// the same information for every other layout.
    private static func appleLayoutLabel(_ normalizedID: String) -> String? {
        let prefix = "com.apple.keylayout."
        guard normalizedID.hasPrefix(prefix) else { return nil }

        let suffix = String(normalizedID.dropFirst(prefix.count))
        if suffix == "abc" || suffix == "us" || suffix == "usextended" {
            return "A"
        }
        guard let firstASCII = suffix.first(where: { $0.isASCII && $0.isLetter }) else {
            return nil
        }
        return String(firstASCII).uppercased()
    }
}
