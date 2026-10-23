import AppKit
import ImageIO
import XCTest
@testable import StatusTrioCore

final class IconImageRasterizerSelectionTests: XCTestCase {
    func testLogicalPointSizeIsDerivedFromDPI() {
        let properties = [
            kCGImagePropertyPixelWidth: 1024,
            kCGImagePropertyPixelHeight: 512,
            kCGImagePropertyDPIWidth: 144,
            kCGImagePropertyDPIHeight: 144
        ] as [CFString: Any]

        XCTAssertEqual(
            IconImageRasterizer.logicalPointSize(
                properties: properties,
                imageWidth: 512,
                imageHeight: 256
            ),
            CGSize(width: 512, height: 256)
        )
    }
}
