import Foundation
import Testing

@Suite
struct IconBehaviorEditorSourceContractTests {
    @Test
    func outerRingBehaviorControlsFollowTheCurrentlySelectedSource() throws {
        let source = try String(contentsOf: behaviorEditorURL, encoding: .utf8)
        let compactSource = String(source.filter { !$0.isWhitespace })

        #expect(compactSource.contains("IconDesignerEditingModel.source(for:effectiveBehaviorTarget,slot:.outerRing"))
        #expect(compactSource.contains("behaviors(for:.outerRing,source:"))
        #expect(compactSource.contains(".contains(.airPodsBattery)"))
        #expect(compactSource.contains(".contains(.systemBattery)"))
        #expect(!compactSource.contains("requiresAirPodsBattery(in:store.iconConfiguration)"),
                "A configured fallback must not expose controls for the other source.")
    }

    @Test
    func textScaleKeepsItsRangeAndUsesTheFullWidthScaleControl() throws {
        let source = try String(contentsOf: behaviorEditorURL, encoding: .utf8)
        guard FileManager.default.fileExists(atPath: scaleControlURL.path) else {
            #expect(Bool(false), "The shared full-width scale control has not been added")
            return
        }
        let scaleControl = try String(contentsOf: scaleControlURL, encoding: .utf8)

        #expect(source.contains("batteryTextScaleSliderValue(for: rawTextScale)"))
        #expect(source.contains("settingBatteryTextScale(value"))
        #expect(source.contains("range: IconDesignerEditingModel.batteryTextScaleRange"))
        #expect(source.contains("step: 0.05"))
        #expect(source.contains("IconDesignerScaleControl("))
        let textScaleHelper = source.components(separatedBy: "private var batteryTextScaleSlider").dropFirst().first ?? ""
        let outerTextControl = textScaleHelper.components(separatedBy: "private var centerBehavior").first ?? ""
        #expect(!outerTextControl.contains("frame(minWidth: 90, maxWidth: 160)"))
        #expect(scaleControl.contains("Slider(value: $value, in: range, step: step"))
        #expect(scaleControl.contains(".frame(maxWidth: .infinity)"))
    }

    @Test
    func globalNetworkOverrideToggleIsVisibleForEveryCentreSource() throws {
        let source = try String(contentsOf: behaviorEditorURL, encoding: .utf8)
        let compactSource = String(source.filter { !$0.isWhitespace })

        // One global switch, rendered outside any per-source branch so it shows
        // for inputSource, network, battery, Bluetooth, none and automaticLegacy.
        #expect(compactSource.contains("iconDesignerControlNetworkProblemsOverride"))
        #expect(compactSource.contains("centerOverride.networkProblemOverridesPrimary=value"))
        #expect(compactSource.contains("iconDesignerControlNetworkProblemsOverrideHelp"))
        #expect(!compactSource.contains("allowsNetworkProblemOverride"),
                "The override must not be gated to Bluetooth-audio sources any more.")
        #expect(!compactSource.contains("iconDesignerControlNetworkProblemsOverrideBluetooth"),
                "The removed Bluetooth-only label must not survive.")
        #expect(!compactSource.contains("iconDesignerControlPrioritizeNetworkErrors"),
                "The global rule is the sole network-failure control; no legacy Bluetooth priority toggle may remain in the designer.")
    }

    @Test
    func centreBehaviorSwitchNoLongerPlacesTheToggleInsideTheBluetoothBranch() throws {
        let source = try String(contentsOf: behaviorEditorURL, encoding: .utf8)
        let toggleIndex = try #require(source.range(of: "iconDesignerControlNetworkProblemsOverride"))
        let bluetoothBranchIndex = try #require(source.range(of: "private var bluetoothOutputBehavior"))
        // The global toggle sits before the per-source branches resolve, so it is
        // not inside the Bluetooth-only output branch.
        #expect(toggleIndex.lowerBound < bluetoothBranchIndex.lowerBound)
    }

    private var scaleControlURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerScaleControl.swift")
    }

    private var behaviorEditorURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconBehaviorEditor.swift")
    }
}
