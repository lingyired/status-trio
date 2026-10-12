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

    @Test func pollsUntilStopped() {
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
        let changeDeadline = Date().addingTimeInterval(2)
        while reported.isEmpty, Date() < changeDeadline {
            _ = RunLoop.main.run(
                mode: .default,
                before: min(changeDeadline, Date().addingTimeInterval(0.01))
            )
        }

        #expect(reported == [clearTheme])

        monitor.stop()
        let readsAfterStop = readCount
        theme = SystemIconAppearanceTheme(style: .tinted, appearance: .dark)
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        let stoppedPollingDeadline = Date().addingTimeInterval(pollingInterval * 2 + 0.05)
        while Date() < stoppedPollingDeadline {
            _ = RunLoop.main.run(
                mode: .default,
                before: min(stoppedPollingDeadline, Date().addingTimeInterval(0.01))
            )
        }

        #expect(readCount == readsAfterStop)
        #expect(reported == [clearTheme])
    }
}
