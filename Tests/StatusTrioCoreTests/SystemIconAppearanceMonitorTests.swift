import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct SystemIconAppearanceMonitorTests {
    @Test func reportsOnlyRealThemeChanges() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reported.isEmpty)

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        theme = clearTheme
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reported == [clearTheme])
    }

    @Test func reReadsWhenTheAppBecomesActive() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        let darkTheme = SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark)
        theme = darkTheme
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(reported == [darkTheme])
    }

    @Test func stopsReportingAfterStop() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()
        monitor.stop()

        theme = SystemIconAppearanceTheme(style: .clear, appearance: .light)
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)

        #expect(reported.isEmpty)
    }

    @Test func pollsUntilStopped() async throws {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let pollingInterval: TimeInterval = 0.05
        var readCount = 0
        let monitor = SystemIconAppearanceMonitor(
            readTheme: {
                readCount += 1
                return theme
            },
            notificationCenter: center,
            pollingInterval: pollingInterval
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        theme = clearTheme
        // A fixed sleep can finish before the timer gets a turn under load.
        let changeDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while reported.isEmpty, ContinuousClock.now < changeDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(reported == [clearTheme])

        monitor.stop()
        let readsAfterStop = readCount
        theme = SystemIconAppearanceTheme(style: .tinted, appearance: .dark)
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        let stoppedPollingDuration = Int64((pollingInterval * 2 + 0.05) * 1_000)
        let stoppedPollingDeadline = ContinuousClock.now.advanced(by: .milliseconds(stoppedPollingDuration))
        while ContinuousClock.now < stoppedPollingDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(readCount == readsAfterStop)
        #expect(reported == [clearTheme])
    }
}
