import Combine
import CoreWLAN
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiSummaryTests: XCTestCase {
    func testKnownFrequencyBandsAndUnknownChannel() {
        XCTAssertEqual(WiFiFrequencyBand(coreWLANBand: .band2GHz), .twoPointFourGHz)
        XCTAssertEqual(WiFiFrequencyBand(coreWLANBand: .band5GHz), .fiveGHz)
        XCTAssertEqual(WiFiFrequencyBand(coreWLANBand: .band6GHz), .sixGHz)
        XCTAssertNil(WiFiFrequencyBand(coreWLANBand: .bandUnknown))
    }

    func testMeasurementsKeepMissingValuesUnknownAndRespectConnectionState() {
        let name = "WiFiSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        func summary(_ wifi: WiFiStatus, connection: NetworkConnection = .wifi) -> String? {
            WiFiSummaryPresentation.measurements(wifi, connection: connection, localization: localization)
        }
        XCTAssertEqual(summary(WiFiStatus(state: .connected, rssi: -58, ssid: "Example Network", band: .fiveGHz)), "5 GHz · -58 dBm")
        XCTAssertEqual(summary(WiFiStatus(state: .connected, rssi: nil, ssid: "Example Network", band: .twoPointFourGHz)), "2.4 GHz")
        XCTAssertEqual(summary(WiFiStatus(state: .connected, rssi: -58, ssid: "Example Network")), "-58 dBm")
        XCTAssertNil(summary(WiFiStatus(state: .connected, rssi: 0, ssid: "Example Network")))
        XCTAssertNil(summary(WiFiStatus(state: .connected, rssi: nil, ssid: "Example Network")))
        XCTAssertNil(summary(WiFiStatus(state: .connected, rssi: -58, ssid: "Example Network", band: .fiveGHz), connection: .ethernet))
        for state in [WiFiState.off, .unavailable, .notAssociated, .noInternet, .shared, .temporary] {
            XCTAssertNil(summary(WiFiStatus(state: state, rssi: -58, ssid: "Example Network", band: .fiveGHz)))
        }
        localization.setPreference(.language(.german))
        XCTAssertEqual(summary(WiFiStatus(state: .connected, rssi: nil, ssid: "Example Network", band: .twoPointFourGHz)), "2,4 GHz")
    }

    func testVisibleAndAccessibleMeasurementsRequireNamedActiveWiFi() {
        let name = "WiFiSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let connected = WiFiStatus(state: .connected, rssi: -58, ssid: "Example Network", band: .fiveGHz)
        for connection in [NetworkConnection.offline, .other, .unknown, .ethernet] {
            XCTAssertNil(WiFiSummaryPresentation.summarySSID(connected, connection: connection))
            XCTAssertNil(WiFiSummaryPresentation.measurements(connected, connection: connection, localization: localization))
        }
        for access in [WiFiNameAccess.denied, .restricted, .notDetermined, .authorized] {
            for ssid in [nil, ""] as [String?] {
                let unnamed = WiFiStatus(state: .connected, rssi: -58, ssid: ssid, nameAccess: access, band: .fiveGHz)
                XCTAssertNil(WiFiSummaryPresentation.summarySSID(unnamed, connection: .wifi))
                XCTAssertNil(WiFiSummaryPresentation.measurements(unnamed, connection: .wifi, localization: localization))
            }
        }
        let hotspot = WiFiStatus(state: .hotspot, rssi: -58, ssid: "Example Hotspot", band: .fiveGHz)
        XCTAssertEqual(WiFiSummaryPresentation.summarySSID(hotspot, connection: .wifi), "Example Hotspot")
        XCTAssertEqual(WiFiSummaryPresentation.measurements(hotspot, connection: .wifi, localization: localization), "5 GHz · -58 dBm")
    }

    func testSummaryWaitsForFreshAuthorizedNameBeforePublishingMeasurements() {
        let name = "WiFiSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let awaitingName = WiFiStatus(
            state: .connected,
            rssi: -58,
            ssid: nil,
            nameAccess: .authorized,
            band: .fiveGHz
        )

        XCTAssertTrue(awaitingName.isAwaitingName)
        XCTAssertNil(WiFiSummaryPresentation.summarySSID(awaitingName, connection: .wifi))
        XCTAssertNil(WiFiSummaryPresentation.measurements(
            awaitingName,
            connection: .wifi,
            localization: localization
        ))

        let freshReading = WiFiStatus(
            state: .connected,
            rssi: -58,
            ssid: "Example Network",
            nameAccess: .authorized,
            band: .fiveGHz
        )
        XCTAssertFalse(freshReading.isAwaitingName)
        XCTAssertEqual(WiFiSummaryPresentation.summarySSID(freshReading, connection: .wifi), "Example Network")
        XCTAssertEqual(WiFiSummaryPresentation.measurements(
            freshReading,
            connection: .wifi,
            localization: localization
        ), "5 GHz · -58 dBm")
    }

    func testBandChangesDoNotInvalidateEitherIconOrItsSubscription() {
        func snapshot(_ band: WiFiFrequencyBand?) -> StatusSnapshot {
            StatusSnapshot(battery: .placeholder,
                           wifi: WiFiStatus(state: .connected, rssi: -58, band: band),
                           connection: .wifi, volume: .placeholder)
        }
        let first = snapshot(.fiveGHz)
        let second = snapshot(.sixGHz)
        XCTAssertNotEqual(first, second)
        let firstIcon = MenuBarStatus(snapshot: first)
        let secondIcon = MenuBarStatus(snapshot: second)
        XCTAssertEqual(firstIcon, secondIcon)
        XCTAssertNil(firstIcon.wifi.band)

        let source = PassthroughSubject<StatusSnapshot, Never>()
        var updates = 0
        let subscription = source.map { MenuBarStatus(snapshot: $0) }.removeDuplicates()
            .sink { _ in updates += 1 }
        source.send(first)
        source.send(second)
        source.send(snapshot(nil))
        XCTAssertEqual(updates, 1)
        subscription.cancel()

        XCTAssertEqual(
            StatusBarRenderKey(
                scene: makeIconPresentationScene(status: firstIcon), iconSize: 28,
                backingScale: 2, appearanceName: "aqua", phase: nil
            ),
            StatusBarRenderKey(
                scene: makeIconPresentationScene(status: secondIcon), iconSize: 28,
                backingScale: 2, appearanceName: "aqua", phase: nil
            )
        )
        XCTAssertEqual(
            DockIconRenderKey(
                scene: makeIconPresentationScene(status: firstIcon),
                backgroundStyle: .dark, pixelLength: DockIconRenderer.pixelSize
            ),
            DockIconRenderKey(
                scene: makeIconPresentationScene(status: secondIcon),
                backgroundStyle: .dark, pixelLength: DockIconRenderer.pixelSize
            )
        )
    }
}
