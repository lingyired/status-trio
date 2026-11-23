import Foundation

/// Store-side stand-in for the Direct-only `SystemIconAppearanceReader`, which
/// reads a private global preference via CFPreferences. The App Store build reads
/// no private preference; it reports the default appearance.
enum SystemIconAppearanceReader {
    static func current() -> SystemIconAppearanceTheme {
        SystemIconAppearanceTheme.parse(nil)
    }
}
