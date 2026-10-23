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
        let firstImage = makeBitmapImage(width: 64, height: 64)
        let secondImage = makeBitmapImage(width: 64, height: 64)
        let thirdImage = makeBitmapImage(width: 64, height: 64)

        cache.store(firstImage, for: first)
        cache.store(secondImage, for: second)
        #expect(cache.image(for: first) === firstImage)
        cache.store(thirdImage, for: third)

        #expect(cache.image(for: second) == nil)
        #expect(cache.image(for: first) === firstImage)
        #expect(cache.image(for: third) === thirdImage)
    }

    @Test func imageCacheEnforcesEntryAndResidentByteBudgetsTogether() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 4 * 1024 * 1024)
        let smallKeys = [
            key(backgroundStyle: .light),
            key(backgroundStyle: .dark),
            key(backgroundStyle: .clear)
        ]
        let largeKey = key(scene: makeScene(rssi: -80))

        for key in smallKeys {
            cache.store(makeBitmapImage(width: 512, height: 512, hasAlpha: false), for: key)
        }
        cache.store(
            makeBitmapImage(width: 800, height: 800, hasAlpha: false),
            for: largeKey
        )

        #expect(cache.entryCount <= 4)
        #expect(cache.residentByteCount <= 4 * 1024 * 1024)
        #expect(cache.entryCount == 3)
        #expect(cache.image(for: smallKeys[0]) == nil)
        #expect(cache.image(for: largeKey) != nil)
    }

    @Test func imageCacheReplacesARasterInPlaceWithoutAddingAnotherEntry() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 4 * 1024 * 1024)
        let renderKey = key(rssi: -55)
        let first = makeBitmapImage(width: 128, height: 128, hasAlpha: false)
        let replacement = makeBitmapImage(width: 128, height: 128, hasAlpha: true)

        cache.store(first, for: renderKey)
        let firstByteCount = cache.residentByteCount
        cache.store(replacement, for: renderKey)

        #expect(cache.entryCount == 1)
        #expect(cache.image(for: renderKey) === replacement)
        #expect(cache.residentByteCount > firstByteCount)
    }

    @Test func imageCacheDoesNotRetainOneRasterLargerThanItsByteBudget() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 2 * 1024 * 1024)
        let oversized = key(rssi: -72)

        cache.store(makeBitmapImage(width: 768, height: 768), for: oversized)

        #expect(cache.entryCount == 0)
        #expect(cache.residentByteCount == 0)
        #expect(cache.image(for: oversized) == nil)
    }

    @Test func imageCacheAccountsEveryPlaneOfPlanarBitmaps() {
        let planarKey = key(rssi: -73)
        let planarImage = makePlanarBitmapImage(width: 64, height: 64)
        let bitmap = planarImage.representations.first as! NSBitmapImageRep
        let expectedBytes = bitmap.bytesPerPlane * bitmap.numberOfPlanes
        #expect(bitmap.isPlanar)
        #expect(bitmap.numberOfPlanes == 4)
        #expect(expectedBytes > bitmap.bytesPerRow * bitmap.pixelsHigh)

        let cache = DockIconImageCache(
            limit: 4,
            maximumResidentBytes: expectedBytes - 1
        )
        cache.store(planarImage, for: planarKey)

        #expect(cache.entryCount == 0)
        #expect(cache.residentByteCount == 0)
        #expect(cache.image(for: planarKey) == nil)
    }

    @Test func imageCacheUsesCostCapturedAtInsertionForEviction() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 16 * 1024)
        let firstKey = key(rssi: -73)
        let firstImage = makeBitmapImage(width: 64, height: 64)
        cache.store(firstImage, for: firstKey)
        #expect(cache.residentByteCount == 4 * 4 * 1024)

        firstImage.removeRepresentation(firstImage.representations[0])
        firstImage.addRepresentation(
            makeBitmapImage(width: 128, height: 128).representations[0]
        )
        cache.store(
            makeBitmapImage(width: 64, height: 64),
            for: key(rssi: -74)
        )

        #expect(cache.entryCount == 1)
        #expect(cache.residentByteCount == 4 * 4 * 1024)
    }

    @Test func imageCacheDoesNotEstimateUnknownRepresentations() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 4 * 1024 * 1024)
        let unknown = key(rssi: -74)
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.addRepresentation(UnknownImageRepresentation())

        cache.store(image, for: unknown)

        #expect(cache.entryCount == 0)
        #expect(cache.residentByteCount == 0)
        #expect(cache.image(for: unknown) == nil)
    }

    @Test func imageCacheKeepsARasterlessCompatibilityImageAtZeroBytes() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 4 * 1024 * 1024)
        let compatibility = key(rssi: -76)
        let image = NSImage(size: NSSize(width: 512, height: 512))

        cache.store(image, for: compatibility)

        #expect(cache.entryCount == 1)
        #expect(cache.residentByteCount == 0)
        #expect(cache.image(for: compatibility) === image)
    }

    @Test func imageCacheUsesRecentUseOrderWhenEvictingForBytes() {
        let cache = DockIconImageCache(
            limit: 4,
            maximumResidentBytes: 2 * 256 * 768 + 4
        )
        let first = key(backgroundStyle: .light)
        let second = key(backgroundStyle: .dark)
        let third = key(backgroundStyle: .clear)
        let firstImage = makeBitmapImage(width: 256, height: 256, hasAlpha: false)
        let secondImage = makeBitmapImage(width: 256, height: 256, hasAlpha: false)
        let thirdImage = makeBitmapImage(width: 256, height: 256, hasAlpha: false)

        cache.store(firstImage, for: first)
        cache.store(secondImage, for: second)
        #expect(cache.entryCount == 2)
        #expect(cache.residentByteCount > 0)
        #expect(cache.residentByteCount <= 2 * 256 * 768 + 4)
        #expect(cache.image(for: first) === firstImage)
        cache.store(thirdImage, for: third)

        #expect(cache.entryCount == 2)
        #expect(cache.image(for: first) === firstImage)
        #expect(cache.image(for: second) == nil)
        #expect(cache.image(for: third) === thirdImage)
    }

    @Test func imageCacheResetReleasesEveryAccountedByte() {
        let cache = DockIconImageCache(limit: 4, maximumResidentBytes: 4 * 1024 * 1024)
        cache.store(makeBitmapImage(width: 256, height: 256), for: key(rssi: -55))
        cache.store(makeBitmapImage(width: 128, height: 128), for: key(rssi: -75))
        #expect(cache.residentByteCount > 0)

        cache.reset()

        #expect(cache.entryCount == 0)
        #expect(cache.residentByteCount == 0)
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
        let cachedImage = makeBitmapImage(width: 64, height: 64)
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

    private func key(backgroundStyle: DockIconBackgroundStyle) -> DockIconRenderKey {
        DockIconRenderKey(
            scene: makeScene(),
            backgroundStyle: backgroundStyle,
            pixelLength: 512
        )
    }

    private func key(scene: IconSceneState) -> DockIconRenderKey {
        DockIconRenderKey(scene: scene, backgroundStyle: .dark, pixelLength: 512)
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

    private func makePlanarBitmapImage(width: Int, height: Int) -> NSImage {
        let pixelCount = width * height
        let red = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let green = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let blue = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let alpha = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        red.initialize(repeating: 0, count: pixelCount)
        green.initialize(repeating: 0, count: pixelCount)
        blue.initialize(repeating: 0, count: pixelCount)
        alpha.initialize(repeating: 255, count: pixelCount)
        defer {
            red.deinitialize(count: pixelCount)
            green.deinitialize(count: pixelCount)
            blue.deinitialize(count: pixelCount)
            alpha.deinitialize(count: pixelCount)
            red.deallocate()
            green.deallocate()
            blue.deallocate()
            alpha.deallocate()
        }
        let planes = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: 4)
        planes.initialize(from: [red, green, blue, alpha], count: 4)
        defer {
            planes.deinitialize(count: 4)
            planes.deallocate()
        }
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: planes,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: true,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(representation)
        return image
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

    private func makeBitmapImage(
        width: Int,
        height: Int,
        hasAlpha: Bool = true
    ) -> NSImage {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: hasAlpha ? 4 : 3,
            hasAlpha: hasAlpha,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(representation)
        return image
    }
}

private final class UnknownImageRepresentation: NSImageRep {}
