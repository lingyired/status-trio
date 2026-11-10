import Combine
import XCTest
@testable import StatusTrioCore

/// The settings pane edits the individual `@Published` icon settings; the
/// runtime renders from the V1 configuration. This pins the bridge: a settings
/// edit must produce a new `IconPresentationSettings` whose V1 configuration
/// actually changed, otherwise the menu bar keeps drawing a stale scene.
@MainActor
final class IconPresentationSettingsBridgeTests: XCTestCase {
    private func makeStore() throws -> SettingsStore {
        let suiteName = "StatusTrioCoreTests.IconPresentationBridge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return SettingsStore(defaults: defaults)
    }

    func testEverySettingsSurfaceIconEditChangesTheV1Configuration() throws {
        let store = try makeStore()
        var published: [IconPresentationSettings] = []
        let cancellable = store.iconPresentationPublisher.sink { published.append($0) }
        defer { cancellable.cancel() }

        let edits: [(name: String, apply: (SettingsStore) -> Void)] = [
            ("wifiSymbolScale", { $0.wifiSymbolScale = 1.15 }),
            ("batteryOnBatteryMarker", { $0.batteryOnBatteryMarker = .hidden }),
            ("batterySplitGapProgress", { $0.batterySplitGapProgress = true }),
            ("bluetoothIconColor", { $0.bluetoothIconColor = .primary }),
            ("inputSourceMarkerStyle", { $0.inputSourceMarkerStyle = .zhong }),
            ("connectionCenterSource", { $0.connectionCenterSource = .batteryPercentage }),
            ("ringStrokeStyle", { $0.ringStrokeStyle = .bold })
        ]

        for edit in edits {
            let previous = published.last
            edit.apply(store)
            guard let latest = published.last else {
                return XCTFail("\(edit.name) published nothing")
            }
            XCTAssertNotEqual(
                latest.iconConfiguration,
                previous?.iconConfiguration,
                "\(edit.name) must change the rendered V1 configuration"
            )
        }
    }

    func testPublishedConfigurationMatchesTheDerivedProjection() throws {
        let store = try makeStore()
        store.wifiSymbolScale = 1.35
        store.batteryOnBatteryMarker = .bolt
        store.bluetoothIconColor = .primary

        var latest: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        let value = try XCTUnwrap(latest)
        XCTAssertEqual(value.iconConfiguration, store.derivedIconConfigurationFromSettings())
        XCTAssertEqual(
            value.iconConfiguration.appearance.center.symbolScale,
            CenterAppearance.classic.symbolScale * store.connectionIconOptions.wifiScale,
            accuracy: 0.0001,
            "The centre size is classic × Wi-Fi scale (the palette divides by classic)"
        )
    }

    /// The legacy mapper always showed Wi-Fi when the chosen centre source was
    /// unavailable, so every non-network centre keeps a network fallback.
    func testNonNetworkCentreKeepsANetworkFallback() throws {
        let store = try makeStore()
        for source in [ConnectionCenterSource.inputSource, .bluetoothDevice, .batteryPercentage] {
            store.connectionCenterSource = source
            XCTAssertEqual(
                store.derivedIconConfigurationFromSettings().composition.center.fallback,
                .network,
                "\(source) must fall back to the network glyph"
            )
        }
    }
}
