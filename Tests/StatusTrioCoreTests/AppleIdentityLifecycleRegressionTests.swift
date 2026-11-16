import Foundation
import Testing
@testable import StatusTrioCore

struct AppleIdentityLifecycleRegressionTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func candidate(_ id: String) -> AppleDeviceCandidate {
        AppleDeviceCandidate(id: .trustedDevice(id), name: "Phone", model: "iPhone18,1",
                             transports: [.network], trustRequired: false, evidence: .verifiedAppleModel)
    }

    @Test func successfulEmptyDiscoveryExcludesHistoryWithoutDeletingMetadata() {
        let history = [candidate("old")]
        let projected = AppleDeviceCatalog.currentCandidates(
            history: history, discovered: [], lastSuccessfulIDs: [], trustedSnapshots: [], now: now)
        #expect(projected.isEmpty)
        #expect(history.count == 1)
    }

    @Test func initialOrFailedDiscoveryDoesNotTreatEmptyAsRemoval() {
        let history = [candidate("old")]
        let projected = AppleDeviceCatalog.currentCandidates(
            history: history, discovered: [], lastSuccessfulIDs: nil, trustedSnapshots: [], now: now)
        #expect(projected == history)
    }

    @Test func freshSnapshotRetainsHistoricalIdentityOnlyWithinOriginalTTL() {
        let snapshot = MobileBatterySnapshot(id: "old", parentID: nil, name: "Phone", model: "iPhone18,1",
                                            batteryLevel: 45, isCharging: false, transport: .network,
                                            observedAt: now.addingTimeInterval(-1199))
        let fresh = AppleDeviceCatalog.currentCandidates(
            history: [candidate("old")], discovered: [], lastSuccessfulIDs: [], trustedSnapshots: [snapshot], now: now)
        #expect(fresh.count == 1)
        let expired = AppleDeviceCatalog.currentCandidates(
            history: [candidate("old")], discovered: [], lastSuccessfulIDs: [], trustedSnapshots: [snapshot],
            now: now.addingTimeInterval(1))
        #expect(expired.isEmpty)
    }

    @Test func currentPhoneDoesNotKeepOldSameNamedTrustedID() {
        let active = candidate("new")
        let projected = AppleDeviceCatalog.currentCandidates(
            history: [candidate("old"), active], discovered: [active], lastSuccessfulIDs: [active.id],
            trustedSnapshots: [], now: now)
        #expect(projected.map(\.id) == [active.id])
    }
}
