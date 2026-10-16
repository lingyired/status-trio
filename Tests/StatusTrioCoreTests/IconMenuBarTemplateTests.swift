import AppKit
import Testing
@testable import StatusTrioCore

/// Issue #112: the menu bar hands monochrome scenes to the system as template
/// images, so the system can keep the tint live while a Space switch is dragged.
/// A scene with any status colour stays a custom multi-colour raster, because a
/// template image would drop that colour.
@MainActor
struct IconMenuBarTemplateTests {
    // MARK: - Role collection

    @Test func colorRolesCollectEveryDrawnRegion() {
        let scene = IconSceneState(
            outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.5, color: .critical)],
                gap: .indicator,
                accessory: .symbol(IconSymbolState(source: .primitive(.bolt), color: .inactive, scale: 1))
            ),
            center: .text(IconTextState(text: "42", color: .primary, scale: 1)),
            footer: .arc(ArcState(progress: 0.5, color: .bluetooth))
        )

        #expect(scene.colorRoles == [.critical, .inactive, .primary, .bluetooth])
        #expect(scene.usesOnlyMonochromeRoles == false)
    }

    @Test func primaryAndInactiveRolesAreTheOnlyMonochromeRoles() {
        for role in [IconColorRole.primary, .inactive] {
            let scene = IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.5, color: role)],
                gap: .closed
            ))
            #expect(scene.usesOnlyMonochromeRoles, "\(role)")
        }

        for role in [IconColorRole.critical, .lowPower, .powered, .bluetooth] {
            let scene = IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.5, color: role)],
                gap: .closed
            ))
            #expect(scene.usesOnlyMonochromeRoles == false, "\(role)")
        }
    }

    // MARK: - Mapping

    @Test func ordinaryUnpluggedSceneIsMonochrome() {
        #expect(mappedScene(snapshot: PresentationFixtures.snapshot()).usesOnlyMonochromeRoles)
    }

    @Test func statusColorsDisabledKeepsEveryRoleMonochrome() {
        let configuration = IconPresentationConfiguration(
            battery: BatteryIconOptions(usesStatusColors: false),
            connection: .standard,
            volume: .standard,
            bluetooth: .standard
        )
        let scene = mappedScene(snapshot: PresentationFixtures.snapshot(), configuration: configuration)

        #expect(scene.usesOnlyMonochromeRoles)
    }

    @Test func statusColourSnapshotsAreNotMonochrome() {
        let cases: [(String, StatusSnapshot)] = [
            ("critical", batterySnapshot(percentage: 10)),
            ("lowPower", batterySnapshot(percentage: 60, isLowPowerMode: true)),
            ("powered", batterySnapshot(percentage: 80, isConnectedToPower: true)),
            ("charging", batterySnapshot(percentage: 80, isCharging: true, isConnectedToPower: true))
        ]

        for (name, snapshot) in cases {
            let scene = mappedScene(snapshot: snapshot)
            #expect(scene.usesOnlyMonochromeRoles == false, "\(name) must keep its status colour")
        }
    }

    @Test func bluetoothSceneIsNotMonochrome() {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -61),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: SheetFixtures.bluetoothDevice.name,
                currentDevice: SheetFixtures.bluetoothDevice
            )
        )
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true, usesVolumeColor: true)
        )
        let scene = mappedScene(snapshot: snapshot, configuration: configuration)

        #expect(scene.colorRoles.contains(.bluetooth))
        #expect(scene.usesOnlyMonochromeRoles == false)
    }

    // MARK: - Menu bar rendering

    @Test func monochromeSceneRendersAsTemplateMenuBarImage() throws {
        let scene = mappedScene(snapshot: PresentationFixtures.snapshot())

        let image = try #require(StatusIconRenderer.menuBarImage(
            scene: scene,
            size: 28,
            scale: 2,
            appearance: NSAppearance(named: .aqua)
        ))

        #expect(image.isTemplate)
    }

    @Test func templateFlagDoesNotDependOnAppearance() throws {
        let scene = mappedScene(snapshot: PresentationFixtures.snapshot())

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let image = try #require(StatusIconRenderer.menuBarImage(
                scene: scene,
                size: 28,
                scale: 2,
                appearance: NSAppearance(named: name)
            ))
            #expect(image.isTemplate, "\(name) must still be a template")
        }
    }

    @Test func statusColourScenesStayCustomRasters() throws {
        let scenes = [
            mappedScene(snapshot: batterySnapshot(percentage: 10)),
            mappedScene(snapshot: batterySnapshot(percentage: 60, isLowPowerMode: true)),
            mappedScene(snapshot: batterySnapshot(percentage: 80, isConnectedToPower: true))
        ]

        for scene in scenes {
            let image = try #require(StatusIconRenderer.menuBarImage(scene: scene, size: 28, scale: 2))
            #expect(image.isTemplate == false)
        }
    }

    @Test func preRenderedMenuBarImageMatchesTheSameTemplateRule() throws {
        let phase = ChargingEffectPhase(step: 0, stepsPerCycle: 36, kind: .steady)
        let appearance = try #require(NSAppearance(named: .aqua))

        let monochrome = try #require(StatusIconRenderer.preRenderedMenuBarImage(
            scene: mappedScene(snapshot: PresentationFixtures.snapshot()),
            size: 28,
            scale: 2,
            appearance: appearance,
            phase: phase
        ))
        #expect(monochrome.isTemplate)

        let coloured = try #require(StatusIconRenderer.preRenderedMenuBarImage(
            scene: mappedScene(snapshot: batterySnapshot(percentage: 80, isConnectedToPower: true)),
            size: 28,
            scale: 2,
            appearance: appearance,
            phase: phase
        ))
        #expect(coloured.isTemplate == false)
    }

    // MARK: - Non-menu-bar surfaces stay non-template

    /// The Settings previews and the Dock draw full colour, so the generic
    /// renderer and the Dock renderer must never hand back a template image.
    @Test func genericRendererImageStaysNonTemplate() throws {
        let scene = mappedScene(snapshot: PresentationFixtures.snapshot())

        let image = try #require(StatusIconRenderer.image(scene: scene, size: 28, scale: 2))

        #expect(image.isTemplate == false)
    }

    @Test func dockIconStaysNonTemplateForMonochromeScenes() throws {
        let scene = mappedScene(snapshot: PresentationFixtures.snapshot())

        for style in DockIconBackgroundStyle.allCases {
            let image = try #require(DockIconRenderer.image(scene: scene, backgroundStyle: style, pixelLength: 96))
            #expect(image.isTemplate == false, "\(style) must stay a full-colour Dock icon")
        }
    }

    // MARK: - Helpers

    private func mappedScene(
        snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
    }

    private func batterySnapshot(
        percentage: Int,
        isCharging: Bool = false,
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool = false
    ) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: isCharging,
                isLowPowerMode: isLowPowerMode,
                isConnectedToPower: isConnectedToPower
            ),
            wifi: WiFiStatus(state: .connected, rssi: -61),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
    }
}
