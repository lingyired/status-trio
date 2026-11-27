import Foundation
import Testing
@testable import StatusTrioCore

struct PopupHorizontalScrollTests {
    @Test(arguments: [true, false])
    func dominantAxisAdjustsOnlyOnce(_ precise: Bool) throws {
        // With natural scrolling on, rightward physical scrolling is reported
        // as positive X and upward physical scrolling as positive Y.
        let packets: [(Double, Double, Double)] = [
            (-4, 0, -4), (4, 0, 4), (0, 4, 4),
            (-4, -2, -4), (2, 4, 4), (-4, -4, -4)
        ]
        for (x, y, expected) in packets {
            var adjustment = PopupVolumeScrollAdjustment()
            let raw = adjustment.volumeDelta(
                deltaX: x, deltaY: y, isPrecise: precise,
                isDirectionInverted: true, usesNaturalScrolling: false,
                wheelStep: 0.05
            )
            let value = try #require(raw)
            let magnitude = precise ? abs(expected) * 0.002 : 0.05
            #expect(abs(value - (expected > 0 ? magnitude : -magnitude)) < 0.000_001)
        }
    }

    @Test(arguments: [true, false], [(false, false), (false, true), (true, false), (true, true)])
    func horizontalDirectionAlwaysFollowsPhysicalDirection(
        _ precise: Bool, _ preferences: (Bool, Bool)
    ) throws {
        let (inverted, natural) = preferences
        for physicalRight in [true, false] {
            var adjustment = PopupVolumeScrollAdjustment()
            // AppKit's horizontal delta is positive for a rightward gesture
            // with natural scrolling on, and negative with it off.
            let deltaX = physicalRight
                ? (inverted ? 4.0 : -4.0)
                : (inverted ? -4.0 : 4.0)
            let raw = adjustment.volumeDelta(
                deltaX: deltaX, deltaY: 0, isPrecise: precise,
                isDirectionInverted: inverted, usesNaturalScrolling: natural
            )
            let value = try #require(raw)
            // Horizontal scrolling is physical: right always raises and left
            // always lowers, regardless of either natural-scrolling switch.
            let magnitude = precise ? 0.008 : 0.10
            #expect(abs(value - (physicalRight ? magnitude : -magnitude)) < 0.000_001)
        }
    }

    @Test(arguments: [true, false], [true, false])
    func verticalDirectionKeepsNaturalScrollingPreferenceHandling(
        _ inverted: Bool, _ natural: Bool
    ) throws {
        for physicalUp in [true, false] {
            var adjustment = PopupVolumeScrollAdjustment()
            let deltaY = physicalUp
                ? (inverted ? -4.0 : 4.0)
                : (inverted ? 4.0 : -4.0)
            let raw = adjustment.volumeDelta(
                deltaX: 0, deltaY: deltaY, isPrecise: true,
                isDirectionInverted: inverted, usesNaturalScrolling: natural
            )
            let value = try #require(raw)
            // Vertical keeps the pre-existing mapping: the app-level natural
            // scrolling preference decides, otherwise the system sign decides.
            let increases = natural ? physicalUp : deltaY > 0
            #expect(abs(value - (increases ? 0.008 : -0.008)) < 0.000_001)
        }
    }

    @MainActor
    @Test func allSlidersShareHorizontalStepAndAccumulation() throws {
        let name = "PopupHorizontalScrollTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        settings.popupScrollWheelStepPercent = 5
        for natural in [false, true] {
            settings.popupVolumeNaturalScrolling = natural
            for target in [PanelLevelScrollTarget.volume, .audioInput, .brightness(displayID: "display")] {
                var adjustment = PopupVolumeScrollAdjustment()
                let partial = adjustment.levelDelta(
                    deltaX: 0.5, deltaY: 0, isPrecise: false,
                    isDirectionInverted: true, timestamp: 1, target: target, settings: settings
                )
                #expect(partial == nil)
                let raw = adjustment.levelDelta(
                    deltaX: 0.5, deltaY: 0, isPrecise: false,
                    isDirectionInverted: true, timestamp: 1.1, target: target, settings: settings
                )
                let value = try #require(raw)
                #expect(abs(value - 0.05) < 0.000_001)
            }
        }
    }
}
