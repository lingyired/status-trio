import XCTest
@testable import StatusTrioCore

@MainActor
final class AirPodsRingColorTests: XCTestCase {
    private let red = IconRGBA(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = IconRGBA(red: 0, green: 1, blue: 0, alpha: 1)

    private func snapshot(
        main: Int? = nil,
        left: Int? = nil,
        right: Int? = nil
    ) -> AirPodsBatteryIconSnapshot {
        AirPodsBatteryIconSnapshot(
            deviceAddress: "AABBCCDDEEFF",
            model: .airPodsPro,
            main: main,
            left: left,
            right: right,
            caseLevel: nil,
            observedAt: Date()
        )
    }

    func testSingleLayoutUsesSingleColor() {
        let ring = AirPodsRingMapper.resolve(
            snapshot: snapshot(main: 80),
            behavior: .single,
            singleColor: .custom(red)
        )
        XCTAssertEqual(ring?.segments.map(\.color), [.custom(red)])
        XCTAssertEqual(ring?.segments.first?.progress, 0.8)
    }

    func testDualLayoutUsesLeftAndRightColors() {
        let ring = AirPodsRingMapper.resolve(
            snapshot: snapshot(left: 40, right: 60),
            behavior: .dual,
            leftColor: .custom(red),
            rightColor: .custom(green)
        )
        XCTAssertEqual(ring?.segments.map(\.color), [.custom(red), .custom(green)])
        XCTAssertEqual(ring?.segments.map(\.progress), [0.4, 0.6])
    }

    /// Only one earbud known: both arcs mirror the value but keep their own
    /// configured colours, and the ring is flagged partial.
    func testDualSingleEarMirrorsValueWithPerSideColors() {
        let ring = AirPodsRingMapper.resolve(
            snapshot: snapshot(left: 40),
            behavior: .dual,
            leftColor: .custom(red),
            rightColor: .custom(green)
        )
        XCTAssertEqual(ring?.segments.map(\.color), [.custom(red), .custom(green)])
        XCTAssertEqual(ring?.segments.map(\.progress), [0.4, 0.4])
        XCTAssertEqual(ring?.isPartial, true)
    }

    func testSettingsProjectAirPodsArcColorsIntoConfiguration() throws {
        let name = "AirPodsRingColorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)

        // Defaults keep the historical look.
        XCTAssertEqual(store.airPodsLeftArcColor, .systemBlue)
        XCTAssertEqual(store.airPodsRightArcColor, .primary)
        XCTAssertEqual(store.airPodsSingleArcColor, .primary)

        store.airPodsLeftArcColor = .custom(.init(hue: 0.5, saturation: 0.8, brightness: 0.9))
        store.airPodsRightArcColor = .systemBlue
        store.airPodsSingleArcColor = .primary

        let configuration = store.derivedIconConfigurationFromSettings()
        XCTAssertEqual(
            configuration.appearance.airPodsLeftArcColor.selection,
            .custom(.init(hue: 0.5, saturation: 0.8, brightness: 0.9))
        )
        XCTAssertEqual(configuration.appearance.airPodsRightArcColor.selection, .systemBlue)
        XCTAssertEqual(configuration.appearance.airPodsSingleArcColor.selection, .primary)
    }
}
