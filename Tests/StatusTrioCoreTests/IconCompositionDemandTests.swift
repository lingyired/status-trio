import XCTest
@testable import StatusTrioCore

@MainActor
final class IconCompositionDemandTests: XCTestCase {
    private static let snapshot = StatusSnapshot(
        battery: BatteryStatus(rawPercentage: 64, isPresent: true, isCharging: false,
                               isLowPowerMode: false, isConnectedToPower: false),
        wifi: WiFiStatus(state: .connected, rssi: -52),
        connection: .wifi,
        volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Built-in")
    )

    private let externalPrimary = IconContentBinding(
        pluginID: "test.primary", presentationID: "value")
    private let externalFallback = IconContentBinding(
        pluginID: "test.fallback", presentationID: "value")

    func testExternalFallbackStartsWithThePrimaryAndIsReleasedWhenThePrimaryRecovers() throws {
        let bindings = footerBindings()
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: Self.snapshot, audioIcon: nil),
            sources: .empty)

        // Cold start: neither package has a reading yet. Both bindings must be
        // subscribed, or the fallback's watcher can never start and the slot
        // stays blank even after the fallback's producer writes data.
        let cold = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: .classic,
            bindings: bindings,
            registry: try registry(primary: .unavailable(.unavailable),
                                   fallback: .unavailable(.unavailable))
        )
        XCTAssertNil(cold.trace.footer.binding)
        XCTAssertEqual(cold.demand.subscribedBindings, [externalPrimary, externalFallback])
        XCTAssertTrue(cold.demand.selectedBindings.isEmpty)

        // The fallback now has data while the primary is still unavailable.
        let fallbackOnly = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: .classic,
            bindings: bindings,
            registry: try registry(primary: .unavailable(.unavailable),
                                   fallback: .available(.footer(dots(active: 2))))
        )
        XCTAssertEqual(fallbackOnly.trace.footer.role, .fallback)
        XCTAssertEqual(fallbackOnly.demand.selectedBindings, [externalFallback])
        XCTAssertEqual(fallbackOnly.demand.subscribedBindings, [externalPrimary, externalFallback])

        // The primary recovers and draws; the fallback no longer needs a watcher.
        let recovered = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: .classic,
            bindings: bindings,
            registry: try registry(primary: .available(.footer(dots(active: 4))),
                                   fallback: .available(.footer(dots(active: 2))))
        )
        XCTAssertEqual(recovered.trace.footer.role, .primary)
        XCTAssertEqual(recovered.demand.selectedBindings, [externalPrimary])
        XCTAssertEqual(recovered.demand.subscribedBindings, [externalPrimary])
    }

    func testExternalFooterIsNotReportedAsVolume() throws {
        let bindings = footerBindings()
        var inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: Self.snapshot, audioIcon: nil),
            sources: .empty)
        // The old individual preference says volume; the footer is external.
        inputs.system.bottomIndicatorSource = .volume

        let first = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: .classic,
            bindings: bindings,
            registry: try registry(primary: .available(.footer(dots(active: 2))),
                                   fallback: .available(.footer(dots(active: 2))))
        )
        XCTAssertEqual(first.scene.bottomIndicatorSource, .hidden)

        var second = first.scene
        second = IconSceneState(
            outerRing: second.outerRing,
            center: second.center,
            footer: dots(active: 3),
            statusColors: second.statusColors,
            bluetoothIconColor: second.bluetoothIconColor,
            bottomIndicatorSource: second.bottomIndicatorSource
        )
        XCTAssertFalse(
            second.isVolumeValueChange(from: first.scene),
            "an external footer update must never be coalesced as a continuous volume change"
        )
    }

    func testResolvedBuiltinFooterStillReportsItsOwnSource() throws {
        var inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: Self.snapshot, audioIcon: nil),
            sources: .empty)
        inputs.system.bottomIndicatorSource = .battery

        let output = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: .classic,
            bindings: IconSlotBindingsV1(
                schemaVersion: 1,
                outerRing: .init(primary: nil),
                center: .init(primary: nil),
                footer: .init(primary: IconContentLegacyAdapter.binding(for: FooterSource.systemVolume))
            )
        )
        XCTAssertEqual(output.trace.footer.binding?.pluginID, "builtin.system-volume")
        XCTAssertEqual(output.scene.bottomIndicatorSource, .volume)
    }

    // MARK: - Fixtures

    private func footerBindings() -> IconSlotBindingsV1 {
        IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: nil),
            center: .init(primary: nil),
            footer: .init(primary: externalPrimary, fallback: externalFallback)
        )
    }

    private func dots(active: Int) -> FooterState {
        .dots(DotsState(count: 4, activeCount: active, color: .primary))
    }

    private func registry(
        primary: SourceResult<IconContentPayload>,
        fallback: SourceResult<IconContentPayload>
    ) throws -> IconContentPluginRegistry {
        try IconContentPluginRegistry(plugins: [
            TestIconContentPlugin(
                descriptor: .init(id: "test.primary", presentations: [
                    .init(id: "value", slot: .footer, title: .settingsLocalPluginsTitle, isSelectable: true)
                ]),
                result: primary),
            TestIconContentPlugin(
                descriptor: .init(id: "test.fallback", presentations: [
                    .init(id: "value", slot: .footer, title: .settingsLocalPluginsTitle, isSelectable: true)
                ]),
                result: fallback)
        ])
    }
}
