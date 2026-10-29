import SwiftUI

struct LocalizedRootView<Content: View>: View {
    @ObservedObject var localization: Localization
    let systemIconAppearance: () -> SystemIconAppearanceTheme
    let content: Content

    init(
        localization: Localization,
        systemIconAppearance: @escaping () -> SystemIconAppearanceTheme = { .default },
        @ViewBuilder content: () -> Content
    ) {
        self.localization = localization
        self.systemIconAppearance = systemIconAppearance
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(localization)
            .environment(\.layoutDirection, localization.resolvedLanguage.layoutDirection)
            .environment(\.systemIconAppearance, systemIconAppearance)
    }
}
