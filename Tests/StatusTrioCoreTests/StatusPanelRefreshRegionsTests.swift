import Testing
@testable import StatusTrioCore

/// The refresh regions are a bit mask. A member whose bit does not fit the
/// underlying integer type silently becomes the empty set: it can never be
/// recorded by `formUnion`, and `contains` on it is always true. That turned
/// two intended per-region refreshes into no-ops, so the mask is pinned here.
@MainActor
@Suite struct StatusPanelRefreshRegionsTests {
    private static let regions: [(name: String, region: StatusPanelViewModel.RefreshRegions)] = [
        ("batteryDetails", .batteryDetails),
        ("wifiDetails", .wifiDetails),
        ("wiredDetailsAndNetwork", .wiredDetailsAndNetwork),
        ("bluetooth", .bluetooth),
        ("all", .all),
        ("volume", .volume),
        ("localIP", .localIP),
        ("audioInput", .audioInput),
        ("inputSource", .inputSource),
        ("vpn", .vpn),
    ]

    @Test func everyRegionHasANonZeroBit() {
        for entry in Self.regions {
            #expect(entry.region.rawValue != 0, "\(entry.name) collapsed to the empty set")
        }
    }

    @Test func regionsDoNotOverlap() {
        for (index, entry) in Self.regions.enumerated() {
            let others = Self.regions.enumerated().filter { $0.offset != index }
            for other in others {
                #expect(
                    !entry.region.contains(other.element.region),
                    "\(entry.name) contains \(other.element.name)"
                )
                #expect(
                    !other.element.region.contains(entry.region),
                    "\(other.element.name) contains \(entry.name)"
                )
            }
        }
    }

    @Test func anEmptyMaskContainsNoRegion() {
        let empty = StatusPanelViewModel.RefreshRegions([])
        for entry in Self.regions {
            #expect(!empty.contains(entry.region), "empty mask contains \(entry.name)")
        }
    }
}
