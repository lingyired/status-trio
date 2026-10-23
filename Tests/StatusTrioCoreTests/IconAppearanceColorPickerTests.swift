import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconAppearanceColorPickerTests: XCTestCase {
    func testHostedFixedAndSemanticAppearanceEditorsRenderOneNativeColorWell() throws {
        let semanticColors: [IconSemanticColorRole: IconRGBA] = [
            .primary: IconRGBA(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.7),
            .critical: IconRGBA(red: 0.9, green: 0.1, blue: 0.2, alpha: 0.6)
        ]
        let colorStyles: [SlotColorStyle] = [
            .fixed(IconRGBA(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.45)),
            .semanticOverrides(semanticColors)
        ]

        for colorStyle in colorStyles {
            let hosted = try makeHostedEditor(colorStyle: colorStyle)
            defer { TestUserDefaults.removeSuite(named: hosted.suiteName) }
            settle(hosted.view)

            let nativeViews = descendants(of: hosted.view)
            let colorWells = nativeViews.compactMap { $0 as? NSColorWell }

            XCTAssertEqual(colorWells.count, 1, "Fixed and semantic styles should each render one native color well.")
            let well = try XCTUnwrap(colorWells.first)
            XCTAssertLessThanOrEqual(well.frame.width, 60, "The swatch must not expand to fill the control column.")
            XCTAssertLessThanOrEqual(well.frame.height, 32, "Long row descriptions must not stretch the swatch vertically.")
        }
    }

    func testNativeColorWellEnablesAlphaAndPreservesItsNativeColor() throws {
        let previousShowsAlpha = NSColorPanel.shared.showsAlpha
        defer { NSColorPanel.shared.showsAlpha = previousShowsAlpha }
        let expected = IconRGBA(red: 0.24, green: 0.48, blue: 0.72, alpha: 0.37)
        let hosted = try makeHostedEditor(colorStyle: .fixed(expected))
        defer { TestUserDefaults.removeSuite(named: hosted.suiteName) }
        settle(hosted.view)

        let wells = descendants(of: hosted.view).compactMap { $0 as? NSColorWell }
        let well = try XCTUnwrap(wells.first)
        let actual = IconAppearanceColorConversion.iconRGBA(from: Color(nsColor: well.color))

        XCTAssertTrue(NSColorPanel.shared.showsAlpha, "The native macOS color panel must expose alpha controls.")
        XCTAssertEqual(actual.red, expected.red, accuracy: 0.002)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.002)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.002)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: 0.002)
    }

    func testNativeColorWellUsesLocalizedAccessibleLabelAndKeepsOnlyScaleSlider() throws {
        let source = try String(contentsOf: appearanceEditorURL, encoding: .utf8)
        let scaleControl = try String(contentsOf: scaleControlURL, encoding: .utf8)

        XCTAssertTrue(source.contains("IconDesignerColorWell("), "Appearance colors should use the native NSColorWell wrapper.")
        XCTAssertFalse(source.contains("componentSlider("), "RGBA channels should not be edited with separate sliders.")
        XCTAssertFalse(source.contains("iconDesignerControlRed"))
        XCTAssertFalse(source.contains("iconDesignerControlGreen"))
        XCTAssertFalse(source.contains("iconDesignerControlBlue"))
        XCTAssertFalse(source.contains("iconDesignerControlOpacity"))
        XCTAssertEqual(source.components(separatedBy: "IconDesignerScaleControl(").count - 1, 1,
                       "The appearance editor should declare one scale control.")
        XCTAssertEqual(scaleControl.components(separatedBy: "Slider(").count - 1, 1,
                       "The shared scale control should own exactly one native slider.")
        XCTAssertTrue(source.contains(".accessibilityLabel(colorPickerLabel)"))
        XCTAssertTrue(source.contains("guard slot == .center, styleBinding.wrappedValue == .semantic else { return nil }"))
    }

    func testColorConversionRoundTripsSRGBComponentsAndAlpha() {
        let original = IconRGBA(red: 0.17, green: 0.43, blue: 0.82, alpha: 0.36)

        let converted = IconAppearanceColorConversion.iconRGBA(
            from: IconAppearanceColorConversion.color(from: original)
        )

        XCTAssertEqual(converted.red, original.red, accuracy: 0.002)
        XCTAssertEqual(converted.green, original.green, accuracy: 0.002)
        XCTAssertEqual(converted.blue, original.blue, accuracy: 0.002)
        XCTAssertEqual(converted.alpha, original.alpha, accuracy: 0.002)
    }

    func testColorConversionNormalizesDisplayP3IntoSRGBWithoutLosingAlpha() throws {
        let displayP3 = NSColor(displayP3Red: 0.72, green: 0.24, blue: 0.48, alpha: 0.29)
        let expected = try XCTUnwrap(displayP3.usingColorSpace(.sRGB))

        let converted = IconAppearanceColorConversion.iconRGBA(from: Color(nsColor: displayP3))

        XCTAssertEqual(converted.red, Double(expected.redComponent), accuracy: 0.002)
        XCTAssertEqual(converted.green, Double(expected.greenComponent), accuracy: 0.002)
        XCTAssertEqual(converted.blue, Double(expected.blueComponent), accuracy: 0.002)
        XCTAssertEqual(converted.alpha, 0.29, accuracy: 0.002)
    }

    func testEditingOneSemanticRolePreservesOtherRolesAndPersistsThroughSettingsStore() throws {
        let suiteName = "StatusTrioCoreTests.IconAppearanceColorPicker.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }

        let originalColors: [IconSemanticColorRole: IconRGBA] = [
            .primary: IconRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            .critical: IconRGBA(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.5),
            .inactive: IconRGBA(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.6)
        ]
        var configuration = IconConfigurationV1.classic
        configuration.appearance.outerRing.color = .semanticOverrides(originalColors)
        defaults.set(try IconConfigurationCodec.encode(configuration), forKey: SettingsStore.iconConfigurationDefaultsKey)
        let store = SettingsStore(defaults: defaults)
        let editedColor = IconRGBA(red: 0.25, green: 0.55, blue: 0.75, alpha: 0.33)

        store.updateIconConfiguration { configuration in
            IconAppearanceColorEditing.setColor(
                editedColor,
                role: .powered,
                slot: .outerRing,
                in: &configuration
            )
        }

        guard case let .semanticOverrides(updatedColors) = store.iconConfiguration.appearance.outerRing.color else {
            return XCTFail("Editing a semantic role must preserve semantic color style.")
        }
        XCTAssertEqual(updatedColors[.powered], editedColor)
        XCTAssertEqual(updatedColors[.primary], originalColors[.primary])
        XCTAssertEqual(updatedColors[.critical], originalColors[.critical])
        XCTAssertEqual(updatedColors[.inactive], originalColors[.inactive])

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.iconConfiguration.appearance.outerRing.color, .semanticOverrides(updatedColors))
    }

    func testFixedColorEditsStayScopedToEachSlotAndPersistThroughSettingsStore() throws {
        let suiteName = "StatusTrioCoreTests.IconAppearanceFixedColorSlots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }

        let initialColors = [
            IconRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            IconRGBA(red: 0.4, green: 0.5, blue: 0.6, alpha: 0.7),
            IconRGBA(red: 0.7, green: 0.8, blue: 0.9, alpha: 1)
        ]
        let editedColors = [
            IconRGBA(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.5),
            IconRGBA(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8),
            IconRGBA(red: 0.8, green: 0.9, blue: 0.1, alpha: 0.2)
        ]
        let slots: [IconSlot] = [.outerRing, .center, .footer]
        var configuration = IconConfigurationV1.classic
        for (slot, color) in zip(slots, initialColors) {
            setColorStyle(.fixed(color), for: slot, in: &configuration)
        }
        defaults.set(try IconConfigurationCodec.encode(configuration), forKey: SettingsStore.iconConfigurationDefaultsKey)
        let store = SettingsStore(defaults: defaults)

        for (slot, color) in zip(slots, editedColors) {
            store.updateIconConfiguration { configuration in
                IconAppearanceColorEditing.setColor(color, role: .primary, slot: slot, in: &configuration)
            }
        }

        for (slot, expected) in zip(slots, editedColors) {
            guard case let .fixed(actual) = colorStyle(for: slot, in: store.iconConfiguration) else {
                return XCTFail("Editing a fixed color must keep that slot fixed.")
            }
            XCTAssertEqual(actual, expected, "An edit to one slot must not overwrite another slot's color.")
        }

        let reloaded = SettingsStore(defaults: defaults)
        for (slot, expected) in zip(slots, editedColors) {
            guard case let .fixed(actual) = colorStyle(for: slot, in: reloaded.iconConfiguration) else {
                return XCTFail("Each fixed slot color should persist after reload.")
            }
            XCTAssertEqual(actual, expected)
        }
    }

    private func setColorStyle(_ style: SlotColorStyle, for slot: IconSlot, in configuration: inout IconConfigurationV1) {
        switch slot {
        case .outerRing: configuration.appearance.outerRing.color = style
        case .center: configuration.appearance.center.color = style
        case .footer: configuration.appearance.footer.color = style
        }
    }

    private func colorStyle(for slot: IconSlot, in configuration: IconConfigurationV1) -> SlotColorStyle {
        switch slot {
        case .outerRing: configuration.appearance.outerRing.color
        case .center: configuration.appearance.center.color
        case .footer: configuration.appearance.footer.color
        }
    }

    private func makeHostedEditor(colorStyle: SlotColorStyle) throws -> (view: NSHostingView<AnyView>, suiteName: String) {
        let suiteName = "StatusTrioCoreTests.IconAppearanceColorPickerHost.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        var configuration = IconConfigurationV1.classic
        configuration.appearance.outerRing.color = colorStyle
        defaults.set(try IconConfigurationCodec.encode(configuration), forKey: SettingsStore.iconConfigurationDefaultsKey)

        let store = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: [AppLanguage.english.rawValue])
        let editor = IconAppearanceEditor(store: store, slot: .outerRing)
            .environmentObject(localization)
        let view = NSHostingView(rootView: AnyView(editor))
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        return (view, suiteName)
    }

    private func settle(_ view: NSHostingView<AnyView>) {
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
    }

    private func descendants(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants(of:))
    }

    private var scaleControlURL: URL {
        appearanceEditorURL.deletingLastPathComponent().appendingPathComponent("IconDesignerScaleControl.swift")
    }

    private var appearanceEditorURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/IconDesigner/IconAppearanceEditor.swift")
    }
}
