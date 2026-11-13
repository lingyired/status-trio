import Foundation
import Testing
@testable import StatusTrioCore

struct PopupHorizontalScrollTests {
    @Test(arguments: [true, false])
    func dominantAxisAdjustsOnlyOnce(_ precise: Bool) throws {
        // Rightward physical scrolling is positive X and upward physical
        // scrolling is positive Y, exactly like the vertical slider.
        let packets: [(Double, Double, Double)] = [
            (-4, 0, -4), (4, 0, 4), (0, 4, 4),
            (-4, -2, -4), (2, 4, 4), (-4, -4, -4)
        ]
        for (x, y, expected) in packets {
            var adjustment = PopupVolumeScrollAdjustment()
            let raw = adjustment.volumeDelta(
                deltaX: x, deltaY: y, isPrecise: precise,
                isDirectionInverted: false, usesNaturalScrolling: false,
                wheelStep: 0.05
            )
            let value = try #require(raw)
            let magnitude = precise ? abs(expected) * 0.002 : 0.05
            #expect(abs(value - (expected > 0 ? magnitude : -magnitude)) < 0.000_001)
        }
    }

    @Test(arguments: [true, false], [(false, false), (false, true), (true, false), (true, true)])
    func horizontalDirectionMirrorsVerticalPreferenceHandling(
        _ precise: Bool, _ preferences: (Bool, Bool)
    ) throws {
        let (inverted, natural) = preferences
        for physicalRight in [true, false] {
            var adjustment = PopupVolumeScrollAdjustment()
            let deltaX = physicalRight
                ? (inverted ? -4.0 : 4.0)
                : (inverted ? 4.0 : -4.0)
            let raw = adjustment.volumeDelta(
                deltaX: deltaX, deltaY: 0, isPrecise: precise,
                isDirectionInverted: inverted, usesNaturalScrolling: natural
            )
            let value = try #require(raw)
            // Natural scrolling follows physical direction; otherwise the
            // system-reported sign decides, exactly like the vertical axis.
            let increases = natural ? physicalRight : deltaX > 0
            let magnitude = precise ? 0.008 : 0.10
            #expect(abs(value - (increases ? magnitude : -magnitude)) < 0.000_001)
        }
    }

    @MainActor
    @Test func allSlidersShareHorizontalStepAndAccumulation() throws {
        let name = "PopupHorizontalScrollTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        settings.popupScrollWheelStepPercent = 5
        for target in [PanelLevelScrollTarget.volume, .audioInput, .brightness(displayID: "display")] {
            var adjustment = PopupVolumeScrollAdjustment()
            let partial = adjustment.levelDelta(
                deltaX: 0.5, deltaY: 0, isPrecise: false,
                isDirectionInverted: false, timestamp: 1, target: target, settings: settings
            )
            #expect(partial == nil)
            let raw = adjustment.levelDelta(
                deltaX: 0.5, deltaY: 0, isPrecise: false,
                isDirectionInverted: false, timestamp: 1.1, target: target, settings: settings
            )
            let value = try #require(raw)
            #expect(abs(value - 0.05) < 0.000_001)
        }
    }
}
