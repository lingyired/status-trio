import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class VPNMonitorTests: XCTestCase {
    func testStartPublishesTheCurrentReading() async {
        let reader = FakeVPNReader(reading: VPNProbeReading(tunnelInterfaces: ["utun4"]))
        let monitor = VPNMonitor(reader: reader, observer: FakeNetworkChangeObserver())

        let updated = expectation(description: "vpn status published")
        let task = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            let status = await iterator.next()
            XCTAssertEqual(status?.tunnelInterfaces, ["utun4"])
            XCTAssertTrue(status?.isTunnelConnected == true)
            updated.fulfill()
        }

        monitor.start()
        await fulfillment(of: [updated], timeout: 1)

        task.cancel()
        monitor.stop()
    }

    func testObserverChangePublishesTheNewReading() async {
        let reader = FakeVPNReader(reading: .empty)
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: reader, observer: observer)

        let updated = expectation(description: "proxy reading published")
        let task = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            while let status = await iterator.next() {
                if status.proxy?.endpoint == "127.0.0.1:10808" {
                    updated.fulfill()
                    return
                }
            }
        }

        monitor.start()
        reader.reading = VPNProbeReading(
            proxy: VPNProxyStatus(kind: .http, host: "127.0.0.1", port: 10808)
        )
        observer.send()
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(observer.startCount, 1)
        task.cancel()
        monitor.stop()
    }

    func testRecoverResubscribesAndReadsAgain() async {
        let reader = FakeVPNReader(reading: .empty)
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: reader, observer: observer)

        monitor.start()
        await waitFor("initial read") { reader.readCount == 1 }

        monitor.recover()
        XCTAssertEqual(observer.startCount, 2)
        XCTAssertEqual(observer.cancelCount, 1)
        await waitFor("recover read") { reader.readCount == 2 }

        monitor.stop()
    }

    func testRefreshBeforeStartDoesNothing() async {
        let reader = FakeVPNReader(reading: .empty)
        let monitor = VPNMonitor(reader: reader, observer: FakeNetworkChangeObserver())

        monitor.refresh()

        // The lifecycle guard returns before dispatching, so no read is queued.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reader.readCount, 0)
        monitor.stop()
    }

    func testStopAllowsRestartAndPublishesTheCurrentReadingAgain() async {
        let reader = FakeVPNReader(reading: VPNProbeReading(tunnelInterfaces: ["utun4"]))
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: reader, observer: observer)

        let firstUpdate = expectation(description: "initial VPN reading published")
        let firstTask = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            while let status = await iterator.next() {
                if status.tunnelInterfaces == ["utun4"] {
                    firstUpdate.fulfill()
                    return
                }
            }
        }
        monitor.start()
        await fulfillment(of: [firstUpdate], timeout: 1)
        firstTask.cancel()
        await firstTask.value

        monitor.stop()
        XCTAssertEqual(observer.cancelCount, 1)

        reader.reading = VPNProbeReading(tunnelInterfaces: ["utun8"])
        let restartedUpdate = expectation(description: "restarted VPN reading published")
        let restartedTask = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            while let status = await iterator.next() {
                if status.tunnelInterfaces == ["utun8"] {
                    restartedUpdate.fulfill()
                    return
                }
            }
        }
        monitor.start()
        await fulfillment(of: [restartedUpdate], timeout: 1)
        await waitFor("second read") { reader.readCount == 2 }
        XCTAssertEqual(observer.startCount, 2)

        restartedTask.cancel()
        monitor.stop()
    }

    /// A second `start()` must not subscribe twice: the store calls it once, but
    /// the guard is what keeps a future double call from doubling the reads.
    func testStartIsIdempotent() {
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: FakeVPNReader(reading: .empty), observer: observer)

        monitor.start()
        monitor.start()

        XCTAssertEqual(observer.startCount, 1)
        monitor.stop()
    }

    /// The synchronous `SystemConfiguration` read must never run on the main
    /// actor, or opening the panel can stall on a wedged `configd`. This models
    /// a read that cannot finish until another task runs: a main-actor
    /// implementation would deadlock the test instead of publishing.
    func testSlowSystemReadLeavesMainActorFreeToUnblockIt() async {
        let started = expectation(description: "background read started")
        let published = expectation(description: "result published")
        let release = DispatchSemaphore(value: 0)
        let reader = FakeVPNReader(reading: VPNProbeReading(tunnelInterfaces: ["utun4"]))
        reader.onRead = {
            XCTAssertFalse(Thread.isMainThread)
            started.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
        }
        let monitor = VPNMonitor(reader: reader, observer: FakeNetworkChangeObserver())

        let task = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            while let status = await iterator.next() {
                if status.tunnelInterfaces == ["utun4"] {
                    published.fulfill()
                    return
                }
            }
        }

        // If the read ran on the main actor, `start()` would block and the test
        // would never reach `await fulfillment(of: [started])`.
        monitor.start()
        await fulfillment(of: [started], timeout: 1)
        release.signal()
        await fulfillment(of: [published], timeout: 2)

        task.cancel()
        monitor.stop()
    }

    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(description)")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class FakeVPNReader: VPNReading {
    private let lock = NSLock()
    private var storedReading: VPNProbeReading
    private var storedReadCount = 0
    /// Runs after the read is taken, on whatever thread `read()` is called from.
    var onRead: (@Sendable () -> Void)?

    init(reading: VPNProbeReading) {
        self.storedReading = reading
    }

    var reading: VPNProbeReading {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedReading
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedReading = newValue
        }
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReadCount
    }

    func read() -> VPNProbeReading {
        lock.lock()
        storedReadCount += 1
        let value = storedReading
        lock.unlock()
        onRead?()
        return value
    }
}

private final class FakeNetworkChangeObserver: NetworkChangeObserving {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var handler: (@Sendable () -> Void)?

    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        startCount += 1
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func send() {
        handler?()
    }
}
