import AppKit
import Combine
import Testing
@testable import StatusTrioCore

@MainActor
struct BatteryStatusColorsTests {
    @Test func storageIsLosslessAndInvalidValuesFallBackToSystem() {
        for selection in [BatteryStatusColorSelection.system, .preset(.sky), .custom(.init(hue: 0.123456789, saturation: 0.72, brightness: 0.63))] {
            #expect(BatteryStatusColorSelection(storageValue: selection.storageValue) == selection)
        }
        for invalid in ["", "preset:unknown", "custom:nan,1,1", "custom:0,1", "wrong"] {
            #expect(BatteryStatusColorSelection(storageValue: invalid) == .system)
        }
    }

    @Test func customReferenceFloorAcrossSampledHSBExtremes() {
        for hue in stride(from: 0.0, through: 1.0, by: 0.125) {
            for saturation in [0.0, 0.5, 1.0] {
                for brightness in [0.0, 0.01, 0.22, 0.5, 0.78, 0.99, 1.0] {
                    let selection = BatteryStatusColorSelection.custom(.init(hue: hue, saturation: saturation, brightness: brightness))
                    let light = BatteryStatusColorResolver.resolution(for: .charging, selection: selection, darkAppearance: false)
                    let dark = BatteryStatusColorResolver.resolution(for: .charging, selection: selection, darkAppearance: true)
                    #expect(light.referenceContrast >= BatteryStatusColorResolver.minimumReferenceContrast)
                    #expect(light == dark)
                    #expect(light.color.alpha == 1)
                }
            }
        }
    }

    @Test func visibleCustomRemainsThePickedColorAndPresetsAdapt() {
        let components = BatteryStatusColorComponents(hue: 0.85, saturation: 0.7, brightness: 0.6)
        let result = BatteryStatusColorResolver.resolution(for: .critical, selection: .custom(components), darkAppearance: false)
        #expect(!result.wasAdjusted)
        #expect(result.color == BatteryStatusColorResolver.color(from: components))
        for preset in BatteryStatusColorPreset.allCases {
            #expect(BatteryStatusColorResolver.presetColor(preset, darkAppearance: false) != BatteryStatusColorResolver.presetColor(preset, darkAppearance: true))
        }
    }

    @Test func settingsPersistAndPublishDeliveredSelectionBeforeStoreChanges() throws {
        let suite = "BatteryStatusColorsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.batteryStatusColors == .standard)
        var delivered: [BatteryStatusColors] = []
        let subscription = settings.iconAppearancePublisher.sink { delivered.append($0.batteryOptions.batteryStatusColors) }
        defer { subscription.cancel() }
        for role in BatteryStatusColorRole.allCases {
            settings.batteryStatusColors.setSelection(.preset(.rose), for: role)
            #expect(delivered.last == settings.batteryStatusColors)
        }
        #expect(SettingsStore(defaults: defaults).batteryStatusColors == settings.batteryStatusColors)
        settings.batteryStatusColors = .standard
        #expect(SettingsStore(defaults: defaults).batteryStatusColors == .standard)
    }

    @Test func sceneCopiesAndBothRenderKeysKeepColorsAndMonochromeIgnoresThem() throws {
        let colors = BatteryStatusColors(charging: .preset(.lavender), lowPower: .preset(.sky), critical: .preset(.rose))
        let scene = makeScene(colors: colors)
        let stripped = scene.withChargingEffectEnabled(false)
        #expect(stripped.statusColors == colors)
        let baseline = makeScene(colors: .standard)
        let key = DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 128)
        let other = DockIconRenderKey(scene: baseline, backgroundStyle: .dark, pixelLength: 128)
        #expect(key != other)
        #expect(Set([key, other]).count == 2)
        #expect(StatusBarRenderKey(scene: scene, iconSize: 20, backingScale: 2, appearanceName: "dark", phase: nil) != StatusBarRenderKey(scene: baseline, iconSize: 20, backingScale: 2, appearanceName: "dark", phase: nil))
        for effect in [true, false] {
            let custom = makeScene(colors: colors, usesColors: false, effect: effect)
            let system = makeScene(colors: .standard, usesColors: false, effect: effect)
            #expect(custom == system)
            #expect(custom.chromaticRegions == system.chromaticRegions)
        }
        #expect(IconGuideView.demoBatteryOptions(configured: BatteryIconOptions(batteryStatusColors: colors)).batteryStatusColors == colors)
    }

    @Test func customConfigurationChangesBothSurfacePixelsWithoutChangingRegions() throws {
        let system = makeScene(colors: .standard).withChargingEffectEnabled(false)
        let custom = makeScene(colors: BatteryStatusColors(charging: .preset(.rose))).withChargingEffectEnabled(false)
        #expect(system.templateRegions == custom.templateRegions)
        #expect(system.chromaticRegions == custom.chromaticRegions)
        let environment = StatusIconRenderer.renderEnvironment(size: 64, scale: 2, appearance: NSAppearance(named: .darkAqua))
        let first = try #require(StatusIconRenderer.render(scene: system, environment: environment))
        let second = try #require(StatusIconRenderer.render(scene: custom, environment: environment))
        #expect(try PixelBuffer(image: first).bytes != PixelBuffer(image: second).bytes)
        let dockFirst = try #require(DockIconRenderer.image(scene: system, backgroundStyle: .dark, pixelLength: 128))
        let dockSecond = try #require(DockIconRenderer.image(scene: custom, backgroundStyle: .dark, pixelLength: 128))
        #expect(dockFirst.tiffRepresentation != dockSecond.tiffRepresentation)
    }

    private func makeScene(colors: BatteryStatusColors, usesColors: Bool = true, effect: Bool = true) -> IconSceneState {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: true, isLowPowerMode: false, isConnectedToPower: true),
            wifi: .placeholder, volume: .placeholder
        )
        return IconPresentationMapper.scene(
            inputs: .init(snapshot: snapshot, audioIcon: nil),
            configuration: .init(battery: BatteryIconOptions(showsChargingEffect: effect, usesStatusColors: usesColors, batteryStatusColors: colors), connection: .standard, volume: .standard, bluetooth: .standard)
        )
    }
}
