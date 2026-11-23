import Foundation
import Testing
@testable import StatusTrioCore

struct CoreWLANKnownNetworkProviderTests {
    @Test func mapsInjectedProfileSSIDsAndPassesTheInterface() {
        let snapshot = CoreWLANProfileSnapshotProvider(snapshot: .profiles(["Home", "Office"]))
        let provider = CoreWLANKnownNetworkProvider(valueProvider: snapshot.read)

        let ssids = provider.preferredNetworkSSIDs(interface: "en0")

        #expect(ssids == ["Home", "Office"])
        #expect(snapshot.interfaces == ["en0"])
        #expect(snapshot.callCount == 1)
    }

    @Test func nilConfigurationMapsToEmptyWithoutClaimingUnsupported() {
        let snapshot = CoreWLANProfileSnapshotProvider(snapshot: .unavailable)
        let provider = CoreWLANKnownNetworkProvider(valueProvider: snapshot.read)

        #expect(provider.preferredNetworkSSIDs(interface: "en0").isEmpty)
        #expect(snapshot.callCount == 1)
    }

    @Test func emptyProfileListMapsToEmpty() {
        let snapshot = CoreWLANProfileSnapshotProvider(snapshot: .profiles([]))
        let provider = CoreWLANKnownNetworkProvider(valueProvider: snapshot.read)

        #expect(provider.preferredNetworkSSIDs(interface: "en1").isEmpty)
    }

    @Test func duplicateProfileSSIDsAreDeduplicated() {
        let snapshot = CoreWLANProfileSnapshotProvider(
            snapshot: .profiles(["Home", "Home", "Office", "Office"])
        )
        let provider = CoreWLANKnownNetworkProvider(valueProvider: snapshot.read)

        #expect(provider.preferredNetworkSSIDs(interface: "en0") == ["Home", "Office"])
    }
}

private final class CoreWLANProfileSnapshotProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: CoreWLANPreferredNetworkSnapshot
    private var recordedInterfaces: [String] = []

    init(snapshot: CoreWLANPreferredNetworkSnapshot) {
        self.snapshot = snapshot
    }

    var interfaces: [String] { lock.withLock { recordedInterfaces } }
    var callCount: Int { lock.withLock { recordedInterfaces.count } }

    func read(interface: String) -> CoreWLANPreferredNetworkSnapshot {
        lock.withLock {
            recordedInterfaces.append(interface)
            return snapshot
        }
    }
}
