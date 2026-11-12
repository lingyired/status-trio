import Foundation
import XCTest
@testable import StatusTrioCore

/// How the join flow reaches the panel: row actions and labels, the password
/// form, and the progress or failure line.
@MainActor
final class WiFiJoinPanelStateTests: XCTestCase {
    private let home = WiFiNetworkIdentity(ssid: "Home", security: .wpa2Personal)

    private func makeLocalization() -> Localization {
        let suite = "WiFiJoinPanelStateTests.\(UUID().uuidString)"
        return Localization(defaults: UserDefaults(suiteName: suite) ?? .standard, preferredLanguages: ["en"])
    }

    private func network(_ ssid: String, _ security: WiFiSecurityKind, connected: Bool = false) -> WiFiNetwork {
        WiFiNetwork(
            identity: WiFiNetworkIdentity(ssid: ssid, security: security),
            candidates: [WiFiNetworkCandidate(ssid: ssid, bssid: "01", rssi: -50, channel: 36, security: security)],
            connectedBSSID: connected ? "01" : "ff",
            isKnown: false
        )
    }

    private func state(
        networks: [WiFiNetwork] = [],
        joinState: WiFiJoinState = .idle,
        joinsInApp: Bool = true,
        localization: Localization
    ) -> WiFiPanelState {
        PanelDetailMapper.wifi(
            status: WiFiStatus(state: .connected, rssi: -48, ssid: "Office", nameAccess: .authorized),
            networks: networks,
            details: .unavailable,
            listState: .ready,
            joinState: joinState,
            joinsInApp: joinsInApp,
            localization: localization
        )
    }

    func testRowsCarryTheirActionAndNameItInTheAccessibilityLabel() {
        let localization = makeLocalization()
        let rows = state(
            networks: [
                network("Office", .wpa2Personal, connected: true),
                network("Cafe", .wpa3Personal),
                network("Corp", .wpa2Enterprise)
            ],
            localization: localization
        )
        let all = rows.knownRows + rows.otherRows
        let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

        XCTAssertEqual(byName["Office"]?.action, WiFiNetworkRowAction.none)
        XCTAssertEqual(byName["Office"]?.isActionable, false)
        XCTAssertEqual(byName["Cafe"]?.action, .join)
        XCTAssertEqual(byName["Cafe"]?.joins, true)
        XCTAssertEqual(byName["Corp"]?.action, .openSettings)
        XCTAssertEqual(byName["Corp"]?.opensSettings, true)

        XCTAssertTrue(byName["Cafe"]?.accessibilityLabel.hasSuffix(localization.string(.wifiActionJoin)) == true)
        XCTAssertTrue(
            byName["Corp"]?.accessibilityLabel.hasSuffix(localization.string(.wifiActionOpenSettings)) == true
        )
        XCTAssertEqual(
            byName["Office"]?.accessibilityLabel,
            "Office, \(localization.string(.wifiConnected))"
        )
    }

    func testWithTheOptInOffEveryRowOpensSettingsAndTheHintSaysSo() {
        let localization = makeLocalization()
        let off = state(
            networks: [network("Cafe", .wpa3Personal), network("Lobby", .open)],
            joinsInApp: false,
            localization: localization
        )
        XCTAssertEqual((off.knownRows + off.otherRows).map(\.action), [.openSettings, .openSettings])
        XCTAssertFalse(off.joinsInApp)

        let on = state(networks: [network("Cafe", .wpa3Personal)], localization: localization)
        XCTAssertEqual(on.otherRows.map(\.action), [.join])
        XCTAssertTrue(on.joinsInApp)
    }

    func testIdleStateHasNoFormOrStatus() {
        let result = state(localization: makeLocalization())
        XCTAssertNil(result.joinPrompt)
        XCTAssertNil(result.joinStatus)
        XCTAssertFalse(result.isJoining)
    }

    func testNeedsPasswordShowsTheFormNamedForTheNetwork() {
        let localization = makeLocalization()
        let first = state(joinState: .needsPassword(home, retry: false), localization: localization)
        XCTAssertEqual(first.joinPrompt?.key, home)
        XCTAssertEqual(first.joinPrompt?.title, "Password for “Home”")
        XCTAssertNil(first.joinPrompt?.errorText)
        XCTAssertNil(first.joinStatus)

        let retry = state(joinState: .needsPassword(home, retry: true), localization: localization)
        XCTAssertEqual(retry.joinPrompt?.errorText, localization.string(.wifiJoinWrongPassword))
    }

    func testJoiningIsBusyAndMakesRowsInert() {
        let result = state(joinState: .joining(home), localization: makeLocalization())
        XCTAssertEqual(result.joinStatus, WiFiJoinStatus(text: "Joining “Home”…", isBusy: true))
        XCTAssertTrue(result.isJoining)
        XCTAssertNil(result.joinPrompt)
    }

    func testFailuresAreAQuietNonBusyLine() {
        let localization = makeLocalization()
        let range = state(joinState: .failed(home, .notInRange), localization: localization)
        XCTAssertEqual(range.joinStatus, WiFiJoinStatus(text: "“Home” is out of range.", isBusy: false))
        XCTAssertFalse(range.isJoining)

        for failure in [WiFiJoinFailure.rejected, .unavailable] {
            let result = state(joinState: .failed(home, failure), localization: localization)
            XCTAssertEqual(result.joinStatus, WiFiJoinStatus(text: "Couldn’t join “Home”.", isBusy: false))
        }
    }

    /// The panel state is plain data about the network; there is nowhere for a
    /// passphrase to live in it.
    func testJoinStateNamesTheNetworkOnly() {
        let mirror = Mirror(reflecting: WiFiJoinState.needsPassword(home, retry: true))
        let payload = String(describing: mirror.children.map(\.value))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("password"))
    }
}
