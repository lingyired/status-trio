import Foundation

enum DirectSystemIconAppearanceReader {
    static let themeDefaultsKey = "AppleIconAppearanceTheme"

    /// Reads the macOS "icon & widget style" preference from the global
    /// (any application) domain. This is Direct-only because the Store build
    /// must not inspect another application's preferences.
    static func current() -> SystemIconAppearanceTheme {
        SystemIconAppearanceReader.current(
            readValue: readGlobalString,
            key: themeDefaultsKey
        )
    }

    static func readGlobalString(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? String
    }
}
