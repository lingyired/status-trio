import Foundation
import SystemConfiguration

/// Reads the wired link out of the system configuration store.
///
/// The protocol exists so a test can answer with a snapshot instead of the
/// live system, which is the only way to reach the interesting states — a VPN
/// on the primary service, a link with no address yet — deterministically.
protocol PrimaryLinkReading: AnyObject {
    func read(
        wiredInterfaces: [WiredInterface],
        completion: @escaping @Sendable (PrimaryLinkDetails?) -> Void
    )
}

/// One Ethernet interface this Mac reports.
///
/// The two names answer different questions and the row uses both: the BSD name
/// (`en9`) is what the system configuration is keyed by and what the subtitle
/// shows, while the display name (`iPhone USB`) is what the reader recognises
/// and what the title shows. macOS derives the display name from the driver, so
/// it is localized and absent only for an interface the system does not
/// describe.
struct WiredInterface: Equatable, Sendable {
    let name: String
    let displayName: String?

    init(name: String, displayName: String? = nil) {
        self.name = name
        self.displayName = displayName
    }
}

/// The Ethernet interfaces this Mac has.
///
/// Separate from `PrimaryLinkReading` because it is a different question with a
/// different failure mode: this one answers "which interfaces could the wired
/// link be on", and the store then answers what is configured on them.
protocol WiredInterfaceProviding: Sendable {
    func wiredInterfaces() -> [WiredInterface]
}

struct SystemWiredInterfaceProvider: WiredInterfaceProviding {
    func wiredInterfaces() -> [WiredInterface] {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let ethernetType = kSCNetworkInterfaceTypeEthernet as String
        return interfaces.compactMap { interface -> WiredInterface? in
            guard let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  type == ethernetType,
                  let name = SCNetworkInterfaceGetBSDName(interface) else {
                return nil
            }
            return WiredInterface(
                name: name as String,
                displayName: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            )
        }
    }
}

/// Reads a `SCDynamicStore` snapshot and resolves the wired link out of it on a
/// serial queue, so the store's synchronous calls never run on the main actor
/// and cannot overlap.
private final class SystemPrimaryLinkReader: @unchecked Sendable, PrimaryLinkReading {
    private let queue = DispatchQueue(label: "StatusTrio.PrimaryLinkReader")
    private let snapshot: @Sendable () -> [String: [String: Any]]

    init(
        snapshot: @escaping @Sendable () -> [String: [String: Any]] = {
            SystemPrimaryLinkReader.readStoreSnapshot()
        }
    ) {
        self.snapshot = snapshot
    }

    func read(
        wiredInterfaces: [WiredInterface],
        completion: @escaping @Sendable (PrimaryLinkDetails?) -> Void
    ) {
        let snapshot = self.snapshot
        queue.async {
            completion(
                PrimaryLinkResolver.resolve(
                    wiredInterfaces: wiredInterfaces,
                    snapshot: snapshot()
                )
            )
        }
    }

    private static func readStoreSnapshot() -> [String: [String: Any]] {
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/.*" as CFString) as? [String] else {
            return [:]
        }
        var snapshot: [String: [String: Any]] = [:]
        for key in keys where key == "State:/Network/Global/IPv4" || key.hasPrefix("State:/Network/Service/") {
            if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                snapshot[key] = value
            }
        }
        return snapshot
    }
}

/// Queues a reader completion onto the main actor.
typealias PrimaryLinkCompletionDispatcher = @Sendable (
    _ action: @escaping @MainActor @Sendable () -> Void
) -> Void

/// The wired link the popover reports.
///
/// Held apart from `StatusSnapshot` on purpose: the snapshot is what the menu
/// bar and Dock icons are drawn from, and an address that changes when DHCP
/// renews must not be an icon input. This is popover-only state, read while the
/// popover is open and dropped when it closes.
@MainActor
final class PrimaryLinkController: ObservableObject {
    @Published private(set) var details: PrimaryLinkDetails?

    private let reader: any PrimaryLinkReading
    private let wiredInterfaces: any WiredInterfaceProviding
    private let periodicRefreshInterval: Duration
    private let periodicRefreshSleep: @Sendable (Duration) async throws -> Void
    private let completionDispatcher: PrimaryLinkCompletionDispatcher
    private var refreshGate = AsyncRequestGate()
    private(set) var isActive = false
    private var periodicRefreshTask: Task<Void, Never>?

    init(
        reader: any PrimaryLinkReading = SystemPrimaryLinkReader(),
        wiredInterfaces: any WiredInterfaceProviding = SystemWiredInterfaceProvider(),
        periodicRefreshInterval: Duration = .seconds(30),
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        completionDispatcher: @escaping PrimaryLinkCompletionDispatcher = { action in
            Task { @MainActor in action() }
        }
    ) {
        self.reader = reader
        self.wiredInterfaces = wiredInterfaces
        self.periodicRefreshInterval = periodicRefreshInterval
        self.periodicRefreshSleep = periodicRefreshSleep
        self.completionDispatcher = completionDispatcher
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        // A new opening invalidates every completion queued by a prior one.
        // While the popover is closed, `isActive` keeps those completions from
        // publishing until this activation advances the gate.
        _ = refreshGate.advance()
        schedulePeriodicRefresh()
        refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        // A read already in flight is rejected by `isActive` while the popover
        // is closed, then by the gate when the next activation advances it.
        // Dropping the value as well keeps the next opening from painting the
        // previous link's address: an unplugged cable must not leave an address
        // on screen.
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        details = nil
    }

    /// A fresh read of the wired link. Called when the popover opens and
    /// whenever the primary connection changes, which is what a cable, a VPN
    /// tunnel coming up, or a Wi-Fi switch reports.
    func refresh() {
        guard isActive else { return }
        let request = refreshGate.advance()
        reader.read(wiredInterfaces: wiredInterfaces.wiredInterfaces()) { [weak self] value in
            guard let self else { return }
            self.completionDispatcher { [weak self] in
                guard let self, self.isActive, self.refreshGate.accepts(request) else { return }
                if self.details != value {
                    self.details = value
                }
            }
        }
    }

    /// The periodic loop only covers what no event reports: a DHCP renewal on a
    /// link that stayed up. Everything else — the cable, the tunnel, the
    /// primary interface — reaches `refresh()` through a connection change.
    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        let interval = periodicRefreshInterval
        let sleep = periodicRefreshSleep
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh()
            }
        }
    }
}
