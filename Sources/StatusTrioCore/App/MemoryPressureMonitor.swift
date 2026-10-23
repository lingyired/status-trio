import Dispatch
import Foundation

@MainActor
protocol MemoryPressureEventSource: AnyObject {
    func resume()
    func cancel()
}

/// One OS event source; no polling timer or process-memory sampling in the app.
@MainActor
final class MemoryPressureMonitor {
    typealias SourceFactory = @MainActor (@escaping @MainActor () -> Void) -> any MemoryPressureEventSource

    var onPressure: (@MainActor () -> Void)?
    private let makeSource: SourceFactory
    private var source: (any MemoryPressureEventSource)?
    private var generation: UUID?

    init(makeSource: @escaping SourceFactory = { DispatchMemoryPressureSource(handler: $0) }) {
        self.makeSource = makeSource
    }

    func start() {
        guard source == nil else { return }
        let current = UUID()
        generation = current
        let next = makeSource { [weak self] in
            guard let self, generation == current else { return }
            onPressure?()
        }
        source = next
        next.resume()
    }

    func stop() {
        generation = nil
        source?.cancel()
        source = nil
    }
}

@MainActor
private final class DispatchMemoryPressureSource: MemoryPressureEventSource {
    // Teardown-only access outside MainActor: Dispatch cancellation is thread
    // safe, and deinit never reads or invokes the actor-isolated event handler.
    nonisolated(unsafe) private let source: any DispatchSourceMemoryPressure

    init(handler: @escaping @MainActor () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { handler() }
        }
    }

    func resume() { source.resume() }
    func cancel() { source.cancel() }
    deinit { source.cancel() }
}
