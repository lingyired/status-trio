import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRenderCacheTests {
    @Test func commitsOnlySuccessfulSceneAndSurfaceIdentity() {
        var cache = DockIconRenderCache()
        let baseScene = makeScene(rssi: -50)
        let dark = DockIconRenderKey(scene: baseScene, backgroundStyle: .dark, pixelLength: 512)
        let light = DockIconRenderKey(scene: baseScene, backgroundStyle: .light, pixelLength: 512)
        let preview = DockIconRenderKey(scene: baseScene, backgroundStyle: .dark, pixelLength: 256)
        let changedScene = DockIconRenderKey(
            scene: makeScene(rssi: -80), backgroundStyle: .dark, pixelLength: 512
        )

        #expect(cache.needsRender(dark))
        #expect(cache.needsRender(dark))
        cache.recordSuccessfulRender(dark)
        #expect(cache.needsRender(dark) == false)
        #expect(cache.needsRender(light))
        #expect(cache.needsRender(preview))
        #expect(cache.needsRender(changedScene))
    }

    @Test func resetAllowsTheSameSceneToRenderAgain() {
        var cache = DockIconRenderCache()
        let key = DockIconRenderKey(scene: makeScene(), backgroundStyle: .dark, pixelLength: 512)
        cache.recordSuccessfulRender(key)

        cache.reset()

        #expect(cache.needsRender(key))
    }

    @Test func imageCacheReusesAndEvictsLeastRecentlyUsedRaster() {
        let cache = DockIconImageCache(limit: 2)
        let first = key(rssi: -50)
        let second = key(rssi: -65)
        let third = key(rssi: -80)
        let firstImage = NSImage(size: NSSize(width: 512, height: 512))
        let secondImage = NSImage(size: NSSize(width: 512, height: 512))
        let thirdImage = NSImage(size: NSSize(width: 512, height: 512))

        cache.store(firstImage, for: first)
        cache.store(secondImage, for: second)
        #expect(cache.image(for: first) === firstImage)
        cache.store(thirdImage, for: third)

        #expect(cache.image(for: second) == nil)
        #expect(cache.image(for: first) === firstImage)
        #expect(cache.image(for: third) === thirdImage)
    }

    @Test func dockIdentityIgnoresChargingEffectButRetainsCanonicalSceneAndStaticInputs() {
        let charging = chargingScene(options: .standard)
        let heartbeatDisabled = chargingScene(options: BatteryIconOptions(
            showsChargingBoltHeartbeat: false
        ))
        let effectDisabled = chargingScene(options: BatteryIconOptions(
            showsChargingEffect: false
        ))
        let regularStroke = chargingScene(options: BatteryIconOptions(
            ringStrokeScale: RingStrokeStyle.regular.scale
        ))
        let boldStroke = chargingScene(options: BatteryIconOptions(
            ringStrokeScale: RingStrokeStyle.bold.scale
        ))
        let chargingKey = DockIconRenderKey(scene: charging, backgroundStyle: .dark, pixelLength: 512)
        let heartbeatKey = DockIconRenderKey(scene: heartbeatDisabled, backgroundStyle: .dark, pixelLength: 512)
        let effectKey = DockIconRenderKey(scene: effectDisabled, backgroundStyle: .dark, pixelLength: 512)
        let boldKey = DockIconRenderKey(scene: boldStroke, backgroundStyle: .dark, pixelLength: 512)

        #expect(charging.outerRing?.effect?.pulsesAccessory == true)
        #expect(heartbeatDisabled.outerRing?.effect?.pulsesAccessory == false)
        #expect(effectDisabled.outerRing?.effect == nil)
        #expect(charging != heartbeatDisabled)
        #expect(charging != effectDisabled)
        #expect(chargingKey.scene == charging, "the key exposes the canonical shared scene")
        #expect(chargingKey == heartbeatKey)
        #expect(chargingKey == effectKey)
        #expect(Set([chargingKey, heartbeatKey, effectKey]).count == 1)
        #expect(DockIconRenderKey(scene: regularStroke, backgroundStyle: .dark, pixelLength: 512) != boldKey)
        #expect(DockIconRenderKey(scene: charging, backgroundStyle: .light, pixelLength: 512) != chargingKey)
        #expect(DockIconRenderKey(scene: charging, backgroundStyle: .dark, pixelLength: 256) != chargingKey)

        let imageCache = DockIconImageCache()
        let cachedImage = NSImage(size: NSSize(width: 512, height: 512))
        imageCache.store(cachedImage, for: chargingKey)
        #expect(imageCache.image(for: heartbeatKey) === cachedImage)

        let previewCache = DockIconPreviewCache()
        var previewRenders = 0
        let previewImage = previewCache.image(for: chargingKey) {
            previewRenders += 1
            return NSImage(size: NSSize(width: 512, height: 512))
        }
        let reusedPreview = previewCache.image(for: effectKey) {
            previewRenders += 1
            return NSImage(size: NSSize(width: 512, height: 512))
        }
        #expect(previewRenders == 1)
        #expect(reusedPreview === previewImage)
    }

    /// The Dock tile renders the same scene as the menu bar, so the dock key
    /// carries the classified output glyph: two classifications must not share
    /// one raster. The snapshot keeps Wi-Fi connected so the replacement is not
    /// suppressed by the network-error priority.
    @Test func rendersAgainWhenTheClassifiedGlyphChanges() {
        let snapshot = bluetoothSnapshot()
        let headphones = makeScene(
            inputs: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: .symbol(name: "headphones", variableValue: nil, fallback: nil)
            ),
            configuration: bluetoothReplacementConfiguration()
        )
        let airPods = makeScene(
            inputs: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: .symbol(name: "airpods", variableValue: nil, fallback: nil)
            ),
            configuration: bluetoothReplacementConfiguration()
        )

        #expect(headphones != airPods)
    }

    /// A picked device's symbol overrides the classified audio glyph, so the
    /// key must differ from the same status rendered with the audio-device
    /// behavior.
    @Test func carriesTheNetworkIconOverrideInTheKey() {
        let snapshot = bluetoothSnapshot()
        let audioDevice = makeScene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: bluetoothReplacementConfiguration()
        )
        let overridden = makeScene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: bluetoothReplacementConfiguration(override: "applewatch")
        )

        #expect(audioDevice != overridden)
    }

    /// The override stands in for the current output's glyph: the key carries
    /// it even when no audio device is current, which is the state the picker
    /// mode mostly runs in.
    @Test func carriesTheOverrideEvenWithoutACurrentAudioDevice() {
        let snapshot = volumeSnapshot()
        let overridden = makeScene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: bluetoothReplacementConfiguration(override: "gamecontroller")
        )
        let untouched = makeScene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: bluetoothReplacementConfiguration()
        )

        #expect(overridden != untouched)
    }

    private func makeScene(
        inputs: IconPresentationInputs,
        configuration: IconPresentationConfiguration
    ) -> IconSceneState {
        IconPresentationMapper.scene(inputs: inputs, configuration: configuration)
    }

    private func bluetoothReplacementConfiguration(
        override: String? = nil
    ) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                networkIconSymbolOverride: override
            )
        )
    }

    private func bluetoothSnapshot() -> StatusSnapshot {
        StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "小王的耳机",
                currentDevice: AudioOutputDevice(
                    id: 42,
                    name: "小王的耳机",
                    isCurrent: true,
                    volume: 0.5,
                    transport: .bluetooth,
                    modelUID: "200f 4c"
                )
            )
        )
    }

    private func volumeSnapshot() -> StatusSnapshot {
        StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
    }

    private func key(rssi: Int = -50) -> DockIconRenderKey {
        DockIconRenderKey(scene: makeScene(rssi: rssi), backgroundStyle: .dark, pixelLength: 512)
    }

    private func makeScene(rssi: Int = -50) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: PresentationFixtures.snapshot(rssi: rssi),
                audioIcon: nil
            ),
            configuration: .standard
        )
    }

    private func chargingScene(options: BatteryIconOptions) -> IconSceneState {
        var snapshot = PresentationFixtures.snapshot()
        snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: snapshot.wifi,
            connection: snapshot.connection,
            volume: snapshot.volume
        )
        return IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: options,
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            )
        )
    }
}
