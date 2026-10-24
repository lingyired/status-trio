import CoreWLAN
import Foundation

/// One read of the preferred-network profiles exposed by CoreWLAN.
///
/// `unavailable` covers a missing interface and a `configuration()` read that
/// returned nil, including a sandbox or permission-restricted read. It is not
/// evidence that CoreWLAN lacks the capability.
enum CoreWLANPreferredNetworkSnapshot: Equatable, Sendable {
    case profiles([String])
    case unavailable
}

/// Reads preferred-network SSIDs through public CoreWLAN configuration APIs.
///
/// This provider never asks for a password and never prompts for permission. The
/// existing `WiFiKnownNetworkProviding` contract has no failure state, so a nil
/// configuration is represented as an empty set for that enrichment path while
/// the snapshot keeps the distinction available to tests and future callers.
struct CoreWLANKnownNetworkProvider: WiFiKnownNetworkProviding {
    typealias ValueProvider = @Sendable (String) -> CoreWLANPreferredNetworkSnapshot

    private let valueProvider: ValueProvider

    init(
        valueProvider: @escaping ValueProvider = CoreWLANKnownNetworkProvider.readSnapshot
    ) {
        self.valueProvider = valueProvider
    }

    func preferredNetworkSSIDs(interface: String) -> Set<String> {
        switch valueProvider(interface) {
        case let .profiles(ssids):
            return Set(ssids.filter { !$0.isEmpty })
        case .unavailable:
            return []
        }
    }

    static func readSnapshot(interface: String) -> CoreWLANPreferredNetworkSnapshot {
        guard let wifiInterface = CWWiFiClient.shared().interface(withName: interface),
              let configuration = wifiInterface.configuration() else {
            return .unavailable
        }
        let profiles = configuration.networkProfiles.array.compactMap {
            $0 as? CWNetworkProfile
        }
        guard profiles.count == configuration.networkProfiles.count else {
            return .unavailable
        }
        return .profiles(profiles.compactMap(\.ssid))
    }
}
