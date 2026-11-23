import Foundation

enum SystemIconAppearanceReader {
    static let themeDefaultsKey = "AppleIconAppearanceTheme"

    /// Reads the macOS "icon & widget style" preference.
    ///
    /// The value lives in the global (any application) domain, so it has to be
    /// read with `CFPreferencesCopyAppValue`. `UserDefaults.standard` walks the
    /// search list and can therefore be shadowed by another domain.
    static func current(
        readValue: (String) -> String? = readGlobalString
    ) -> SystemIconAppearanceTheme {
        SystemIconAppearanceTheme.parse(readValue(themeDefaultsKey))
    }

    static func readGlobalString(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? String
    }
}
