import AppKit
import Combine
import Testing
@testable import StatusTrioCore

/// A colour edited in the icon designer must reach the live menu bar scene
/// immediately, even when that scene's content is being held for source
/// availability.
@MainActor
struct IconDesignerMenuBarColorPropagationTests {
    @Test func heldAirPodsRingAdoptsANewOuterRingColourImmediately() async throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }

        // First establish a real last-good AirPods scene, then make only the
        // source temporarily stale so the presentation model enters its bounded
        // hold path.
        fixture.fixture.now = fixture.fixture.now.addingTimeInterval(1)
        fixture.fixture.batteryLevelsAvailable = false
        fixture.model.refreshSourceState()
        #expect(fixture.model.output.trace.outerRing.selectedSourceID == RingSource.airPodsBattery.rawValue)

        var configuration = fixture.settings.iconConfiguration
        let red = IconRGBA(red: 1, green: 0, blue: 0, alpha: 1)
        configuration.appearance.outerRing.color = .semanticOverrides([.primary: red])
        fixture.settings.updateIconConfiguration { $0 = configuration }
        await Task.yield()

        let colors = try #require(fixture.model.output.scene.outerRing?.segments.map(\.color))
        #expect(colors.allSatisfy { $0 == .custom(red) },
                "The live menu-bar scene must adopt an outer-ring colour immediately")
    }

    @Test func realIconOverrideKeepsSimulatedSamplesWhileLiveAirPodsIsHeld() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let session = IconDesignerPreviewSession()
        let bridge = IconDesignerRealIconOverrideBridge(
            session: session,
            settings: fixture.settings,
            iconPresentation: fixture.model
        )
        bridge.start()
        defer { bridge.stop() }

        fixture.fixture.now = fixture.fixture.now.addingTimeInterval(1)
        fixture.fixture.batteryLevelsAvailable = false
        fixture.model.refreshSourceState()
        session.mode = .simulated
        session.setAirPodsBattery(.left, 12)
        session.setAirPodsAvailability(.right, isAvailable: false)
        session.setAppliesToRealIcons(true)

        let simulatedLeft = try #require(fixture.model.output.scene.outerRing?.segments.first?.progress)
        #expect(abs(simulatedLeft - 0.12) < 1e-12,
                "Live hold work must not replace the simulated real-icon override")

        fixture.model.refreshSourceState()
        let afterSourceRefresh = try #require(fixture.model.output.scene.outerRing?.segments.first?.progress)
        #expect(abs(afterSourceRefresh - 0.12) < 1e-12,
                "A source-state refresh must leave the explicit simulated override in control")
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "StatusTrioCoreTests.IconDesignerMenuBarColor.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(
            primary: .airPodsBattery,
            fallback: .systemBattery
        )
        configuration.appearance.center.normalizedSizePercentage = 1.3
        configuration.appearance.outerRing.color = .semanticOverrides([
            .primary: IconRGBA(red: 0, green: 0.7, blue: 1, alpha: 1)
        ])
        defaults.set(
            try IconConfigurationCodec.encode(configuration),
            forKey: SettingsStore.iconConfigurationDefaultsKey
        )

        let settings = SettingsStore(defaults: defaults)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(PresentationFixtures.snapshot())
        let sourceFixture = MutableColorPropagationSourceFixture()
        var initialSettings: IconPresentationSettings?
        let initialSettingsCancellable = settings.iconPresentationPublisher.sink {
            initialSettings = $0
        }
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(
            try #require(initialSettings)
        )
        let model = IconPresentationViewModel(
            snapshot: snapshots.value,
            settings: preferences.value,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration,
                    now: sourceFixture.now
                )
            },
            resolveSourceSnapshot: { _ in sourceFixture.resolve() },
            now: { sourceFixture.now }
        )
        let preferenceCancellable = settings.iconPresentationPublisher
            .sink { preferences.send($0) }
        initialSettingsCancellable.cancel()
        model.start()
        return Fixture(
            suiteName: suiteName,
            defaults: defaults,
            settings: settings,
            snapshots: snapshots,
            preferences: preferences,
            preferenceCancellable: preferenceCancellable,
            model: model,
            fixture: sourceFixture
        )
    }

    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let settings: SettingsStore
        let snapshots: CurrentValueSubject<StatusSnapshot, Never>
        let preferences: CurrentValueSubject<IconPresentationSettings, Never>
        let preferenceCancellable: AnyCancellable
        let model: IconPresentationViewModel
        let fixture: MutableColorPropagationSourceFixture

        @MainActor
        func clear() {
            preferenceCancellable.cancel()
            model.stop()
            TestUserDefaults.removeSuite(named: suiteName)
        }
    }
}

@MainActor
private final class MutableColorPropagationSourceFixture {
    var now = Date(timeIntervalSince1970: 20_000)
    var batteryLevelsAvailable = true

    func resolve() -> IconSourceSnapshot {
        IconSourceSnapshot(
            availability: [
                RingSource.airPodsBattery.rawValue: batteryLevelsAvailable
                    ? .available : .unavailable(.temporarilyStale)
            ],
            airPodsBattery: AirPodsBatteryIconSnapshot(
                deviceAddress: "AA:BB:CC:DD:EE:FF",
                model: .airPods,
                main: nil,
                left: 80,
                right: 70,
                caseLevel: nil,
                observedAt: now
            )
        )
    }
}
