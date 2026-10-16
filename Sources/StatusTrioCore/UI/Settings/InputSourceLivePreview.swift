import SwiftUI

/// Re-evaluates its content whenever the live input source changes.
///
/// `@ObservedObject` cannot wrap an optional, and the previews have to keep
/// working in tests and guides that never carry a controller, so the observer
/// is installed here only when there is something to observe.
struct InputSourceLivePreview<Content: View>: View {
    @ObservedObject private var controller: InputSourceController
    private let content: () -> Content

    init(
        controller: InputSourceController?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._controller = ObservedObject(wrappedValue: controller ?? InputSourcePreviewPlaceholder.shared)
        self.content = content
    }

    var body: some View {
        content()
    }
}

/// Static stored properties are not allowed on generic types, so the shared
/// placeholder lives here. A fresh controller on every body pass would make
/// SwiftUI drop and reinstall its subscription each time.
@MainActor
enum InputSourcePreviewPlaceholder {
    static let shared = InputSourceController()
}
