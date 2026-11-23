import SwiftUI

struct LocalizedRootView<Content: View>: View {
    @ObservedObject var localization: Localization
    let content: Content

    init(
        localization: Localization,
        @ViewBuilder content: () -> Content
    ) {
        self.localization = localization
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(localization)
            .environment(\.layoutDirection, localization.resolvedLanguage.layoutDirection)
    }
}
