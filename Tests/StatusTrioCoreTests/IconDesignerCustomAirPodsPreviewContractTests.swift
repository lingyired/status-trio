import XCTest
@testable import StatusTrioCore

final class IconDesignerCustomAirPodsPreviewContractTests: XCTestCase {
    func testCustomSampleIsTransientAndUsesTheSameResolutionForSceneAndExplanation() throws {
        let root = projectRoot
        let sampleSource = try source("Sources/StatusTrioCore/Presentation/Icon/Preview/CustomAirPodsPreviewSample.swift", root: root)
        let cardSource = try source("Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift", root: root)
        let designerSource = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerView.swift", root: root)

        XCTAssertFalse(sampleSource.contains("SettingsStore"))
        XCTAssertFalse(sampleSource.contains("SystemStatusStore"))
        let sessionSource = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerPreviewSession.swift", root: root)
        let controllerSource = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconPreviewDataWindowController.swift", root: root)
        XCTAssertTrue(designerSource.contains("@ObservedObject var previewSession: IconDesignerPreviewSession"))
        XCTAssertTrue(designerSource.contains("previewSession.samples.airPods"))
        XCTAssertTrue(controllerSource.contains("self.previewSession = previewSession"))
        XCTAssertTrue(sessionSource.contains("@Published private(set) var samples"))
        XCTAssertFalse(sessionSource.contains("SettingsStore"))
        XCTAssertFalse(sessionSource.contains("SystemStatusStore"))
        XCTAssertTrue(cardSource.contains("customAirPodsSample: customAirPodsSample"))
        XCTAssertTrue(cardSource.contains("if scenario == .airPodsCustom"))
        XCTAssertTrue(cardSource.contains("return designerResolution"))
        XCTAssertTrue(cardSource.contains("for: designerResolution.trace"))
    }

    func testDesignerSelectionPulseStaysPreviewOnlyAndExplicitGuideHighlightRemains() throws {
        let previewSource = try source("Sources/StatusTrioCore/UI/IconPreviewComponents.swift", root: projectRoot)
        let highlightSource = try source("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerSelectionPulseOverlay.swift", root: projectRoot)
        let statusHighlight = try XCTUnwrap(
            previewSource.range(of: "struct StatusIconPartHighlight: View")
        )
        let statusHighlightSource = String(previewSource[statusHighlight.lowerBound...])

        XCTAssertTrue(previewSource.contains("if onSelectSlot != nil, let selectedSlot {"),
                      "Only the interactive designer preview may show the selected-slot overlay.")
        XCTAssertTrue(previewSource.contains("if let part = highlightedPart {"),
                      "The icon guide must retain its explicitly requested highlight.")
        XCTAssertTrue(statusHighlightSource.contains("var tint: Color = .accentColor"),
                      "Existing guide callers must retain their system accent appearance by default.")
        XCTAssertTrue(highlightSource.contains("tint: .blue"),
                      "Designer selection feedback uses a fixed blue independent of system accent color.")
        XCTAssertTrue(highlightSource.contains("IconDesignerSelectionHighlight.part(for: slot)"))
        XCTAssertTrue(highlightSource.contains(".task(id: taskKey)"))
        XCTAssertTrue(previewSource.contains(".accessibilityAddTraits(selectedSlot == region.slot ? .isSelected : [])"))
    }

    @MainActor
    func testSelectionDoesNotChangeResolvedRasterScene() {
        let status = IconGuideView.example
        let outerRingSelection = MenuBarPreviewBar(
            status: status,
            selectedSlot: .outerRing,
            onSelectSlot: { _ in }
        ) {}
        let centerSelection = MenuBarPreviewBar(
            status: status,
            selectedSlot: .center,
            onSelectSlot: { _ in }
        ) {}

        XCTAssertEqual(outerRingSelection.scene, centerSelection.scene)
    }

    func testBothRequestedLocalesContainTheExactCustomAirPodsCopy() throws {
        let root = projectRoot
        let english = try source("Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings", root: root)
        let chinese = try source("Sources/StatusTrioCore/Resources/zh-Hans.lproj/Localizable.strings", root: root)

        let expectedCopy: [(String, String, String)] = [
            ("icon.preview.scenario.airPodsCustom", "Custom AirPods battery", "自定义 AirPods 电量"),
            ("icon.designer.airPods.test.title", "AirPods test battery", "AirPods 测试电量"),
            ("icon.designer.airPods.test.simulatedData", "Simulated data · Settings preview only; menu bar and Dock remain live.", "模拟数据 · 仅影响设置预览，菜单栏与 Dock 保持实时状态。"),
            ("icon.designer.airPods.test.leftAvailable", "Left ear battery available", "左耳电量可用"),
            ("icon.designer.airPods.test.rightAvailable", "Right ear battery available", "右耳电量可用"),
            ("icon.designer.airPods.test.leftBattery", "Left ear battery", "左耳电量"),
            ("icon.designer.airPods.test.rightBattery", "Right ear battery", "右耳电量"),
            ("icon.designer.airPods.test.both", "Both ears", "双耳"),
            ("icon.designer.airPods.test.leftOnly", "Left only", "仅左耳"),
            ("icon.designer.airPods.test.rightOnly", "Right only", "仅右耳"),
            ("icon.designer.airPods.test.unavailable", "No battery data", "无可用电量")
        ]
        for (key, enValue, zhValue) in expectedCopy {
            XCTAssertTrue(english.contains("\"\(key)\" = \"\(enValue)\";"), "Missing English copy for \(key)")
            XCTAssertTrue(chinese.contains("\"\(key)\" = \"\(zhValue)\";"), "Missing Simplified Chinese copy for \(key)")
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
