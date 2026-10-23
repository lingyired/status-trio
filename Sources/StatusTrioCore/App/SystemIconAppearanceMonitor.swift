import AppKit
import Foundation

@MainActor
final class SystemIconAppearanceMonitor {
    static let defaultPollingInterval: TimeInterval = 1

    /// Undocumented but exported by AppKit; registered by name so the app never
    /// links against a private symbol.
    static let didChangeNotificationName = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification"
    )

    private let readTheme: () -> SystemIconAppearanceTheme
    private let notificationCenter: NotificationCenter
    private let pollingInterval: TimeInterval
    private var lastTheme: SystemIconAppearanceTheme
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    var onChange: ((SystemIconAppearanceTheme) -> Void)?
    /// Runs on every poll before the cheap theme comparison so callers can
    /// reuse this cadence without starting another timer.
    var onPoll: (() -> Void)?

    init(
        readTheme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        notificationCenter: NotificationCenter = .default,
        pollingInterval: TimeInterval = SystemIconAppearanceMonitor.defaultPollingInterval
    ) {
        self.readTheme = readTheme
        self.notificationCenter = notificationCenter
        self.pollingInterval = pollingInterval
        self.lastTheme = readTheme()
    }

    func start() {
        guard observers.isEmpty, pollTimer == nil else { return }
        observe(Self.didChangeNotificationName)
        observe(NSApplication.didBecomeActiveNotification)

        // The system neither posts a usable change notification nor updates the
        // WindowServer configuration promptly, but it does write the preference
        // right away, so poll it. A cached preferences read is very cheap.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onPoll?()
                self?.refresh()
            }
        }
    }

    func stop() {
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Re-reads the system style and reports it when it actually changed.
    func refresh() {
        let theme = readTheme()
        guard theme != lastTheme else { return }
        lastTheme = theme
        onChange?(theme)
    }

    private func observe(_ name: Notification.Name) {
        observers.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        })
    }
}
