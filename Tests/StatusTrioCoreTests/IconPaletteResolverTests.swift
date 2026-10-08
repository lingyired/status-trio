import AppKit
import XCTest
@testable import StatusTrioCore

final class IconPaletteResolverTests: XCTestCase {
    func testAutomaticPreservesSemanticRoleAndFixedColorIsNormalized() {
        let color = IconRGBA(red: 1.4, green: -0.2, blue: 0.5, alpha: 0.7)
        XCTAssertEqual(IconPaletteResolver.resolve(role: .critical, style: .automatic), .critical)
        XCTAssertEqual(
            IconPaletteResolver.resolve(role: .primary, style: .fixed(color)),
            .custom(IconRGBA(red: 1, green: 0, blue: 0.5, alpha: 0.7))
        )
    }

    func testSemanticOverrideFallsBackToTheOriginalRole() {
        let warning = IconRGBA(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        let style = SlotColorStyle.semanticOverrides([.critical: warning])

        XCTAssertEqual(IconPaletteResolver.resolve(role: .critical, style: style), .custom(warning))
        XCTAssertEqual(IconPaletteResolver.resolve(role: .lowPower, style: style), .lowPower)
    }

    func testOnlySlotBeingStyledChangesAndColorParticipatesInSceneIdentity() {
        let red = IconRGBA(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = IconRGBA(red: 0, green: 0, blue: 1, alpha: 1)
        let redScene = IconSceneState(
            outerRing: OuterRingState(segments: [RingSegmentState(progress: 0.5, color: .custom(red))], gap: .closed)
        )
        let blueScene = IconSceneState(
            outerRing: OuterRingState(segments: [RingSegmentState(progress: 0.5, color: .custom(blue))], gap: .closed)
        )
        XCTAssertNotEqual(redScene, blueScene)
        XCTAssertNotEqual(
            DockIconRenderKey(scene: redScene, backgroundStyle: .dark, pixelLength: 96),
            DockIconRenderKey(scene: blueScene, backgroundStyle: .dark, pixelLength: 96)
        )
    }

    func testCompositionAppliesAppearanceIndependentlyFromSourceSelection() throws {
        var configuration = IconConfigurationV1.classic
        let ringColor = IconRGBA(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        configuration.appearance.outerRing.color = .fixed(ringColor)
        configuration.appearance.outerRing.strokeScale = 1.8
        configuration.behaviors.networkCenter.wifiScale = 1.5
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 42, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -54),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Output")
        )
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil), sources: .empty),
            configuration: configuration
        )

        XCTAssertEqual(output.scene.outerRing?.segments.first?.color, .custom(ringColor))
        XCTAssertEqual(try XCTUnwrap(output.scene.outerRing).strokeScale, 1.8, accuracy: 0.0001)
        XCTAssertEqual(output.scene.center?.colorRole, .primary)
        XCTAssertEqual(try XCTUnwrap(output.scene.center?.symbolScaleValue), 1.5)
        XCTAssertEqual(output.scene.footer?.colorRole, .primary)
        XCTAssertEqual(try XCTUnwrap(output.scene.footer?.strokeScaleValue), FooterAppearance.classic.strokeScale, accuracy: 0.0001)
    }

    func testFallbackSelectionRetainsTheSlotsConfiguredAppearance() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        let custom = IconRGBA(red: 0.1, green: 0.8, blue: 0.9, alpha: 1)
        configuration.appearance.center.color = .fixed(custom)
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 52, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -54),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Bluetooth", currentDevice: PresentationFixtures.bluetoothDevice)
        )
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: .symbol(name: "airpods", variableValue: nil, fallback: nil)),
                sources: IconSourceSnapshot(availability: [CenterSource.network.rawValue: .unavailable(.disconnected)])
            ),
            configuration: configuration
        )

        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.scene.center?.colorRole, .custom(custom))
    }

    func testCriticalBatteryRoleWinsOverLowPowerAndChargingBeforePaletteResolution() {
        let battery = BatteryStatus(rawPercentage: 8, isPresent: true, isCharging: true,
                                    isLowPowerMode: true, isConnectedToPower: true)
        let role = StatusMappings.batteryColorRole(battery, criticalThreshold: 20)
        let critical = IconRGBA(red: 0.95, green: 0.1, blue: 0.1, alpha: 1)
        let palette: SlotColorStyle = .semanticOverrides([.critical: critical, .powered: .white])

        XCTAssertEqual(role, .critical)
        XCTAssertEqual(IconPaletteResolver.resolve(role: .critical, style: palette), .custom(critical))
    }

    func testAppearanceConfigurationRoundTripsCustomColorsThroughVersionedCodec() throws {
        var configuration = IconConfigurationV1.classic
        configuration.appearance.outerRing.color = .fixed(IconRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.8))
        configuration.appearance.center.color = .semanticOverrides([.bluetooth: IconRGBA(red: 0, green: 0.4, blue: 1, alpha: 1)])
        XCTAssertEqual(try IconConfigurationCodec.decode(IconConfigurationCodec.encode(configuration)), configuration)
    }

    @MainActor
    func testMenuBarAndDockRastersBothChangeWhenSceneColorChanges() throws {
        let red = IconRGBA(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = IconRGBA(red: 0, green: 0, blue: 1, alpha: 1)
        let scenes = [red, blue].map { color in
            IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.7, color: .custom(color))], gap: .closed
            ))
        }
        let environment = StatusIconRenderEnvironment(
            size: 28, scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let menuBar = try scenes.map { try XCTUnwrap(StatusIconRenderer.render(scene: $0, environment: environment)) }
        let dock = try scenes.map { try XCTUnwrap(DockIconRenderer.image(scene: $0, backgroundStyle: .dark, pixelLength: 96)) }
        XCTAssertNotEqual(try rgbaBytes(menuBar[0]), try rgbaBytes(menuBar[1]))
        XCTAssertNotEqual(try rgbaBytes(dock[0]), try rgbaBytes(dock[1]))
    }

    @MainActor
    func testAutomaticSemanticPaletteAdaptsAcrossLightAndDarkForegrounds() throws {
        let scene = IconSceneState(outerRing: OuterRingState(
            segments: [RingSegmentState(progress: 0.65, color: .lowPower)], gap: .closed
        ))
        let critical = StatusIconRenderer.defaultCriticalColor
        let lightForeground = CGColor(gray: 0, alpha: 1)
        let darkForeground = CGColor(gray: 1, alpha: 1)
        let light = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(size: 28, scale: 2, foreground: lightForeground, criticalColor: critical)
        ))
        let dark = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(size: 28, scale: 2, foreground: darkForeground, criticalColor: critical)
        ))

        XCTAssertNotEqual(try rgbaBytes(light), try rgbaBytes(dark))
    }

    @MainActor
    func testChargingRasterEffectsRespectCustomAlphaForActiveArcAndBolt() throws {
        let environment = StatusIconRenderEnvironment(
            size: 48, scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let phase = ChargingEffectPhase(step: 34, stepsPerCycle: 36, kind: .steady)

        for includesBolt in [false, true] {
            var rendersByAlpha: [Double: ([UInt8], [UInt8])] = [:]
            for alpha in [0.0, 0.4, 1.0] {
                let color = IconRGBA(red: 0.15, green: 0.55, blue: 0.9, alpha: alpha)
                let ring = OuterRingState(
                    segments: [RingSegmentState(progress: 1, color: .custom(color))],
                    gap: .indicator,
                    accessory: includesBolt
                        ? .symbol(IconSymbolState(source: .primitive(.bolt), color: .custom(color), scale: 1))
                        : nil,
                    effect: RingEffectState(pulsesAccessory: true, tintsAccessory: true)
                )
                let scene = IconSceneState(outerRing: ring)
                let staticImage = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment))
                let chargingImage = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment, phase: phase))
                rendersByAlpha[alpha] = (try rgbaBytes(staticImage), try rgbaBytes(chargingImage))
            }

            let transparent = try XCTUnwrap(rendersByAlpha[0])
            XCTAssertFalse(pixelsDiffer(transparent.0, transparent.1),
                           "Charging animation must not make a transparent active arc or bolt visible; static track is unchanged.")
            let translucent = try XCTUnwrap(rendersByAlpha[0.4])
            XCTAssertTrue(pixelsDiffer(translucent.0, translucent.1),
                          "Charging phase should still animate a visible alpha-0.4 active arc/bolt.")
            let opaque = try XCTUnwrap(rendersByAlpha[1.0])
            XCTAssertNotEqual(opaque.0, opaque.1)
            XCTAssertLessThan(maxAlpha(translucent.1), maxAlpha(opaque.1),
                              "Translucent custom color must remain less opaque than the opaque color during animation.")
        }
    }

    @MainActor
    func testInactiveSemanticOverrideChangesZeroVolumeDotsInMenuBarAndDock() throws {
        let scene = IconSceneState(footer: .dots(DotsState(count: 4, activeCount: 0, color: .primary)))
        var appearance = IconAppearanceConfiguration.classic
        appearance.footer.color = .semanticOverrides([
            .inactive: IconRGBA(red: 0.1, green: 0.9, blue: 0.35, alpha: 1)
        ])
        let defaultScene = IconPaletteResolver.apply(scene, appearance: .classic)
        let overriddenScene = IconPaletteResolver.apply(scene, appearance: appearance)
        XCTAssertNotEqual(defaultScene, overriddenScene, "Resolved inactive dot colors must be part of the scene identity.")
        try assertMenuBarAndDockDiffer(defaultScene, overriddenScene)
    }

    @MainActor
    func testInactiveSemanticOverrideChangesBatteryAndVolumeArcTracksInMenuBarAndDock() throws {
        let scene = IconSceneState(
            outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.55, color: .primary)], gap: .closed
            ),
            footer: .arc(ArcState(progress: 0, color: .primary))
        )
        var appearance = IconAppearanceConfiguration.classic
        appearance.outerRing.color = .semanticOverrides([
            .inactive: IconRGBA(red: 0.95, green: 0.15, blue: 0.2, alpha: 1)
        ])
        appearance.footer.color = .semanticOverrides([
            .inactive: IconRGBA(red: 0.1, green: 0.35, blue: 1, alpha: 1)
        ])
        let defaultScene = IconPaletteResolver.apply(scene, appearance: .classic)
        let overriddenScene = IconPaletteResolver.apply(scene, appearance: appearance)
        XCTAssertNotEqual(defaultScene, overriddenScene, "Resolved inactive ring/arc colors must participate in scene identity.")
        try assertMenuBarAndDockDiffer(defaultScene, overriddenScene)
    }

    @MainActor
    private func assertMenuBarAndDockDiffer(_ lhs: IconSceneState, _ rhs: IconSceneState) throws {
        let environment = StatusIconRenderEnvironment(
            size: 28, scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let menuBar = [lhs, rhs].map { StatusIconRenderer.render(scene: $0, environment: environment) }
        let dock = [lhs, rhs].map { DockIconRenderer.image(scene: $0, backgroundStyle: .dark, pixelLength: 96) }
        let menuBarBytes = try menuBar.map { try rgbaBytes(try XCTUnwrap($0)) }
        let dockBytes = try dock.map { try rgbaBytes(try XCTUnwrap($0)) }
        XCTAssertTrue(pixelsDiffer(menuBarBytes[0], menuBarBytes[1]), "Menu Bar inactive pixels should use the override.")
        XCTAssertTrue(pixelsDiffer(dockBytes[0], dockBytes[1]), "Dock inactive pixels should use the override.")
        XCTAssertNotEqual(
            DockIconRenderKey(scene: lhs, backgroundStyle: .dark, pixelLength: 96),
            DockIconRenderKey(scene: rhs, backgroundStyle: .dark, pixelLength: 96),
            "Static Dock cache identity must retain resolved inactive colors."
        )
    }

    private func pixelsDiffer(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs != rhs
    }

    private func maxAlpha(_ bytes: [UInt8]) -> UInt8 {
        bytes.enumerated().compactMap { index, byte in index % 4 == 3 ? byte : nil }.max() ?? 0
    }

    func testNonFiniteRGBAComponentsUseOpaqueWhiteFallbackAndClampFiniteComponents() {
        let normalized = IconRGBA(red: .nan, green: .infinity, blue: -2, alpha: 0.4).normalized()
        XCTAssertEqual(normalized, IconRGBA(red: 1, green: 1, blue: 0, alpha: 0.4))
    }
    private func rgbaBytes(_ image: CGImage) throws -> [UInt8] {
        guard let data = image.dataProvider?.data else { throw NSError(domain: "IconPaletteResolverTests", code: 1) }
        guard let bytes = CFDataGetBytePtr(data) else { throw NSError(domain: "IconPaletteResolverTests", code: 3) }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data)))
    }

    @MainActor
    private func rgbaBytes(_ image: NSImage) throws -> [UInt8] {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw NSError(domain: "IconPaletteResolverTests", code: 2)
        }
        return try rgbaBytes(cgImage)
    }
}

private extension CenterState {
    var symbolScaleValue: Double? {
        switch self {
        case let .symbol(symbol): symbol.scale
        case let .text(text): text.scale
        }
    }

    var colorRole: IconColorRole? {
        switch self {
        case let .symbol(symbol): symbol.color
        case let .text(text): text.color
        }
    }
}

private extension FooterState {
    var strokeScaleValue: Double {
        switch self {
        case let .dots(dots): dots.strokeScale
        case let .arc(arc): arc.strokeScale
        }
    }

    var colorRole: IconColorRole? {
        switch self {
        case let .dots(dots): dots.color
        case let .arc(arc): arc.color
        }
    }
}
