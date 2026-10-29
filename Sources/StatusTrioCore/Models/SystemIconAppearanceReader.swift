import Foundation

enum SystemIconAppearanceReader {
    static func current(
        readValue: (String) -> String?,
        key: String
    ) -> SystemIconAppearanceTheme {
        SystemIconAppearanceTheme.parse(readValue(key))
    }
}
