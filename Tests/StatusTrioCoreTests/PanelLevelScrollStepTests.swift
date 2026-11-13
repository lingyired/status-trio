import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct PanelLevelScrollStepTests {
    @Test(arguments: [1.0, 2.5, 5.0, 10.0, 20.0])
    func allSlidersReadTheLiveStepAndKeepTrackpadContinuous(_ percent: Double) throws {
        let name = "PanelLevelScrollStepTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        var adjustment = PopupVolumeScrollAdjustment()
        let targets: [PanelLevelScrollTarget] = [.volume, .brightness(displayID: "external"), .audioInput]
        // Change after creating the adjustment: settings take effect immediately.
        store.popupScrollWheelStepPercent = percent
        for target in targets {
            for lines in [1.0, 3.0, -1.0, -3.0] {
                let result = adjustment.levelDelta(
                    deltaY: lines, isPrecise: false, isDirectionInverted: false,
                    timestamp: 1, target: target, settings: store
                )
                let value = try #require(result)
                #expect(abs(value - (lines > 0 ? percent / 100 : -percent / 100)) < 0.000_001)
            }
            let result = adjustment.levelDelta(
                deltaY: 2.5, isPrecise: true, isDirectionInverted: false,
                timestamp: 1, target: target, settings: store
            )
            let precise = try #require(result)
            #expect(abs(precise - 0.005) < 0.000_001)
        }
    }

    @Test func differentDisplaysDoNotSharePartialWheelPackets() throws {
        let name = "PanelLevelScrollStepTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        var adjustment = PopupVolumeScrollAdjustment()
        for display in ["first", "second"] {
            let result = adjustment.levelDelta(
                deltaY: 0.5, isPrecise: false, isDirectionInverted: false,
                timestamp: 1, target: .brightness(displayID: display), settings: store
            )
            #expect(result == nil)
        }
    }
}
