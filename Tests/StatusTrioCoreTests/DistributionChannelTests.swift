import XCTest
@testable import StatusTrioCore

final class DistributionChannelTests: XCTestCase {
    func testProductionIdentitiesStayDistinct() {
        XCTAssertEqual(
            DistributionChannel.direct.productionBundleIdentifier,
            "com.lingsmbp.StatusTrio"
        )
        XCTAssertEqual(
            DistributionChannel.appStore.productionBundleIdentifier,
            "com.lingsmbp.StatusTrio.AppStore"
        )
        XCTAssertNotEqual(
            DistributionChannel.direct.productionBundleIdentifier,
            DistributionChannel.appStore.productionBundleIdentifier
        )
    }

    func testDefaultBuildRemainsDirect() {
        #if STATUS_TRIO_APP_STORE
        XCTAssertEqual(DistributionChannel.current, .appStore)
        #else
        XCTAssertEqual(DistributionChannel.current, .direct)
        #endif
    }
}
