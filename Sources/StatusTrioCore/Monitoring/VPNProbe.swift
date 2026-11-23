import Darwin
import Foundation
import SystemConfiguration

// MARK: - Interfaces

/// One `getifaddrs` pass, collapsed to a single entry per interface name.
struct InterfaceAddressEntry: Equatable, Sendable {
    let name: String
    let flags: UInt32
    let ipv4Addresses: [String]
}

enum InterfaceAddressReader {
    /// Reads every interface with its flags and IPv4 addresses.
    ///
    /// `getifaddrs` returns one entry per address, not per interface, so the
    /// entries are folded by name here: the flags of the last entry and the
    /// concatenated address list. Repeated names always agree on their flags.
    static func read() -> [InterfaceAddressEntry] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var order: [String] = []
        var flagsByName: [String: UInt32] = [:]
        var addressesByName: [String: [String]] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let node = entry.pointee
            cursor = node.ifa_next

            guard let name = String(validatingCString: node.ifa_name) else { continue }
            if flagsByName[name] == nil {
                order.append(name)
            }
            flagsByName[name] = UInt32(node.ifa_flags)

            guard let address = node.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let text = numericHost(of: address) else {
                continue
            }
            addressesByName[name, default: []].append(text)
        }

        return order.map { name in
            InterfaceAddressEntry(
                name: name,
                flags: flagsByName[name] ?? 0,
                ipv4Addresses: addressesByName[name] ?? []
            )
        }
    }

    private static func numericHost(of address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return string(fromCString: host)
    }

    /// The numeric host `getnameinfo` wrote into a fixed buffer, stopping at the
    /// null terminator. Built from bytes rather than `String(cString:)` because
    /// the `CChar` convenience initializers are deprecated in Swift 6.
    private static func string(fromCString buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

protocol TunnelInterfaceReading: AnyObject {
    func readTunnelInterfaces() -> [String]
}

final class SystemTunnelInterfaceReader: @unchecked Sendable, TunnelInterfaceReading {
    func readTunnelInterfaces() -> [String] {
        InterfaceAddressReader.read().compactMap { entry in
            guard TunnelInterfaceClassifier.isTunnelInterface(entry.name),
                  TunnelInterfaceClassifier.isActiveTunnel(
                      flags: entry.flags,
                      ipv4Addresses: entry.ipv4Addresses
                  ) else {
                return nil
            }
            return entry.name
        }
    }
}

// MARK: - System VPN services

protocol VPNServiceReadingProviding: AnyObject {
    func readServices() -> [VPNServiceReading]
}

/// Reads the VPN services configured in System Settings and asks each one
/// whether it is connected.
///
/// Reading the service list needs no entitlement and no root: `scutil --nc
/// list` is the same query, and it runs as an ordinary user. The one caveat is
/// that macOS treats the network preferences as administrative, so a standard
/// (non-admin) account can be refused the list. That failure is survivable by
/// design: the name is decoration, and the row's verdict does not depend on it.
final class SystemVPNServiceReader: @unchecked Sendable, VPNServiceReadingProviding {
    /// Interface types that identify a service as a VPN. `PPTP` is deliberately
    /// absent: it was removed from macOS and the constant is deprecated.
    static let vpnInterfaceTypes: Set<String> = [
        kSCNetworkInterfaceTypePPP as String,
        kSCNetworkInterfaceTypeIPSec as String,
        kSCNetworkInterfaceTypeL2TP as String
    ]

    func readServices() -> [VPNServiceReading] {
        guard let preferences = SCPreferencesCreate(
            nil,
            "StatusTrio.VPN" as CFString,
            nil
        ) else {
            return []
        }
        guard let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
            return []
        }

        return services.compactMap { service in
            guard let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  Self.vpnInterfaceTypes.contains(type) else {
                return nil
            }
            let name = (SCNetworkServiceGetName(service) as String?) ?? ""
            guard !name.isEmpty,
                  let serviceID = SCNetworkServiceGetServiceID(service) else {
                return nil
            }
            return VPNServiceReading(
                serviceID: serviceID as String,
                name: name,
                state: Self.connectionState(serviceID: serviceID),
                isEnabled: SCNetworkServiceGetEnabled(service)
            )
        }
    }

    private static func connectionState(serviceID: CFString) -> VPNConnectionState {
        guard let connection = SCNetworkConnectionCreateWithServiceID(
            nil, serviceID, nil, nil
        ) else {
            return .invalid
        }
        switch SCNetworkConnectionGetStatus(connection).rawValue {
        case SCNetworkConnectionStatus.connected.rawValue: return .connected
        case SCNetworkConnectionStatus.connecting.rawValue: return .connecting
        case SCNetworkConnectionStatus.disconnecting.rawValue: return .disconnecting
        case SCNetworkConnectionStatus.disconnected.rawValue: return .disconnected
        default: return .invalid
        }
    }
}

