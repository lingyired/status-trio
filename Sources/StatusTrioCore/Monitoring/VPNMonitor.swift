import Foundation
import SystemConfiguration

/// Delivers a callback whenever the system's network configuration changes.
protocol NetworkChangeObserving: AnyObject {
    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void)
    func cancel()
}

/// A `SCDynamicStore` watcher over the keys and patterns a tunnel or a proxy
/// can move: the global proxy dictionary, the global IPv4 set, per-interface
/// IPv4, and the PPP/IPSec state of every service.
///
/// Only the notification is subscribed here. The read stays in `VPNReader`, so
/// the callback carries no payload and nothing is parsed off the change list.
final class SystemNetworkChangeObserver: @unchecked Sendable, NetworkChangeObserving {
    private let lock = NSLock()
    private var store: SCDynamicStore?
    private var handler: (@Sendable () -> Void)?

    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        // A second `start` without a `cancel` would leave the first store
        // subscribed, reporting into a handler that is no longer the one in use.
        cancel()

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(
            nil,
            "StatusTrio.VPN" as CFString,
            vpnDynamicStoreCallback,
            &context
        ) else {
            return
        }

        let keys = [
            "State:/Network/Global/Proxies",
            "State:/Network/Global/IPv4"
        ] as CFArray
        let patterns = [
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Service/.*/PPP",
            "State:/Network/Service/.*/IPSec"
        ] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns) else { return }

        lock.withLock {
            self.store = store
            self.handler = handler
        }
        _ = SCDynamicStoreSetDispatchQueue(store, queue)
    }

    func cancel() {
        let store = lock.withLock { () -> SCDynamicStore? in
            let store = self.store
            self.store = nil
            self.handler = nil
            return store
        }
        guard let store else { return }
        // Clears the dispatch queue before the store is released, so a
        // notification already in flight cannot reach a handler that is gone.
        _ = SCDynamicStoreSetDispatchQueue(store, nil)
    }

    fileprivate func storeDidChange() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

/// The callback is a plain C function pointer, so it cannot capture context.
/// The observer is recovered from the store's `info` pointer instead, which is
/// safe because the monitor holds the observer for the whole subscription.
private let vpnDynamicStoreCallback: SCDynamicStoreCallBack = { _, _, info in
    guard let info else { return }
    let observer = Unmanaged<SystemNetworkChangeObserver>
        .fromOpaque(info)
        .takeUnretainedValue()
    observer.storeDidChange()
}

/// Watches the three VPN signals and publishes the resolved status.
///
/// The lifecycle moves between `idle` and `running`; `stop()` pauses the
/// observer and leaves the stream available for the next popover opening.
/// `recover()` re-subscribes while running after a wake.
///
/// The read is **not** done on the main actor. A full read is a `getifaddrs`
/// pass plus several `SystemConfiguration` lookups, including
/// `SCNetworkConnectionGetStatus` per configured service — a synchronous
/// round-trip to `configd`. While a tunnel is connecting or disconnecting, or
/// `configd` is wedged, that call can block for seconds, and the store reads it
/// on every popover opening. It therefore runs on a dedicated utility queue so
/// opening the panel can never stall on it. Results are published back on the
/// main actor behind a token guard so a slow read cannot overwrite a newer one,
/// a read that never returns is abandoned by `ReadWatchdog` and retried with
/// backoff (on a fresh queue, so the retry is not stuck behind the abandoned
/// block), and bursts collapse to one in-flight read plus one follow-up.
@MainActor
final class VPNMonitor: VPNMonitoring {
    private enum Lifecycle {
        case idle
        case running
    }

    private(set) var updates: AsyncStream<VPNStatus>

    nonisolated(unsafe) private let reader: any VPNReading
    nonisolated(unsafe) private let observer: any NetworkChangeObserving
    private let queue = DispatchQueue(label: "StatusTrio.VPN")
    /// Synchronous IPC must run off both the main actor and the cooperative
    /// executor. A read that never returns would block every later read behind
    /// it on this serial queue, so it is replaced when a read is abandoned.
    private var readQueue = DispatchQueue(label: "StatusTrio.VPN.read", qos: .utility)
    private let readWatchdog: ReadWatchdog
    private var continuation: AsyncStream<VPNStatus>.Continuation
    private var lifecycle = Lifecycle.idle
    private var readInFlight = false
    private var refreshPending = false
    private var readToken: UInt64 = 0
    /// The last value handed to the stream, so a notification that changed
    /// nothing does not wake the store.
    private var lastPublished: VPNStatus?

    init(
        reader: any VPNReading = SystemVPNReader(),
        observer: any NetworkChangeObserving = SystemNetworkChangeObserver(),
        readTimeout: Duration = .seconds(2),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.reader = reader
        self.observer = observer
        readWatchdog = ReadWatchdog(
            baseTimeout: readTimeout,
            maxTimeout: .seconds(60),
            sleep: readTimeoutSleep
        )
        (updates, continuation) = MonitorStream.make(of: VPNStatus.self)
    }

    deinit {
        observer.cancel()
        continuation.finish()
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running
        startObserving()
        refresh()
    }

    func refresh() {
        guard lifecycle == .running else { return }
        // Coalesce event bursts and polling while a slow service replies. At
        // most one read and one follow-up are retained, regardless of latency.
        guard !readInFlight else {
            refreshPending = true
            return
        }
        readInFlight = true
        readToken &+= 1
        let token = readToken
        let readQueue = self.readQueue
        readWatchdog.arm { [weak self] in
            self?.abandonTimedOutRead(token: token)
        }
        readQueue.async { [weak self] in
            guard let self else { return }
            let status = VPNStatusResolver.resolve(self.reader.read())
            Task { @MainActor [weak self] in
                // A completion that arrives after the read was declared stuck,
                // or after a later trigger superseded it, belongs to a retired
                // token: it must not release the latch of the read that
                // replaced it, nor publish over it.
                guard let self, token == self.readToken else { return }
                self.readWatchdog.cancel()
                guard self.lifecycle == .running else { return }
                self.readWatchdog.recordSuccess()
                self.readInFlight = false
                self.publish(status)
                if self.refreshPending {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
    }

    /// The read hit its watchdog deadline. Retire the stuck serial queue (its
    /// block may never return) and retry on a fresh one; the abandoned
    /// completion is ignored by the token guard.
    private func abandonTimedOutRead(token: UInt64) {
        guard token == readToken else { return }
        readToken &+= 1
        readInFlight = false
        readQueue = DispatchQueue(label: "StatusTrio.VPN.read", qos: .utility)
        refresh()
    }

    /// Re-subscribes and reads again. The old subscription is cancelled first,
    /// the same way `NetworkConnectionMonitor.recover()` cancels its path
    /// monitor, so a monitor recovered twice cannot end up with two live
    /// stores both reporting.
    func recover() {
        guard lifecycle == .running else { return }
        observer.cancel()
        startObserving()
        refresh()
    }

    func stop() {
        guard lifecycle == .running else { return }
        lifecycle = .idle
        readWatchdog.cancel()
        // Retire the token so a read still in flight cannot publish after stop.
        readToken &+= 1
        readInFlight = false
        refreshPending = false
        observer.cancel()
        // Reopening must publish even when the status matches the last value
        // from the previous visible session.
        lastPublished = nil
        continuation.finish()
        (updates, continuation) = MonitorStream.make(of: VPNStatus.self)
    }

    private func startObserving() {
        observer.start(queue: queue) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func publish(_ status: VPNStatus) {
        guard lifecycle == .running, status != lastPublished else { return }
        lastPublished = status
        continuation.yield(status)
    }
}
