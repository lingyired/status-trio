import SwiftUI

private struct SystemIconAppearanceReaderKey: EnvironmentKey {
    static var defaultValue: () -> SystemIconAppearanceTheme {
        { .default }
    }
}

extension EnvironmentValues {
    var systemIconAppearance: () -> SystemIconAppearanceTheme {
        get { self[SystemIconAppearanceReaderKey.self] }
        set { self[SystemIconAppearanceReaderKey.self] = newValue }
    }
}