// MARK: - System-wide proxy

protocol VPNProxyReadingProviding: AnyObject {
    func readProxy() -> VPNProxyStatus?
}

final class SystemVPNProxyReader: @unchecked Sendable, VPNProxyReadingProviding {
    private let store: SCDynamicStore?

    init() {
        store = SCDynamicStoreCreate(
            nil,
            "StatusTrio.VPN" as CFString,
            nil,
            nil
        )
    }

    func readProxy() -> VPNProxyStatus? {
        guard let store,
              let value = SCDynamicStoreCopyValue(
                  store,
                  "State:/Network/Global/Proxies" as CFString
              ) as? [String: Any] else {
            return nil
        }
        return Self.proxy(from: value)
    }

    /// Turns one `State:/Network/Global/Proxies` dictionary into a status.
    ///
    /// The dictionary carries a flag and an endpoint per protocol, plus a PAC
    /// flag. A fixed endpoint is preferred over a PAC script: it is what the
    /// row can print, and a configuration that sets both is reported by the
    /// endpoint it actually dials.
    static func proxy(from value: [String: Any]) -> VPNProxyStatus? {
        let candidates: [(enabled: String, host: String, port: String, kind: VPNProxyStatus.Kind)] = [
            ("HTTPEnable", "HTTPProxy", "HTTPPort", .http),
            ("HTTPSEnable", "HTTPSProxy", "HTTPSPort", .https),
            ("SOCKSEnable", "SOCKSProxy", "SOCKSPort", .socks)
        ]

        for candidate in candidates {
            guard isEnabled(value[candidate.enabled]) else { continue }
            return VPNProxyStatus(
                kind: candidate.kind,
                host: value[candidate.host] as? String,
                port: integer(value[candidate.port])
            )
        }

        guard isEnabled(value["ProxyAutoConfigEnable"]) else { return nil }
        return VPNProxyStatus(
            kind: .automaticConfiguration,
            host: value["ProxyAutoConfigURLString"] as? String,
            port: nil
        )
    }

    private static func isEnabled(_ raw: Any?) -> Bool {
        integer(raw).map { $0 != 0 } ?? false
    }

    private static func integer(_ raw: Any?) -> Int? {
        (raw as? NSNumber)?.intValue
    }
}

// MARK: - Aggregate

protocol VPNReading: AnyObject {
    func read() -> VPNProbeReading
}

final class SystemVPNReader: @unchecked Sendable, VPNReading {
    private let interfaces: any TunnelInterfaceReading
    private let services: any VPNServiceReadingProviding
    private let proxy: any VPNProxyReadingProviding

    init(
        interfaces: any TunnelInterfaceReading = SystemTunnelInterfaceReader(),
        services: any VPNServiceReadingProviding = SystemVPNServiceReader(),
        proxy: any VPNProxyReadingProviding = SystemVPNProxyReader()
    ) {
        self.interfaces = interfaces
        self.services = services
        self.proxy = proxy
    }

    func read() -> VPNProbeReading {
        VPNProbeReading(
            tunnelInterfaces: interfaces.readTunnelInterfaces(),
            services: services.readServices(),
            proxy: proxy.readProxy()
        )
    }
}
