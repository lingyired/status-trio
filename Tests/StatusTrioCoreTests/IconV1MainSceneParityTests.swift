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
}
