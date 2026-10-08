import XCTest
@testable import StatusTrioCore

@MainActor
final class IconPreviewSceneTests: XCTestCase {
    func testPreviewUsesCanonicalMapping() {
        let snapshot = PresentationFixtures.snapshot()

        XCTAssertEqual(
            IconPreviewScene.make(snapshot: snapshot, configuration: .standard),
            IconPresentationMapper.scene(
                inputs: IconPresentationResourceResolver.inputs(snapshot: snapshot),
                configuration: .standard
            )
        )
    }
}
