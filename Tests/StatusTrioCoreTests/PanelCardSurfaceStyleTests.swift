import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Pins the card-surface decision that replaced "look only at ColorScheme"
/// (#296): the panel background picks the strategy, Reduce Transparency forces
/// the opaque surface, and the environment default keeps the tuned Liquid Glass
/// wash for any subtree that never injects a value.
final class PanelCardSurfaceStyleTests: XCTestCase {
    func testBackgroundStyleMapsToCardStrategy() {
        XCTAssertEqual(PanelCardSurfaceStyle.resolve(.liquidGlass), .glass)
        XCTAssertEqual(PanelCardSurfaceStyle.resolve(.classicMaterial), .material)
        XCTAssertEqual(PanelCardSurfaceStyle.resolve(.solid), .solid)
    }

    func testReduceTransparencyForcesOpaqueCardSurface() {
        for style in PanelBackgroundStyle.allCases {
            let rendered = PanelBackgroundStyle.renderStyle(for: style, reduceTransparency: true)
            XCTAssertEqual(rendered, .solid, "\(style) renders solid under Reduce Transparency")
            XCTAssertEqual(PanelCardSurfaceStyle.resolve(rendered), .solid,
                           "\(style) must use the opaque card surface under Reduce Transparency")
        }
    }

    func testLiquidGlassFallsBackOnOlderSystems() {
        let rendered = PanelBackgroundStyle.renderStyle(for: .liquidGlass, reduceTransparency: false)
        let expectGlass = PanelBackgroundStyle.isLiquidGlassAvailable
        XCTAssertEqual(rendered, expectGlass ? .liquidGlass : .classicMaterial)
        XCTAssertEqual(PanelCardSurfaceStyle.resolve(rendered), expectGlass ? .glass : .material,
                       "an unavailable Liquid Glass style must degrade to the material card")
    }

    func testEnvironmentDefaultKeepsTheTunedGlassWash() {
        // Previews and the existing rendering tests never inject a value; they
        // must keep the exact wash they were written against.
        XCTAssertEqual(EnvironmentValues().panelCardSurfaceStyle, .glass)
    }

    func testClassicMaterialStaysMaterial() {
        XCTAssertEqual(
            PanelCardSurfaceStyle.resolve(
                PanelBackgroundStyle.renderStyle(for: .classicMaterial, reduceTransparency: false)
            ),
            .material
        )
    }
}
