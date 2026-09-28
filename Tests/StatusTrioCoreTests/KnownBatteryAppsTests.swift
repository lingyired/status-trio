import XCTest
@testable import StatusTrioCore

final class KnownBatteryAppsTests: XCTestCase {
    func testKnownAppsUseVerifiedNamesIdentifiersAndNoUnverifiedDeepLinks() {
        XCTAssertEqual(KnownBatteryApps.definition(for: .alDente).displayName, "AlDente")
        XCTAssertEqual(
            KnownBatteryApps.definition(for: .alDente).bundleIdentifiers,
            ["com.apphousekitchen.aldente-pro"]
        )
        XCTAssertNil(KnownBatteryApps.definition(for: .alDente).deepLink)

        XCTAssertEqual(KnownBatteryApps.definition(for: .batFi).displayName, "BatFi")
        XCTAssertEqual(
            KnownBatteryApps.definition(for: .batFi).bundleIdentifiers,
            ["software.micropixels.BatFi"]
        )
        XCTAssertNil(KnownBatteryApps.definition(for: .batFi).deepLink)
    }

    func testEveryKnownAppIdentifierHasExactlyOneDefinition() {
        let definitionIDs = KnownBatteryApps.all.map(\.id)

        XCTAssertEqual(Set(definitionIDs), Set(KnownBatteryAppID.allCases))
        XCTAssertEqual(definitionIDs.count, Set(definitionIDs).count)
    }
}
