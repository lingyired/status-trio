import Darwin
import Foundation
import SystemConfiguration

/// The private address this Mac answers on, as the popover reports it.
///
/// Held apart from `StatusSnapshot` for the same reason `PrimaryLinkDetails`
/// is: an address that moves when DHCP renews is popover-only state, and the
/// menu bar and Dock icons must not be redrawn for it.
struct LocalIPDetails: Equatable, Sendable {
    let interfaceName: String?
    let address: String?

    static let unavailable = Self(interfaceName: nil, address: nil)
}

/// Picks the LAN address out of one `getifaddrs` pass.
///
/// A pure function over the interface list and the primary interface name, so
/// the interesting cases — a VPN holding the primary interface, a Mac whose
/// first enumerated interfaces carry no address, an interface that only has a
/// self-assigned link-local address — are reachable in a test without a live
/// system.
enum LocalIPResolver {
    /// Interface names that are never the LAN address.
    ///
    /// `lo0` is the loopback, the tunnels are VPN links, and `gif0`/`stf0` are
    /// macOS's own transition stubs: all of them can hold an IPv4 address that
    /// is not the private address the user means.
    static let excludedPrefixes = ["lo", "gif", "stf"]

    static func resolve(
        primaryInterface: String?,
        entries: [InterfaceAddressEntry]
    ) -> LocalIPDetails {
        let primaries = candidates(in: entries)
        // The interface macOS routes through is the one the user means when it
        // is a real link; a VPN tunnel that claimed primary service is skipped
        // so "Local IP" keeps reporting the physical LAN address.
        if let primaryInterface,
           let match = primaries.first(where: { $0.name == primaryInterface }) {
            return LocalIPDetails(interfaceName: match.name, address: match.address)
        }
        guard let first = primaries.first else { return .unavailable }
        return LocalIPDetails(interfaceName: first.name, address: first.address)
    }

    private static func candidates(in entries: [InterfaceAddressEntry]) -> [(name: String, address: String)] {
        entries.compactMap { entry -> (name: String, address: String)? in
            guard !isExcluded(entry.name),
                  let address = entry.ipv4Addresses.first(where: { !TunnelInterfaceClassifier.isLinkLocal($0) })
            else { return nil }
            return (entry.name, address)
        }
    }

    private static func isExcluded(_ name: String) -> Bool {
        TunnelInterfaceClassifier.isTunnelInterface(name)
            || excludedPrefixes.contains { name.hasPrefix($0) }
    }
}

/// Reads the LAN address on demand.
///
/// The protocol exists so a test can answer with a fixed interface list instead
/// of the live system.
protocol LocalIPReading: AnyObject {
    func read(completion: @escaping @Sendable (LocalIPDetails) -> Void)
}

private final class SystemLocalIPReader: @unchecked Sendable, LocalIPReading {
    private let queue = DispatchQueue(label: "StatusTrio.LocalIPReader")
    private let entries: @Sendable () -> [InterfaceAddressEntry]
    private let primaryInterface: @Sendable () -> String?

    init(
        entries: @escaping @Sendable () -> [InterfaceAddressEntry] = {
            InterfaceAddressReader.read()
        },
        primaryInterface: @escaping @Sendable () -> String? = {
            SystemLocalIPReader.readPrimaryInterface()
        }
    ) {
        self.entries = entries
        self.primaryInterface = primaryInterface
    }

    func read(completion: @escaping @Sendable (LocalIPDetails) -> Void) {
        let entries = self.entries
        let primaryInterface = self.primaryInterface
        queue.async {
            completion(
                LocalIPResolver.resolve(
                    primaryInterface: primaryInterface(),
                    entries: entries()
                )
            )
        }
    }

    /// The interface the system currently routes IPv4 through.
    ///
    /// While a VPN tunnel is up this names the tunnel, which is exactly why
    /// `LocalIPResolver` treats it as a preference rather than a verdict.
    private static func readPrimaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio.LocalIP" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(
                  store,
                  "State:/Network/Global/IPv4" as CFString
              ) as? [String: Any] else {
            return nil
        }
        return value["PrimaryInterface"] as? String
    }
}

/// The LAN address the popover reports.
///
/// Read only while the popover is open and the Local IP row is switched on, and
/// dropped when either stops being true, so the row never shows an address the
/// user has left and the Read is not paid for while the row is hidden.
@MainActor
final class LocalIPController: ObservableObject {
    @Published private(set) var details: LocalIPDetails = .unavailable

    private let reader: any LocalIPReading
    private let periodicRefreshInterval: Duration
    private let periodicRefreshSleep: @Sendable (Duration) async throws -> Void
    private var refreshGate = AsyncRequestGate()
    private(set) var isActive = false
    private var periodicRefreshTask: Task<Void, Never>?

    init(
        reader: any LocalIPReading = SystemLocalIPReader(),
        periodicRefreshInterval: Duration = .seconds(30),
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.reader = reader
        self.periodicRefreshInterval = periodicRefreshInterval
        self.periodicRefreshSleep = periodicRefreshSleep
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        schedulePeriodicRefresh()
        refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        // A read already in flight now has a completion this gate rejects, so
        // its answer cannot land after the popover closed. Dropping the value
        // keeps the next opening from painting the previous address.
        _ = refreshGate.advance()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        details = .unavailable
    }

    /// A fresh read. Called when the popover opens, when the row is switched on,
    /// and whenever the primary connection changes.
    func refresh() {
        guard isActive else { return }
        let request = refreshGate.advance()
        reader.read { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.refreshGate.accepts(request) else { return }
                if self.details != value {
                    self.details = value
                }
            }
        }
    }

    /// The periodic loop covers what no event reports: a DHCP renewal on a link
    /// that stayed up. Everything else reaches `refresh()` through a connection
    /// change.
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
