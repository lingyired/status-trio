import XCTest
@testable import StatusTrioCore

final class IconPreviewTransitionTests: XCTestCase {
    func testTransitionDurationMeetsShortMotionContract() {
        XCTAssertGreaterThanOrEqual(IconPreviewTransitionState.duration, 0.20)
        XCTAssertLessThanOrEqual(IconPreviewTransitionState.duration, 0.24)
        XCTAssertLessThanOrEqual(IconPreviewTransitionState.reduceMotionDuration, 0.10)
    }

    func testOnlyChangedCenterCreatesBriefOutgoingLayer() {
        var transition = IconPreviewTransitionState()
        let old = center("wifi")
        let new = center("network")
        XCTAssertNotEqual(old, new)
        let start = Date(timeIntervalSince1970: 100)
        transition.begin(from: old, oldIdentity: identity("source-a"), to: identity("source-b"), reduceMotion: false, now: start)
        XCTAssertEqual(transition.outgoingCenter, old)
        XCTAssertEqual(transition.progress(at: start.addingTimeInterval(IconPreviewTransitionState.duration / 2)), 0.5, accuracy: 0.001)
        XCTAssertFalse(transition.isActive(at: start.addingTimeInterval(IconPreviewTransitionState.duration + 0.001)))
    }

    func testRapidChangeReplacesOldLayerAndStaleCompletionCannotClearNewTransition() {
        var transition = IconPreviewTransitionState()
        let start = Date(timeIntervalSince1970: 100)
        transition.begin(from: center("wifi"), oldIdentity: identity("source-a"), to: identity("source-b"), reduceMotion: false, now: start)
        let staleGeneration = transition.generation
        let secondStart = start.addingTimeInterval(0.04)
        let next = center("headphones")
        XCTAssertNotEqual(center("network"), next)
        transition.begin(from: center("network"), oldIdentity: identity("source-b"), to: identity("source-c"), reduceMotion: false, now: secondStart)
        transition.clear(generation: staleGeneration)
        XCTAssertEqual(transition.outgoingCenter, center("network"))
        XCTAssertTrue(transition.isActive(at: secondStart))
    }

    func testReduceMotionUsesShortFadeAndUnchangedCenterNeverLeavesAnOverlay() {
        var transition = IconPreviewTransitionState()
        let now = Date(timeIntervalSince1970: 100)
        transition.begin(from: center("wifi"), oldIdentity: identity("source-a"), to: identity("source-b"), reduceMotion: true, now: now)
        XCTAssertEqual(transition.activeDuration, 0.08)
        XCTAssertEqual(transition.outgoingCenter, center("wifi"))
        XCTAssertEqual(transition.progress(at: now.addingTimeInterval(0.04)), 0.5, accuracy: 0.001)
        transition.begin(from: center("wifi"), oldIdentity: identity("source-a"), to: identity("source-a"), reduceMotion: false, now: now)
        XCTAssertNil(transition.outgoingCenter)
    }

    func testConfiguredIdentityIgnoresLiveNetworkSymbolAndStatusButTracksSourceTargetAndStyle() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .connectedBluetoothDevice)
        let first = IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: "aa:bb:cc:dd:ee:ff")

        // A Wi-Fi/Ethernet or status-derived symbol change is deliberately not an input to identity.
        let liveNetworkWifiCenter = center("wifi")
        let liveNetworkEthernetCenter = center("cable.connector")
        XCTAssertNotEqual(liveNetworkWifiCenter, liveNetworkEthernetCenter)
        XCTAssertEqual(first, IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: "AA:BB:CC:DD:EE:FF"))

        configuration.appearance.center.effectiveSymbolScale = 2
        XCTAssertEqual(first, IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: "aa:bb:cc:dd:ee:ff"))

        configuration.appearance.center.effectiveSymbolScale = nil
        configuration.appearance.center.symbolScale = 2.5
        XCTAssertEqual(first, IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: "aa:bb:cc:dd:ee:ff"))

        configuration.composition.center.primary = .bluetoothAudioOutput
        XCTAssertNotEqual(first, IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: "aa:bb:cc:dd:ee:ff"))
        configuration.composition.center.primary = .network
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "cable.connector"
        XCTAssertNotEqual(first, IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: "aa:bb:cc:dd:ee:ff"))
    }

    func testSizeChangeUpdatesLatestCenterWithoutTransitionButSourceChangeStillTransitions() {
        var driver = IconPreviewTransitionDriver()
        var configuration = IconConfigurationV1.classic
        let initialIdentity = IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: nil)
        let initialScale = configuration.appearance.center.effectiveSymbolScale
            ?? configuration.appearance.center.symbolScale
        let initialCenter = center("wifi", scale: initialScale)
        driver.setInitial(center: initialCenter, identity: initialIdentity)

        configuration.appearance.center.effectiveSymbolScale = 2.5
        let resizedIdentity = IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: nil)
        let resizedCenter = center("wifi", scale: 2.5)
        driver.update(center: resizedCenter, identity: resizedIdentity, reduceMotion: false,
                      now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(driver.identity, resizedIdentity)
        XCTAssertEqual(driver.latestCenter, resizedCenter)
        XCTAssertNil(driver.transition.outgoingCenter)

        configuration.composition.center.primary = .bluetoothAudioOutput
        let bluetoothIdentity = IconPreviewCenterIdentity.make(configuration: configuration, selectedBluetoothAddress: nil)
        let bluetoothCenter = center("headphones", scale: 2.5)
        driver.update(center: bluetoothCenter, identity: bluetoothIdentity, reduceMotion: false,
                      now: Date(timeIntervalSince1970: 100.1))
        XCTAssertEqual(driver.latestCenter, bluetoothCenter)
        XCTAssertEqual(driver.transition.outgoingCenter, resizedCenter)
    }

    func testSameConfiguredIdentityUpdatesPreviousPatternWithoutStartingTransition() {
        var driver = IconPreviewTransitionDriver()
        let identity = IconPreviewCenterIdentity(source: "network", target: "configured-source", style: "scale:1")
        let oldPattern = center("wifi")
        let currentPattern = center("cable.connector")
        driver.setInitial(center: oldPattern, identity: identity)
        driver.update(center: currentPattern, identity: identity, reduceMotion: false,
                      now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(driver.latestCenter, currentPattern)
        XCTAssertNil(driver.transition.outgoingCenter)

        let changedIdentity = IconPreviewCenterIdentity(source: "bluetooth", target: "configured-source", style: "scale:1")
        driver.update(center: center("headphones"), identity: changedIdentity, reduceMotion: false,
                      now: Date(timeIntervalSince1970: 100.1))
        XCTAssertEqual(driver.transition.outgoingCenter, currentPattern)
    }

    private func identity(_ source: String) -> IconPreviewCenterIdentity {
        IconPreviewCenterIdentity(source: source, target: "fixture", style: "scale:1")
    }

    private func center(_ name: String, scale: Double = 1) -> CenterState {
        .symbol(IconSymbolState(source: .symbol(name: name, variableValue: nil, fallback: nil),
                                color: .primary, scale: scale))
    }
}
