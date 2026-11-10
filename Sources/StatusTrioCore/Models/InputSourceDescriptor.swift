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
    /// Apple's known Pinyin modes draw an explicit 简/繁 marker instead of the
    /// shared system image; every other source — including third-party IMEs —
    /// keeps its own icon. Decided by the stable input-source ID alone, so it
    /// never depends on the marker text.
    var overridesSystemIcon: Bool {
        Self.systemIconOverrideIDs.contains(id.lowercased())
    }

    /// The Apple input-source IDs whose system image is replaced by `shortLabel`.
    private static let systemIconOverrideIDs: Set<String> = [
        "com.apple.inputmethod.scim.itabc",
        "com.apple.inputmethod.tcim.pinyin",
    ]

    /// The icon this source may draw, or `nil` to fall back to `shortLabel`.
    ///
    /// This is the single source of truth for the menu bar, Dock, settings
    /// previews and the input-source list. The Apple Pinyin override is applied
    /// only when `style` asks for a text marker; `.systemIcon` keeps the source's
    /// own image, which is the pre-#297 behaviour.
    func drawingIconURL(style: InputSourceMarkerStyle) -> URL? {
        guard overridesSystemIcon, style.drawsTextMarker else { return iconURL }
        return nil
    }

    func drawingIconURL(style: InputSourceMarkerStyle, fileExists: (URL) -> Bool) -> URL? {
        guard let iconURL = drawingIconURL(style: style), fileExists(iconURL) else {
            return nil
        }
        return iconURL
    }

    /// The marker drawn for this source under `style`. Only the Apple Pinyin
    /// override changes it: `.script` keeps 简/繁, `.zhong` draws 中, and
    /// `.systemIcon` (or any non-override source) keeps the label as-is.
    func drawingShortLabel(style: InputSourceMarkerStyle) -> String? {
        guard overridesSystemIcon, style.drawsTextMarker else { return shortLabel }
        return style == .zhong ? "中" : shortLabel
    }

    /// The descriptor with `style` baked into `iconURL` / `shortLabel`, so a
    /// renderer that only reads those two fields — or that re-resolves the value
    /// with the default style — still draws the same thing.
    func applying(markerStyle: InputSourceMarkerStyle) -> InputSourceDescriptor {
        InputSourceDescriptor(
            id: id,
            localizedName: localizedName,
            primaryLanguage: primaryLanguage,
            iconURL: drawingIconURL(style: markerStyle),
            shortLabel: drawingShortLabel(style: markerStyle)
        )
    }

    /// Explicit English keyboard layouts only. An IME's language metadata does
    /// not establish its internal Latin mode, so its icon remains untouched.
    func applying(_ modifiers: InputSourceModifiers) -> InputSourceDescriptor {
        let englishLayouts: Set<String> = [
            "com.apple.keylayout.abc", "com.apple.keylayout.us",
            "com.apple.keylayout.usextended", "com.apple.keylayout.british",
            "com.apple.keylayout.british-pc", "com.apple.keylayout.australian",
            "com.apple.keylayout.canadian", "com.apple.keylayout.irish",
            "com.apple.keylayout.dvorak", "com.apple.keylayout.colemak"
        ]
        guard englishLayouts.contains(id.lowercased()) else { return self }
        return InputSourceDescriptor(
            id: id, localizedName: localizedName, primaryLanguage: primaryLanguage,
            iconURL: nil, shortLabel: modifiers.isUppercase ? "A" : "a"
        )
    }

    /// The descriptor as the icon is allowed to draw it.
    ///
    /// An input source whose icon file is gone must degrade to its short label,
    /// never to a keyboard glyph behind a broken image. Resolution lives on the
    /// value so the live menu bar and Dock, which own the source publisher, and
    /// the settings previews, which resolve their own inputs, all degrade the
    /// same way instead of depending on which path assembled the inputs.
    func resolvedForDrawing(
        style: InputSourceMarkerStyle = .systemIcon,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> InputSourceDescriptor {
        let resolvedIconURL = drawingIconURL(style: style, fileExists: fileExists)
        let resolvedShortLabel = drawingShortLabel(style: style)
        guard resolvedIconURL != iconURL || resolvedShortLabel != shortLabel else {
            return self
        }
        return InputSourceDescriptor(
            id: id,
            localizedName: localizedName,
            primaryLanguage: primaryLanguage,
            iconURL: resolvedIconURL,
            shortLabel: resolvedShortLabel
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
        if normalizedID == "com.apple.inputmethod.scim.itabc" {
            return "简"
        }
        if normalizedID == "com.apple.inputmethod.tcim.pinyin" {
            return "繁"
        }
        if normalizedID.contains("pinyin") || localizedName.contains("拼音")
            || localizedName.lowercased().contains("pinyin") {
            return pinyinScriptLabel(localizedName: localizedName, languages: languages) ?? "拼"
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

    /// Script evidence applies only after identifying Pinyin, so other Chinese
    /// input methods keep their own markers. Ambiguous metadata stays generic.
    private static func pinyinScriptLabel(localizedName: String, languages: [String]) -> String? {
        let scripts = Set(languages.compactMap { language -> String? in
            let subtags = language.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-")
            guard subtags.count > 1, subtags[0] == "zh" else { return nil }
            switch subtags[1] {
            case "hans": return "简"
            case "hant": return "繁"
            default: return nil
            }
        })
        if scripts.count == 1 { return scripts.first }
        if scripts.count > 1 { return nil }

        let name = localizedName.lowercased()
        let isSimplified = name.contains("简体") || name.contains("簡體") || name.contains("simplified")
        let isTraditional = name.contains("繁体") || name.contains("繁體") || name.contains("traditional")
        guard isSimplified != isTraditional else { return nil }
        return isSimplified ? "简" : "繁"
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
