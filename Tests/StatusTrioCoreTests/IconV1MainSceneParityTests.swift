import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
/// The V1 runtime path and the legacy/main mapper must produce the same centre
/// scene for the same settings. Any divergence shows up as a different icon
/// size or a different glyph, which is exactly the class of bug reported when
/// the input-source icon rendered smaller than Wi-Fi.
final class IconV1MainSceneParityTests: XCTestCase {
    private func snapshot() -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -50), connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: nil))
    }
    private func centerScale(_ c: CenterState?) -> Double? {
        switch c { case let .symbol(s): s.scale; case let .text(t): t.scale; default: nil }
    }
    private func centerKind(_ c: CenterState?) -> String {
        switch c { case .symbol: "symbol"; case .text: "text"; default: "nil" }
    }
    private static func differ(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): false
        case let (x?, y?): abs(x - y) > 1e-9
        default: true
        }
    }

    func testV1CentreMatchesMainMapperAcrossScalesAndSources() throws {
        let suite = "zzparity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let iconURL = try InputSourceIconFixtures.writeIcon(
            pixelWidth: 96, pixelHeight: 48, inkRect: CGRect(x: 48, y: 8, width: 40, height: 32))
        defer { try? FileManager.default.removeItem(at: iconURL) }
        let descriptor = InputSourceDescriptor(id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en", iconURL: iconURL, shortLabel: "A")
        var mismatches = 0
        for scale in [1.0, 1.3, 1.6, 1.8] {
            store.wifiSymbolScale = scale
            for source in [ConnectionCenterSource.network, .inputSource, .batteryPercentage, .bluetoothDevice] {
                store.connectionCenterSource = source
                let config = store.derivedIconConfigurationFromSettings()
                let inputs = IconResolutionInputs(
                    system: IconPresentationInputs(snapshot: snapshot(), audioIcon: nil, inputSource: descriptor),
                    sources: .empty)
                let v1 = IconCompositionResolver.resolve(inputs: inputs, configuration: config).scene
                let main = IconPresentationMapper.scene(
                    inputs: IconPresentationInputs(snapshot: snapshot(), audioIcon: nil, inputSource: descriptor),
                    configuration: IconPresentationConfiguration(
                        battery: store.batteryIconOptions, connection: store.connectionIconOptions,
                        volume: store.volumeIconOptions, bluetooth: store.bluetoothAudioIconOptions))
                let vs = centerScale(v1.center), ms = centerScale(main.center)
                if Self.differ(vs, ms) { mismatches += 1; print("MISMATCH scale=\(scale) src=\(source) v1=\(String(describing: vs)) main=\(String(describing: ms)) kindv1=\(centerKind(v1.center)) kindmain=\(centerKind(main.center))") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    /// #309: the monochrome-charging ring choice and the battery-less ring must
    /// resolve identically through the V1 path and the legacy/main mapper.
    func testBatteryRing309ChoicesMatchMainMapper() throws {
        let suite = "zz309parity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.connectionCenterSource = .network

        for present in [true, false] {
            for monochrome in [nil, true, false] as [Bool?] {
                store.monochromeChargingRing = monochrome
                let snapshot = StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: present ? 80 : 100,
                        isPresent: present,
                        isCharging: false,
                        isLowPowerMode: false,
                        isConnectedToPower: false
                    ),
                    wifi: WiFiStatus(state: .connected, rssi: -50),
                    connection: .wifi,
                    volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: nil)
                )
                let v1 = IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(
                        system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                        sources: .empty
                    ),
                    configuration: store.derivedIconConfigurationFromSettings()
                ).scene
                let main = IconPresentationMapper.scene(
                    inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                    configuration: IconPresentationConfiguration(
                        battery: store.batteryIconOptions,
                        connection: store.connectionIconOptions,
                        volume: store.volumeIconOptions,
                        bluetooth: store.bluetoothAudioIconOptions
                    )
                )
                XCTAssertEqual(
                    v1.outerRing, main.outerRing,
                    "batteryPresent=\(present) monochrome=\(String(describing: monochrome))"
                )
            }
        }
    }

    /// The charging-status centre (#253/#195) and whole-machine power are real
    /// main centre modes; the V1 path must draw the same percentage/bolt/plug
    /// the legacy mapper does (this was reported as "charging status not
    /// supported").
    func testChargingStatusCentreMatchesMainMapper() throws {
        let suite = "zzcs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.connectionCenterSource = .chargingStatus

        let states: [(String, BatteryStatus)] = [
            ("onBattery", BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
            ("charging", BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: true, isLowPowerMode: false, isConnectedToPower: true)),
            ("connected", BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: true))
        ]
        for (name, battery) in states {
            let snapshot = StatusSnapshot(
                battery: battery,
                wifi: WiFiStatus(state: .connected, rssi: -50),
                connection: .wifi,
                volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: nil)
            )
            let v1 = IconCompositionResolver.resolve(
                inputs: IconResolutionInputs(
                    system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                    sources: .empty
                ),
                configuration: store.derivedIconConfigurationFromSettings()
            ).scene.center
            let main = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                configuration: IconPresentationConfiguration(
                    battery: store.batteryIconOptions,
                    connection: store.connectionIconOptions,
                    volume: store.volumeIconOptions,
                    bluetooth: store.bluetoothAudioIconOptions
                )
            ).center
            XCTAssertEqual(Self.kind(v1), Self.kind(main), "\(name) centre kind")
            XCTAssertTrue(Self.approximatelyEqual(Self.scale(v1), Self.scale(main)), "\(name) centre scale")
        }
    }

    private static func kind(_ c: CenterState?) -> String {
        switch c { case .symbol: "symbol"; case .text: "text"; case .none: "nil"; default: "?" }
    }
    private static func scale(_ c: CenterState?) -> Double? {
        switch c { case let .symbol(s): s.scale; case let .text(t): t.scale; default: nil }
    }
    private static func approximatelyEqual(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) <= 1e-9
        default: false
        }
    }

    /// The Bluetooth-device centre must draw the same glyph / colour / size as
    /// main's `.bluetoothDevice` branch: no separate "selected device" is
    /// required — the current Bluetooth audio device is enough. Reported as
    /// "Bluetooth device not supported".
    func testBluetoothDeviceCentreMatchesMainMapper() throws {
        let suite = "zzbtp.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.connectionCenterSource = .bluetoothDevice

        let device = AudioOutputDevice(id: 1, name: "AirPods Pro", isCurrent: true, transport: .bluetooth)
        let scenarios: [(String, AudioOutputDevice?, String?)] = [
            ("bluetooth audio device", device, nil),
            ("no device", nil, nil),
            ("glyph override", device, "airpodspro")
        ]
        for (name, dev, override) in scenarios {
            store.bluetoothNetworkIconSymbolName = override
            let snapshot = StatusSnapshot(
                battery: BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false),
                wifi: WiFiStatus(state: .connected, rssi: -50),
                connection: .wifi,
                volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: dev?.name ?? "Output", currentDevice: dev)
            )
            let v1 = IconCompositionResolver.resolve(
                inputs: IconResolutionInputs(
                    system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                    sources: IconPresentationResourceResolver.sourceSnapshot(snapshot: snapshot)
                ),
                configuration: store.derivedIconConfigurationFromSettings()
            ).scene.center
            let main = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                configuration: IconPresentationConfiguration(
                    battery: store.batteryIconOptions,
                    connection: store.connectionIconOptions,
                    volume: store.volumeIconOptions,
                    bluetooth: store.bluetoothAudioIconOptions
                )
            ).center
            XCTAssertEqual(Self.kind(v1), Self.kind(main), "\(name) kind")
            XCTAssertTrue(Self.approximatelyEqual(Self.scale(v1), Self.scale(main)), "\(name) scale")
            XCTAssertEqual(Self.sourceName(v1), Self.sourceName(main), "\(name) symbol")
            XCTAssertEqual(Self.colorRole(v1), Self.colorRole(main), "\(name) colour")
        }
    }

    private static func sourceName(_ c: CenterState?) -> String? {
        if case let .symbol(s) = c, case let .symbol(name, _, _) = s.source { return name }
        return nil
    }
    private static func colorRole(_ c: CenterState?) -> String? {
        if case let .symbol(s) = c { return "\(s.color)" }
        return nil
    }

    /// Whole-surface pixel parity: every icon setting, every centre source and
    /// representative power states must render the same through the production
    /// V1 path as through the legacy/main mapper. This is the guard against a
    /// setting that changes the preview but not the menu bar (a field dropped in
    /// the V1 projection or lost when runtime options are applied).
    func testEveryIconSettingRendersTheSameSceneAsMain() throws {
        let suite = "zzpixel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = AudioOutputDevice(id: 1, name: "AirPods Pro", isCurrent: true, transport: .bluetooth)
        let descriptor = InputSourceDescriptor(id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en", iconURL: nil, shortLabel: "A")
        let batteries: [(String, BatteryStatus)] = [
            ("onBattery", BatteryStatus(rawPercentage: 55, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
            ("charging", BatteryStatus(rawPercentage: 55, isPresent: true, isCharging: true, isLowPowerMode: false, isConnectedToPower: true))
        ]
        let mutations: [(String, (SettingsStore) -> Void)] = [
            ("baseline", { _ in }),
            ("wifiSymbolScale", { $0.wifiSymbolScale = 1.15 }),
            ("bluetoothSymbolScale", { $0.bluetoothSymbolScale = 1.15 }),
            ("bluetoothIconColor", { $0.bluetoothIconColor = .primary }),
            ("bluetoothAudioIconChoice", { $0.bluetoothAudioIconChoice = .airpodsPro }),
            ("inputSourceMarkerStyle", { $0.inputSourceMarkerStyle = .zhong }),
            ("batteryOnBatteryMarker", { $0.batteryOnBatteryMarker = .hidden }),
            ("batterySplitGapProgress", { $0.batterySplitGapProgress = true }),
            ("batteryCriticalThreshold", { $0.batteryCriticalThreshold = 33 }),
            ("monochromeChargingRing", { $0.monochromeChargingRing = false }),
            ("volumeDisplayStyle", { $0.volumeDisplayStyle = .arc }),
            ("ringStrokeStyle", { $0.ringStrokeStyle = .bold })
        ]

        let environment = StatusIconRenderEnvironment(
            size: 120, scale: 3,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        func pixels(_ scene: IconSceneState) throws -> [UInt8]? {
            guard let image = StatusIconRenderer.render(scene: scene, environment: environment) else { return nil }
            return try PixelBuffer(image: image).bytes
        }

        for (batteryName, battery) in batteries {
            for (mutationName, apply) in mutations {
                let store = SettingsStore(defaults: defaults)
                apply(store)
                for source in ConnectionCenterSource.allCases {
                    store.connectionCenterSource = source
                    let snapshot = StatusSnapshot(
                        battery: battery,
                        wifi: WiFiStatus(state: .connected, rssi: -52),
                        connection: .wifi,
                        volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: device.name, currentDevice: device)
                    )
                    let v1 = IconCompositionResolver.resolve(
                        inputs: IconResolutionInputs(
                            system: IconPresentationResourceResolver.inputs(
                                snapshot: snapshot, inputSource: descriptor,
                                runtimeOptions: store.iconRuntimePresentationOptions
                            ),
                            sources: IconPresentationResourceResolver.sourceSnapshot(snapshot: snapshot)
                        ),
                        configuration: store.derivedIconConfigurationFromSettings()
                    ).scene
                    let main = IconPresentationMapper.scene(
                        inputs: IconPresentationResourceResolver.inputs(snapshot: snapshot, inputSource: descriptor),
                        configuration: store.legacyPresentationConfiguration
                    )
                    XCTAssertEqual(
                        try pixels(v1), try pixels(main),
                        "rendered icon differs: battery=\(batteryName) mutation=\(mutationName) centre=\(source)"
                    )
                }
            }
        }
    }
}
