import AppKit

/// Reports changes to the app's effective appearance.
///
/// The Dock icon's background follows the system light/dark appearance when the
/// user picks the system style, but `AppIconController` owns no view whose
/// `effectiveAppearance` it could observe the way the menu bar observes its
/// status-item button. `NSApplication.effectiveAppearance` is the same signal
/// for the whole app and is KVO-observable.
@MainActor
protocol SystemAppearanceObserving: AnyObject {
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class ApplicationAppearanceObservation: SystemAppearanceObserving {
    private let application: NSApplication
    private var observation: NSKeyValueObservation?
    private var onChange: (@MainActor () -> Void)?

    init(application: NSApplication = .shared) {
        self.application = application
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard observation == nil else { return }
        // AppKit posts the change on the main thread; hop through the main actor
        // anyway so the callback contract does not depend on that detail.
        observation = application.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.onChange?()
            }
        }
    }

    func stop() {
        onChange = nil
        observation?.invalidate()
        observation = nil
    }
}
