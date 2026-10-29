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
