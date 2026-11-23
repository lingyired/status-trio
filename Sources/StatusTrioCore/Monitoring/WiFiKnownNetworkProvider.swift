import Foundation

struct WiFiNetworkSetupCommand: Equatable, Sendable {
    let arguments: [String]

    static func listPreferredNetworks(interface: String) -> Self {
        Self(arguments: ["-listpreferredwirelessnetworks", interface])
    }
}

enum WiFiPreferredNetworkOutputParser {
    static func parse(_ output: String) -> Set<String> {
        var lines = output.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        guard !lines.isEmpty else { return [] }
        lines.removeFirst()

        return Set(lines.compactMap { rawLine in
            var line = String(rawLine)
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            while line.first == "\t" {
                line.removeFirst()
            }
            return line.isEmpty ? nil : line
        })
    }
}

protocol WiFiKnownNetworkProviding: Sendable {
    func preferredNetworkSSIDs(interface: String) -> Set<String>
}

/// Reads the system's preferred-network names without accessing their stored
/// passwords. The process runs on the CoreWLAN worker's serial queue.
///
/// The wait is bounded: `networksetup` can stall behind a wedged network stack,
/// and a synchronous read with no deadline would hold the CoreWLAN queue for the
/// rest of the process, stalling every later Wi-Fi read behind it. A timeout
/// degrades to "no known networks", the same answer an unreadable list already
/// gives the caller.
final class NetworksetupWiFiKnownNetworkProvider: WiFiKnownNetworkProviding, @unchecked Sendable {
    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    /// Comfortably under the monitor's five-second read watchdog, so a stalled
    /// command ends the read itself instead of having the watchdog abandon the
    /// worker thread.
    static let defaultTimeout: Duration = .seconds(3)

    private let timeout: Duration

    init(timeout: Duration = NetworksetupWiFiKnownNetworkProvider.defaultTimeout) {
        self.timeout = timeout
    }

    func preferredNetworkSSIDs(interface: String) -> Set<String> {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: Self.executableURL,
            arguments: WiFiNetworkSetupCommand
                .listPreferredNetworks(interface: interface)
                .arguments,
            timeout: timeout
        )
        guard case .exited(let outputData) = outcome else { return [] }
        return WiFiPreferredNetworkOutputParser.parse(
            String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
