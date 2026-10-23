import Testing
@testable import StatusTrioCore

@MainActor
struct MemoryPressureMonitorTests {
    @Test func startsOnceAndRejectsEventsFromRetiredSources() {
        var sources: [ManualPressureSource] = []
        let monitor = MemoryPressureMonitor { handler in
            let source = ManualPressureSource(handler: handler)
            sources.append(source)
            return source
        }
        var events = 0
        monitor.onPressure = { events += 1 }
        monitor.start()
        monitor.start()
        #expect(sources.count == 1)
        sources[0].fire()
        #expect(events == 1)
        monitor.stop()
        sources[0].fire()
        #expect(events == 1)
        monitor.start()
        sources[0].fire()
        sources[1].fire()
        #expect(events == 2)
        #expect(sources[0].isCancelled)
        monitor.stop()
    }

    @Test func stoppingTheMonitorCancelsItsSource() {
        var source: ManualPressureSource?
        var monitor: MemoryPressureMonitor? = MemoryPressureMonitor { handler in
            let next = ManualPressureSource(handler: handler)
            source = next
            return next
        }
        monitor?.start()
        monitor?.stop()
        monitor = nil
        #expect(source?.isCancelled == true)
    }
}

@MainActor
private final class ManualPressureSource: MemoryPressureEventSource {
    let handler: @MainActor () -> Void
    private(set) var isCancelled = false
    init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    func resume() {}
    func cancel() { isCancelled = true }
    func fire() { handler() }
}
