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
