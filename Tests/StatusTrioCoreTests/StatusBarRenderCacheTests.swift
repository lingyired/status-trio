import CoreAudio
import XCTest
@testable import StatusTrioCore

final class StatusBarRenderCacheTests: XCTestCase {
    func testFailedRasterDoesNotBecomeSuccessfulKey() {
        var cache = StatusBarRenderCache()
        let key = makeKey()

        XCTAssertTrue(cache.needsRender(key))
        XCTAssertTrue(cache.needsRender(key))
        cache.recordSuccessfulRender(key)
        XCTAssertFalse(cache.needsRender(key))
    }

    func testBackingScaleAndAppearanceArePartOfMenuBarRasterIdentity() {
        var cache = StatusBarRenderCache()
        let scene = makeScene()
        let oneXAqua = StatusBarRenderKey(
            scene: scene, iconSize: 28, backingScale: 1,
            appearanceName: "NSAppearanceNameAqua", phase: nil
        )
        let twoXAqua = StatusBarRenderKey(
            scene: scene, iconSize: 28, backingScale: 2,
            appearanceName: "NSAppearanceNameAqua", phase: nil
        )
        let twoXDark = StatusBarRenderKey(
            scene: scene, iconSize: 28, backingScale: 2,
            appearanceName: "NSAppearanceNameDarkAqua", phase: nil
        )

        XCTAssertTrue(cache.needsRender(oneXAqua))
        cache.recordSuccessfulRender(oneXAqua)
        XCTAssertTrue(cache.needsRender(twoXAqua))
        cache.recordSuccessfulRender(twoXAqua)
        XCTAssertTrue(cache.needsRender(twoXDark))
    }

    func testSceneAndFramePhaseArePartOfMenuBarRasterIdentity() {
        var cache = StatusBarRenderCache()
        let scene = makeScene(rssi: -50)
        let otherScene = makeScene(rssi: -80)
        let steadyFrame = ChargingEffectPhase(step: 0, stepsPerCycle: 36, kind: .steady)
        let nextSteadyFrame = ChargingEffectPhase(step: 1, stepsPerCycle: 36, kind: .steady)
        let first = makeKey(scene: scene, phase: steadyFrame)

        cache.recordSuccessfulRender(first)

        XCTAssertFalse(cache.needsRender(first))
        XCTAssertTrue(cache.needsRender(makeKey(scene: scene, phase: nextSteadyFrame)))
        XCTAssertTrue(cache.needsRender(makeKey(scene: otherScene, phase: steadyFrame)))
    }

    func testOutputDeviceMetadataDoesNotChangeScene() {
        let first = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.5, isMuted: false, deviceName: "Speakers",
                outputDevices: [makeDevice(id: 1, uid: "one")]
            )
        )
        let second = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.5, isMuted: false, deviceName: "Speakers",
                outputDevices: [makeDevice(id: 2, uid: "two")]
            )
        )

        XCTAssertNotEqual(first.volume, second.volume)
        XCTAssertEqual(makeScene(snapshot: first), makeScene(snapshot: second))
    }

    func testRingStrokeWidthChangeChangesSceneIdentity() {
        let light = IconPresentationConfiguration(
            battery: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.light.scale),
            connection: .standard, volume: .standard, bluetooth: .standard
        )
        let bold = IconPresentationConfiguration(
            battery: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale),
            connection: .standard, volume: .standard, bluetooth: .standard
        )

        XCTAssertNotEqual(makeScene(configuration: light), makeScene(configuration: bold))
    }

    /// Main added the Apple device glyph override after the presentation
    /// refactor branched, so the scene it feeds into must still notice it.
    func testAppleWatchDeviceOverrideChangesSceneIdentity() {
        let snapshot = bluetoothSnapshot()
        let withoutGlyph = makeScene(
            configuration: configuration(bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true)),
            snapshot: snapshot
        )
        let appleWatchGlyph = makeScene(
            configuration: configuration(
                bluetooth: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    networkIconSymbolOverride: "applewatch"
                )
            ),
            snapshot: snapshot
        )

        XCTAssertNotEqual(withoutGlyph, appleWatchGlyph)
    }

    /// Main let the user scale the Bluetooth glyph; the scale is part of the
    /// symbol state, so two scales must not share one cached raster.
    func testBluetoothSymbolScaleChangeChangesSceneIdentity() {
        let snapshot = bluetoothSnapshot()
        let standard = makeScene(
            configuration: configuration(bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true)),
            snapshot: snapshot
        )
        let scaled = makeScene(
            configuration: configuration(
                bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true, symbolScale: 1.45)
            ),
            snapshot: snapshot
        )

        XCTAssertNotEqual(standard, scaled)
    }

    private func configuration(
        bluetooth: BluetoothAudioIconOptions
    ) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: .standard,
            bluetooth: bluetooth
        )
    }

    private func bluetoothSnapshot() -> StatusSnapshot {
        StatusSnapshot(
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
    }

    private func makeKey(
        scene: IconSceneState? = nil,
        phase: ChargingEffectPhase? = nil
    ) -> StatusBarRenderKey {
        StatusBarRenderKey(
            scene: scene ?? makeScene(),
            iconSize: 28,
            backingScale: 2,
            appearanceName: "NSAppearanceNameAqua",
            phase: phase
        )
    }

    private func makeScene(
        rssi: Int = -50,
        configuration: IconPresentationConfiguration = .standard,
        snapshot: StatusSnapshot? = nil
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot ?? PresentationFixtures.snapshot(rssi: rssi),
                audioIcon: nil
            ),
            configuration: configuration
        )
    }

    private func makeDevice(id: AudioDeviceID, uid: String) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            name: uid,
            uid: uid,
            isCurrent: id == 1,
            volume: 0.5
        )
    }
}
