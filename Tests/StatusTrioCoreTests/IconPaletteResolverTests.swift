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
