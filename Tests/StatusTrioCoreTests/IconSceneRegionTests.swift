import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

/// Issue #112: the menu bar tints the monochrome primitives by handing them to
/// the system as a template image and keeps the status colours in a custom
/// raster above it. That split is sound as long as the status-coloured
/// primitives are drawn after every monochrome primitive they cover — the
/// overlay always sits on top — and `templatePlusOverlayReproducesTheSinglePassRender`
/// pins the resulting pixels against the one-pass render.
@MainActor
struct IconSceneRegionTests {
    private static let size: CGFloat = 120
    private static let scale: CGFloat = 1

    // MARK: - Paint order

    @Test func monochromeRegionsNeverCoverALaterStatusColourRegion() throws {
        for (name, scene) in representativeScenes() {
            let chromatic = scene.chromaticRegions
            guard !chromatic.isEmpty else { continue }

            for region in IconSceneRegion.allPrimitives where chromatic.contains(region) {
                let laterMonochrome = paintedAfter(region).intersection(scene.templateRegions)
                guard !laterMonochrome.isEmpty else { continue }

                let shared = try sharedPixels(
                    scene: scene,
                    first: region,
                    second: laterMonochrome
                )
                // A one-unit halo is the antialiasing of two strokes that touch;
                // anything more would move the status colour under the tinted
                // chrome and change the picture.
                #expect(
                    shared == 0,
                    "\(name): \(laterMonochrome) is drawn after \(region) but shares \(shared) pixels"
                )
            }
        }
    }

    // MARK: - Composite equivalence

    @Test func templatePlusOverlayReproducesTheSinglePassRender() throws {
        let foregrounds = [
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 0, alpha: 1)
        ]
        for (name, scene) in representativeScenes() {
            for foreground in foregrounds {
                let environment = StatusIconRenderEnvironment(
                    size: Self.size,
                    scale: Self.scale,
                    foreground: foreground,
                    criticalColor: StatusIconRenderer.defaultCriticalColor
                )
                let whole = try #require(StatusIconRenderer.render(scene: scene, environment: environment))
                let base = try #require(StatusIconRenderer.render(
                    scene: scene,
                    environment: environment,
                    regions: scene.templateRegions
                ))
                let overlay = try #require(StatusIconRenderer.render(
                    scene: scene,
                    environment: environment,
                    regions: scene.chromaticRegions
                ))

                let composited = try composite(base: base, overlay: overlay, environment: environment)
                let wholePixels = try PixelBuffer(image: whole)
                let compositedPixels = try PixelBuffer(image: composited)
                let delta = maximumChannelDelta(compositedPixels.bytes, wholePixels.bytes)
                // Two rasterisations composited at 8-bit premultiplied precision
                // round independently, so an antialiased edge may land one
                // 255th away from the single-pass render. Anything larger means
                // a primitive changed colour or moved between the two passes.
                #expect(delta <= 1, "\(name) at \(foreground): channel delta \(delta)")
            }
        }
    }

    private func maximumChannelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        zip(lhs, rhs).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    // MARK: - Classification

    @Test func theAlwaysMonochromeChromeStaysInTheTemplate() {
        for (name, scene) in representativeScenes() {
            #expect(
                scene.templateRegions.isSuperset(of: .alwaysMonochrome),
                "\(name): the ring track and volume track are always the label colour"
            )
        }
    }

    @Test func monochromeScenesHaveNoOverlay() {
        for (name, scene) in representativeScenes() where scene.chromaticRegions.isEmpty {
            #expect(scene.templateRegions == .all, "\(name)")
        }
    }

    @Test func pluggedInRingKeepsTheChromeInTheTemplate() {
        // The user's case: the ring is a status colour, but the connection glyph
        // and the volume dots are still the label colour, and so is the plug in
        // the ring's top gap.
        let scene = mappedScene(snapshot: snapshot(percentage: 76, isConnectedToPower: true))

        #expect(scene.chromaticRegions == [.ringFill])
        #expect(scene.templateRegions.contains(.center))
        #expect(scene.templateRegions.contains(.footerFill))
        #expect(scene.templateRegions.contains(.ringTrack))
        #expect(scene.templateRegions.contains(.ringAccessory))
    }

    @Test func lowPowerRingKeepsThePercentageInTheTemplate() {
        let scene = mappedScene(snapshot: snapshot(percentage: 55, isLowPowerMode: true))

        #expect(scene.chromaticRegions.contains(.ringFill))
        #expect(scene.templateRegions.contains(.ringAccessory))
        #expect(scene.templateRegions.contains(.center))
    }

    @Test func bluetoothVolumeOnlyColoursTheFooter() {
        let scene = mappedScene(
            snapshot: bluetoothSnapshot(),
            configuration: IconPresentationConfiguration(
                battery: .standard,
                connection: .standard,
                volume: .standard,
                bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true, usesVolumeColor: true)
            )
        )

        #expect(scene.chromaticRegions == [.center, .footerFill])
        #expect(scene.templateRegions.contains(.ringFill))
        #expect(scene.templateRegions.contains(.footerTrack))
    }

    @Test func chargingEffectMovesTheWholeRingIntoTheOverlay() {
        let scene = mappedScene(snapshot: snapshot(percentage: 62, isCharging: true))

        // The effect animates the ring, its highlight, and the accessory, so the
        // template keeps only the always-monochrome chrome.
        #expect(scene.chromaticRegions.contains(.ringFill))
        #expect(scene.chromaticRegions.contains(.ringEffect))
        #expect(scene.chromaticRegions.contains(.ringAccessory))
        #expect(scene.templateRegions == [.ringTrack, .center, .footerTrack, .footerFill])
    }

    @Test func aPercentageIndicatorStaysInTheTemplateWhileCharging() {
        // Without the bolt there is no heartbeat, so the percentage is a static
        // label that can still be re-tinted for the Space being dragged toward.
        let scene = mappedScene(
            snapshot: snapshot(percentage: 62, isCharging: true),
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsChargingIndicator: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            )
        )

        #expect(scene.chromaticRegions.contains(.ringFill))
        #expect(scene.templateRegions.contains(.ringAccessory))
    }

    // MARK: - Menu bar layers

    @Test func menuBarLayersMarkTheBaseAsTemplate() throws {
        let scene = mappedScene(snapshot: snapshot(percentage: 76, isConnectedToPower: true))
        let layers = try #require(StatusIconRenderer.menuBarLayers(
            scene: scene,
            size: 28,
            scale: 2,
            appearance: NSAppearance(named: .aqua)
        ))

        #expect(layers.base.isTemplate)
        #expect(layers.overlay != nil)
    }

    @Test func menuBarLayersOmitTheOverlayForMonochromeScenes() throws {
        let scene = mappedScene(snapshot: snapshot(percentage: 76))
        let layers = try #require(StatusIconRenderer.menuBarLayers(
            scene: scene,
            size: 28,
            scale: 2,
            appearance: NSAppearance(named: .aqua)
        ))

        #expect(layers.base.isTemplate)
        #expect(layers.overlay == nil)
    }

    // MARK: - Fixtures

    private func representativeScenes() -> [(String, IconSceneState)] {
        var scenes: [(String, IconSceneState)] = [
            ("plain", mappedScene(snapshot: snapshot(percentage: 76))),
            ("empty", mappedScene(snapshot: snapshot(percentage: 0))),
            ("full", mappedScene(snapshot: snapshot(percentage: 100))),
            ("plugged-in", mappedScene(snapshot: snapshot(percentage: 76, isConnectedToPower: true))),
            ("plugged-in percentage", mappedScene(
                snapshot: snapshot(percentage: 76, isConnectedToPower: true),
                configuration: IconPresentationConfiguration(
                    battery: BatteryIconOptions(showsPercentageWhenConnected: true),
                    connection: .standard,
                    volume: .standard,
                    bluetooth: .standard
                )
            )),
            ("low power", mappedScene(snapshot: snapshot(percentage: 55, isLowPowerMode: true))),
            ("critical", mappedScene(snapshot: snapshot(percentage: 12))),
            ("charging", mappedScene(snapshot: snapshot(percentage: 62, isCharging: true))),
            ("muted", mappedScene(snapshot: snapshot(percentage: 76, scalar: 0))),
            ("arc volume", mappedScene(
                snapshot: snapshot(percentage: 76),
                configuration: IconPresentationConfiguration(
                    battery: .standard,
                    connection: .standard,
                    volume: VolumeIconOptions(displayStyle: .arc),
                    bluetooth: .standard
                )
            )),
            ("bluetooth audio", mappedScene(
                snapshot: bluetoothSnapshot(),
                configuration: IconPresentationConfiguration(
                    battery: .standard,
                    connection: .standard,
                    volume: .standard,
                    bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true, usesVolumeColor: true)
                )
            )),
            ("ethernet", mappedScene(snapshot: snapshot(percentage: 76, connection: .ethernet)))
        ]
        scenes.append((
            "unknown rssi",
            mappedScene(snapshot: snapshot(percentage: 76, rssi: nil))
        ))
        return scenes
    }

    private func mappedScene(
        snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
    }

    private func snapshot(
        percentage: Int,
        isCharging: Bool = false,
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool = false,
        scalar: Double = 0.6,
        rssi: Int? = -55,
        connection: NetworkConnection = .wifi
    ) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: isCharging,
                isLowPowerMode: isLowPowerMode,
                isConnectedToPower: isConnectedToPower
            ),
            wifi: WiFiStatus(state: .connected, rssi: rssi),
            connection: connection,
            volume: VolumeStatus(scalar: scalar, isMuted: scalar == 0, deviceName: "Output")
        )
    }

    private func bluetoothSnapshot() -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: SheetFixtures.bluetoothDevice.name,
                currentDevice: SheetFixtures.bluetoothDevice
            )
        )
    }

    private func alphaMask(scene: IconSceneState, regions: IconSceneRegion) throws -> [UInt8] {
        let image = try #require(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: Self.size,
                scale: Self.scale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            ),
            regions: regions
        ))
        let buffer = try PixelBuffer(image: image)
        return stride(from: 3, to: buffer.bytes.count, by: 4).map { buffer.bytes[$0] }
    }

    /// Counts the pixels two region groups both cover with more than a rounding
    /// halo: a pixel that either layer covers by one 255th is antialiasing, not
    /// an overlap.
    private func sharedPixels(
        scene: IconSceneState,
        first: IconSceneRegion,
        second: IconSceneRegion
    ) throws -> Int {
        let lhs = try alphaMask(scene: scene, regions: first)
        let rhs = try alphaMask(scene: scene, regions: second)
        return zip(lhs, rhs).reduce(0) { total, pair in
            total + (pair.0 > 1 && pair.1 > 1 ? 1 : 0)
        }
    }

    /// The primitives the renderer paints after `region`.
    private func paintedAfter(_ region: IconSceneRegion) -> IconSceneRegion {
        guard let index = IconSceneRegion.allPrimitives.firstIndex(of: region) else { return [] }
        return IconSceneRegion.allPrimitives[(index + 1)...]
            .reduce(into: IconSceneRegion()) { $0.formUnion($1) }
    }

    private func composite(
        base: CGImage,
        overlay: CGImage,
        environment: StatusIconRenderEnvironment
    ) throws -> CGImage {
        let pixelLength = Int((environment.size * environment.scale).rounded(.up))
        let context = try #require(CGContext(
            data: nil,
            width: pixelLength,
            height: pixelLength,
            bitsPerComponent: 8,
            bytesPerRow: pixelLength * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let rect = CGRect(x: 0, y: 0, width: pixelLength, height: pixelLength)
        context.draw(base, in: rect)
        context.draw(overlay, in: rect)
        return try #require(context.makeImage())
    }
}
