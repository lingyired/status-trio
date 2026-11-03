import Foundation
import XCTest
@testable import StatusTrioCore

/// Pins the settings plumbing for the user-selectable panel background
/// (issue #233): default derivation, persistence, and the Reduce Transparency
/// override.
@MainActor
final class PanelBackgroundStyleTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "PanelBackgroundStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return defaults
    }

    func testDefaultFollowsSystemAvailability() throws {
        let settings = SettingsStore(defaults: try makeDefaults())

        XCTAssertEqual(settings.panelBackgroundStyle, PanelBackgroundStyle.systemDefault)
        XCTAssertEqual(
            PanelBackgroundStyle.systemDefault,
            PanelBackgroundStyle.isLiquidGlassAvailable ? .liquidGlass : .classicMaterial
        )
    }

    func testPersistedValueRoundTrips() throws {
        let defaults = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)

        settings.panelBackgroundStyle = .solid

        XCTAssertEqual(
            defaults.string(forKey: SettingsStore.panelBackgroundStyleDefaultsKey),
            PanelBackgroundStyle.solid.rawValue
        )
        XCTAssertEqual(SettingsStore(defaults: defaults).panelBackgroundStyle, .solid)
    }

    func testReduceTransparencyForcesSolid() {
        XCTAssertEqual(
            PanelBackgroundStyle.renderStyle(for: .liquidGlass, reduceTransparency: true),
            .solid
        )
        XCTAssertEqual(
            PanelBackgroundStyle.renderStyle(for: .classicMaterial, reduceTransparency: true),
            .solid
        )
        XCTAssertEqual(
            PanelBackgroundStyle.renderStyle(for: .solid, reduceTransparency: true),
            .solid
        )
    }

    func testRenderStyleResolvesUnavailableLiquidGlass() {
        let expected: PanelBackgroundStyle = PanelBackgroundStyle.isLiquidGlassAvailable
            ? .liquidGlass
            : .classicMaterial
        XCTAssertEqual(
            PanelBackgroundStyle.renderStyle(for: .liquidGlass, reduceTransparency: false),
            expected
        )
        XCTAssertEqual(PanelBackgroundStyle.resolved(.liquidGlass), expected)
    }

    func testAvailableStylesHideLiquidGlassWhenUnsupported() {
        let styles = PanelBackgroundStyle.availableStyles
        if PanelBackgroundStyle.isLiquidGlassAvailable {
            XCTAssertEqual(styles, [.liquidGlass, .classicMaterial, .solid])
        } else {
            XCTAssertEqual(styles, [.classicMaterial, .solid])
        }
    }
}
