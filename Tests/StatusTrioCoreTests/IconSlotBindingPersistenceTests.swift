import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconSlotBindingPersistenceTests: XCTestCase {
    func testBindingStoreRoundTripsUnknownPluginIDs() throws {
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(
                primary: .init(pluginID: "com.example.ring", presentationID: "cpu"),
                fallback: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(primary: .init(pluginID: "com.example.latency", presentationID: "text")),
            footer: .init(primary: nil, fallback: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let data = try IconSlotBindingsCodec.encode(bindings)
        let decoded = try IconSlotBindingsCodec.decode(data)
        XCTAssertEqual(decoded, bindings.normalized())
        XCTAssertEqual(decoded.center.primary?.pluginID, "com.example.latency")
        XCTAssertNil(decoded.footer.primary, "an empty primary hides the slot and drops its fallback")
        XCTAssertNil(decoded.footer.fallback)
    }

    func testCodecRejectsFutureAndMalformedPayloads() throws {
        XCTAssertThrowsError(try IconSlotBindingsCodec.decode(Data(#"{"schemaVersion":2}"#.utf8))) {
            XCTAssertEqual($0 as? IconSlotBindingsCodecError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(try IconSlotBindingsCodec.decode(Data("{".utf8))) {
            XCTAssertEqual($0 as? IconSlotBindingsCodecError, .malformedData)
        }
    }

    func testMissingStoreMigratesTheCurrentIndividualSettingsOnce() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.outerRingContent = .airPodsBattery
        store.airPodsRingFallback = .hardwareMonitor
        store.connectionCenterSource = .inputSource
        store.bottomIndicatorSource = .wifi

        XCTAssertEqual(store.iconSlotBindings.outerRing.primary?.pluginID, "builtin.airpods-battery")
        XCTAssertEqual(store.iconSlotBindings.outerRing.fallback?.pluginID, "builtin.hardware-monitor")
        XCTAssertEqual(store.iconSlotBindings.center.primary?.pluginID, "builtin.input-source")
        XCTAssertEqual(store.iconSlotBindings.center.fallback?.pluginID, "builtin.network")
        XCTAssertEqual(store.iconSlotBindings.footer.primary?.pluginID, "builtin.network")
        XCTAssertNotNil(defaults.data(forKey: SettingsStore.iconSlotBindingsDefaultsKey),
                        "the migration is persisted immediately so it only runs once")

        // A second launch must read the persisted bindings rather than
        // re-importing a changed legacy key.
        defaults.set(ConnectionCenterSource.network.rawValue,
                     forKey: SettingsStore.connectionCenterSourceDefaultsKey)
        let relaunched = SettingsStore(defaults: defaults)
        XCTAssertEqual(relaunched.iconSlotBindings, store.iconSlotBindings)
    }

    func testLegacyPreferencesWinOverAConflictingPersistedV1Payload() throws {
        let defaults = try makeDefaults()
        var stored = IconConfigurationV1.classic
        stored.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        defaults.set(try IconConfigurationCodec.encode(stored),
                     forKey: SettingsStore.iconConfigurationDefaultsKey)
        defaults.set(ConnectionCenterSource.inputSource.rawValue,
                     forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.iconSlotBindings.center.primary?.pluginID, "builtin.input-source",
                       "the migrated binding must follow the live per-setting choice")
        XCTAssertEqual(store.iconSlotBindings.center.fallback?.pluginID, "builtin.network")
    }

    func testCorruptPayloadStaysUntouchedAndFallsBackForThisRun() throws {
        let defaults = try makeDefaults()
        let corrupt = Data("{not-json".utf8)
        defaults.set(corrupt, forKey: SettingsStore.iconSlotBindingsDefaultsKey)
        defaults.set(ConnectionCenterSource.inputSource.rawValue,
                     forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        let store = SettingsStore(defaults: defaults)
        XCTAssertNotNil(store.iconSlotBindingsLoadError)
        XCTAssertEqual(defaults.data(forKey: SettingsStore.iconSlotBindingsDefaultsKey), corrupt,
                       "the user's bytes must never be silently destroyed")
        XCTAssertEqual(store.iconSlotBindings.center.primary?.pluginID, "builtin.input-source",
                       "the current run falls back to the per-setting projection")

        // A later legacy edit must not overwrite the preserved payload either.
        store.connectionCenterSource = .network
        XCTAssertEqual(defaults.data(forKey: SettingsStore.iconSlotBindingsDefaultsKey), corrupt)
    }

    func testNewerSchemaStaysUntouched() throws {
        let defaults = try makeDefaults()
        let future = Data(#"{"schemaVersion":9,"center":{"primary":null}}"#.utf8)
        defaults.set(future, forKey: SettingsStore.iconSlotBindingsDefaultsKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.iconSlotBindingsLoadError, .unsupportedSchemaVersion(9))
        XCTAssertEqual(defaults.data(forKey: SettingsStore.iconSlotBindingsDefaultsKey), future)
    }

    func testSettingsControlRoutesThroughTheBindingSetter() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.outerRingContent = .hardwareMonitor
        XCTAssertEqual(store.iconSlotBindings.outerRing.primary,
                       .init(pluginID: "builtin.hardware-monitor", presentationID: "ring"))

        store.setIconSlotBinding(
            primary: .init(pluginID: "com.example.ring", presentationID: "load"),
            fallback: .init(pluginID: "builtin.system-battery", presentationID: "ring"),
            for: .outerRing)
        XCTAssertEqual(store.iconSlotBindings.outerRing.primary?.pluginID, "com.example.ring")
        XCTAssertEqual(store.iconSlotBindings.outerRing.fallback?.pluginID, "builtin.system-battery")

        let relaunched = SettingsStore(defaults: defaults)
        XCTAssertEqual(relaunched.iconSlotBindings, store.iconSlotBindings)
    }

    func testSelectingAnExternalSourceKeepsTheReplacedBuiltinAsFallback() throws {
        let store = SettingsStore(defaults: try makeDefaults())
        store.outerRingContent = .systemBattery
        let external = IconContentBinding(pluginID: "com.example.ring", presentationID: "load")

        store.selectExternalIconSlotSource(external, for: .outerRing)
        XCTAssertEqual(store.iconSlotBindings.outerRing.primary, external)
        XCTAssertEqual(
            store.iconSlotBindings.outerRing.fallback,
            .init(pluginID: "builtin.system-battery", presentationID: "ring"),
            "zero-fallback external selection must keep the replaced built-in source"
        )

        // An existing fallback is preserved instead of being overwritten by the
        // built-in primary that is replaced.
        let second = IconContentBinding(pluginID: "com.example.second", presentationID: "load")
        store.selectExternalIconSlotSource(second, for: .outerRing)
        XCTAssertEqual(store.iconSlotBindings.outerRing.primary, second)
        XCTAssertEqual(
            store.iconSlotBindings.outerRing.fallback,
            .init(pluginID: "builtin.system-battery", presentationID: "ring")
        )
    }

    func testSlotPickerStaysReachableAfterTheLastPackageDisappears() {
        let external = IconSlotBindingSelection(
            primary: .init(pluginID: "com.example.gone", presentationID: "load"))
        XCTAssertTrue(LocalIconPluginSlotPickerPolicy.showsMenu(hasOptions: false, selection: external))
        XCTAssertFalse(
            LocalIconPluginSlotPickerPolicy.showsMenu(
                hasOptions: false,
                selection: .init(primary: .init(pluginID: "builtin.system-battery",
                                               presentationID: "ring"))),
            "no packages and no external binding keeps the row hidden"
        )
        XCTAssertTrue(
            LocalIconPluginSlotPickerPolicy.showsMenu(
                hasOptions: true,
                selection: .init(primary: .init(pluginID: "builtin.system-battery",
                                               presentationID: "ring")))
        )

        let externalFallback = IconSlotBindingSelection(
            primary: .init(pluginID: "builtin.system-battery", presentationID: "ring"),
            fallback: .init(pluginID: "com.example.gone", presentationID: "load"))
        XCTAssertNil(LocalIconPluginSlotPickerPolicy.builtinFallback(for: externalFallback))
        let builtinFallback = IconSlotBindingSelection(
            primary: .init(pluginID: "com.example.gone", presentationID: "load"),
            fallback: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        XCTAssertEqual(
            LocalIconPluginSlotPickerPolicy.builtinFallback(for: builtinFallback)?.pluginID,
            "builtin.system-volume"
        )
    }

    func testUnknownPluginFallsBackAndRecoversWhenItReturns() throws {
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(
                primary: .init(pluginID: "test.external", presentationID: "latency"),
                fallback: .init(pluginID: "builtin.network", presentationID: "center")),
            footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: Self.snapshot, audioIcon: nil),
            sources: .empty)

        let without = IconCompositionResolver.resolve(
            inputs: inputs, configuration: .classic, bindings: bindings,
            registry: try Self.registry(includingExternal: false))
        XCTAssertEqual(without.trace.center.role, .fallback)
        XCTAssertEqual(without.trace.center.selectedSourceID, CenterSource.network.rawValue)

        let with = IconCompositionResolver.resolve(
            inputs: inputs, configuration: .classic, bindings: bindings,
            registry: try Self.registry(includingExternal: true))
        XCTAssertEqual(with.trace.center.role, .primary)
        XCTAssertEqual(with.trace.center.binding?.pluginID, "test.external")
        XCTAssertEqual(with.scene.center, .text(IconTextState(text: "42 ms", color: .primary, scale: 1)))
    }

    /// Every bottom-indicator choice the settings surface exposes must draw the
    /// same footer through the binding path as the legacy mapper.
    func testMigratedFooterBindingsMatchTheLegacyFooterForEverySource() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        var inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: Self.snapshot, audioIcon: nil),
            sources: .empty)

        for source in BottomIndicatorSource.allCases {
            store.bottomIndicatorSource = source
            inputs.system.bottomIndicatorSource = source
            let v1 = IconCompositionResolver.resolve(
                inputs: inputs,
                configuration: store.derivedIconConfigurationFromSettings(),
                bindings: store.iconSlotBindings
            )
            let legacy = IconPresentationMapper.scene(
                inputs: inputs.system,
                configuration: IconPresentationConfiguration(
                    battery: store.batteryIconOptions,
                    connection: store.connectionIconOptions,
                    volume: store.volumeIconOptions,
                    bluetooth: store.bluetoothAudioIconOptions
                )
            )
            XCTAssertEqual(v1.scene.footer, legacy.footer, "bottom source \(source)")
        }
    }

    // MARK: - Fixtures

    private static let snapshot = StatusSnapshot(
        battery: BatteryStatus(rawPercentage: 64, isPresent: true, isCharging: false,
                               isLowPowerMode: false, isConnectedToPower: false),
        wifi: WiFiStatus(state: .connected, rssi: -52),
        connection: .wifi,
        volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Built-in")
    )

    private func makeDefaults() throws -> UserDefaults {
        let name = "StatusTrioCoreTests.IconSlotBindings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private static func registry(includingExternal: Bool) throws -> IconContentPluginRegistry {
        var plugins: [any IconContentPlugin] = [
            InputSourceIconPlugin(), NetworkIconPlugin(), BluetoothDeviceIconPlugin(),
            SystemBatteryIconPlugin(), AirPodsBatteryIconPlugin(),
            HardwareMonitorIconPlugin(), SystemVolumeIconPlugin(), LegacyIconPlugin()
        ]
        if includingExternal { plugins.append(TestLatencyPlugin()) }
        return try IconContentPluginRegistry(plugins: plugins)
    }
}

private struct TestLatencyPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "test.external", presentations: [
        .init(id: "latency", slot: .center, title: .iconDesignerSourceNetwork,
              isSelectable: true, summary: .iconDesignerNetworkSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "latency" else { return .unavailable(.unavailable) }
        return .available(.center(.text(IconTextState(text: "42 ms", color: .primary, scale: 1))))
    }
}
