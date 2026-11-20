import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconLiveDemandWiringTests: XCTestCase {
    private let binding = IconContentBinding(pluginID: "test.external", presentationID: "latency")

    func testBothHiddenSurfacesReleaseEverySubscription() {
        let demand = IconPresentationDemand(subscribedBindings: [binding])
        XCTAssertEqual(
            IconLiveDemandPolicy.subscribedBindings(
                demand: demand, showsMenuBar: false, showsDock: false),
            []
        )
        XCTAssertEqual(
            IconLiveDemandPolicy.subscribedBindings(
                demand: demand, showsMenuBar: true, showsDock: false),
            [binding]
        )
        XCTAssertEqual(
            IconLiveDemandPolicy.subscribedBindings(
                demand: demand, showsMenuBar: false, showsDock: true),
            [binding]
        )
    }

    func testWiringFollowsPlacementAndRestartsAfterStop() {
        let demands = CurrentValueSubject<IconPresentationDemand, Never>(
            IconPresentationDemand(subscribedBindings: [binding]))
        let placements = CurrentValueSubject<AppIconPlacement, Never>(.both)
        var applied: [Set<IconContentBinding>] = []
        let wiring = IconLiveDemandWiring(placement: .both) { applied.append($0) }

        wiring.start(
            demands: demands.eraseToAnyPublisher(),
            placements: placements.eraseToAnyPublisher()
        )
        XCTAssertEqual(applied.last, [binding])
        XCTAssertEqual(wiring.activeSubscriptionCount, 1)

        wiring.stop()
        XCTAssertEqual(wiring.activeSubscriptionCount, 0)

        // Changes made while stopped are not lost: restart replays the latest
        // demand and placement to the apply closure.
        demands.send(IconPresentationDemand(subscribedBindings: [binding]))
        placements.send(.dock)
        wiring.start(
            demands: demands.eraseToAnyPublisher(),
            placements: placements.eraseToAnyPublisher()
        )
        XCTAssertEqual(applied.last, [binding])
        XCTAssertEqual(wiring.activeSubscriptionCount, 1)
        wiring.stop()
    }

    func testDemandChangeWithoutPlacementChangeReconciles() {
        let demands = PassthroughSubject<IconPresentationDemand, Never>()
        let placements = CurrentValueSubject<AppIconPlacement, Never>(.menuBar)
        var applied: [Set<IconContentBinding>] = []
        let wiring = IconLiveDemandWiring(placement: .menuBar) { applied.append($0) }
        wiring.start(
            demands: demands.eraseToAnyPublisher(),
            placements: placements.eraseToAnyPublisher()
        )
        XCTAssertEqual(applied, [])

        demands.send(IconPresentationDemand(subscribedBindings: [binding]))
        XCTAssertEqual(applied.last, [binding])

        demands.send(IconPresentationDemand())
        XCTAssertEqual(applied.last, [])
        wiring.stop()
    }
}
