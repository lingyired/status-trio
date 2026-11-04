import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

final class AirPodsInlineControlsTests: XCTestCase {
    @MainActor
    func testRefreshPublishesReadyGroupsBeforeAdaptiveCompletesAndIgnoresCancelledUpdates() async throws {
        let model = AirPodsSystemControlsModel(deviceID: .init(id: 42, uid: "test"), deviceName: "Test")
        let ready = AirPodsSystemSnapshot(conversation: [.init(title: "On", selected: true)],
                                         spatial: [.init(title: "Fixed", selected: true)],
                                         conversationLoaded: true, spatialLoaded: true)
        var finish: CheckedContinuation<Void, Never>?
        model.refresh { publish in
            publish(ready)
            await withCheckedContinuation { finish = $0 }
            var late = ready
            late.adaptive = 50
            late.loaded = true
            publish(late)
            return late
        }
        for _ in 0..<100 where finish == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(finish)
        XCTAssertTrue(model.busy)
        XCTAssertEqual(model.snapshot, ready, "Ready controls must publish while Adaptive is pending")
        model.stop()
        finish?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.snapshot, ready, "Dismissed reads must not publish late results")
        XCTAssertFalse(model.busy)
    }

    func testAirPodsControlsHaveNoSystemUINavigation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Audio/AirPodsSpatialControls.swift", "Audio/AirPodsSystemControls.swift", "UI/AirPodsSystemControlsView.swift", "UI/OutputDeviceRow.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/StatusTrioCore/" + file), encoding: .utf8)
            for forbidden in ["AXUIElement", "AXIsProcessTrusted", "NSWorkspace.shared.open", "automationActivity", "closeConnection()"] {
                XCTAssertFalse(source.contains(forbidden), "\(file) must not navigate system UI: \(forbidden)")
            }
        }
    }

    @MainActor
    func testMissingNativeSymbolStillProducesFallbackArtwork() {
        let image = AirPodsControlSymbols.image("status.trio.nonexistent.symbol")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    @MainActor
    func testFailedAdaptiveWritePreservesOtherGroupsButRouteChangeClearsIdentity() async throws {
        let options = [AirPodsSystemOption(title: "On", selected: true)]
        let snapshot = AirPodsSystemSnapshot(conversation: options, spatial: options, adaptive: 50,
                                            loaded: true)
        let model = AirPodsSystemControlsModel(deviceID: .init(id: 42, uid: "test"), deviceName: "Test", snapshot: snapshot)
        model.run(.adaptive) { throw AirPodsSystemControlError.unavailable }
        for _ in 0..<20 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.snapshot.adaptive)
        XCTAssertEqual(model.snapshot.conversation, options)
        XCTAssertEqual(model.snapshot.spatial, options)
        model.run(.option(.conversation)) { throw AirPodsSystemControlError.routeChanged }
        for _ in 0..<20 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.snapshot, AirPodsSystemSnapshot())
        XCTAssertEqual(model.errorKey, .airPodsRouteChanged)
    }

    @MainActor
    func testTransportCancellationEndsBusyState() async throws {
        let model = AirPodsSystemControlsModel(deviceID: .init(id: 42, uid: "test"), deviceName: "Test")
        model.run(.refresh) { throw CancellationError() }
        for _ in 0..<20 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.errorKey, .airPodsUnavailable)
    }

    @MainActor
    func testNativeSliderFitsMenuWidthAndKeepsAccessibleSteppedValues() async throws {
        let suite = "AirPodsInlineControlsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let row = PanelAudioDeviceRow(
            key: .init(id: 42, uid: "AA-BB-CC-DD-EE-FF:output"), name: "AirPods Pro",
            symbol: .symbol(name: "airpodspro", variableValue: nil, fallback: nil),
            selected: true, enabled: true, accessibilityLabel: "AirPods Pro",
            listeningMode: .init(availableModes: [.transparency, .adaptive, .noiseCancellation], selectedMode: .adaptive),
            supportsAirPodsSystemControls: true)
        let model = AirPodsSystemControlsModel(deviceID: row.key, deviceName: row.name,
            snapshot: .init(conversation: [.init(title: "Off", selected: false), .init(title: "On", selected: true)],
                            spatial: [.init(title: "Off", selected: false), .init(title: "Fixed", selected: true),
                                      .init(title: "Head Tracked", selected: false)], adaptive: 50, loaded: true))
        for dark in [false, true] {
            let host = NSHostingView(rootView: AirPodsSystemControlsView(model: model, listeningMode: row.listeningMode)
                .padding(14).frame(width: 300)
                .background(dark ? Color(white: 0.16) : Color(white: 0.93))
                .environmentObject(localization).environment(\.colorScheme, dark ? .dark : .light))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            var pending = host.subviews
            var sliders: [NSSlider] = []
            while let view = pending.popLast() {
                if let slider = view as? NSSlider { sliders.append(slider) }
                pending.append(contentsOf: view.subviews)
            }
            XCTAssertEqual(sliders.count, 1)
            let slider = try XCTUnwrap(sliders.first)
            XCTAssertEqual(slider.doubleValue, 50)
            XCTAssertEqual(slider.numberOfTickMarks, 11)
            XCTAssertTrue(slider.allowsTickMarkValuesOnly)
            XCTAssertEqual(slider.accessibilityValueDescription(), "50%")
            XCTAssertGreaterThan(slider.bounds.width, 180)
            XCTAssertLessThan(host.bounds.height, 550, "Inline controls must fit a compact menu section")
            if let directory = ProcessInfo.processInfo.environment["AIRPODS_PREVIEW_DIR"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("airpods-inline-\(dark ? "dark" : "light").png"))
                // PR comparison uses fixture state, not hardware access. Keep the
                // unverified Adaptive slider absent from the published preview.
                var beforeRow = row
                beforeRow.supportsAirPodsSystemControls = false
                var headerRow = beforeRow
                headerRow.listeningMode = nil
                let preview = AirPodsSystemControlsModel(deviceID: row.key, deviceName: row.name,
                    snapshot: .init(
                        conversation: [.init(title: "Off", selected: false, symbol: "person.fill"),
                                       .init(title: "On", selected: true, symbol: "person.wave.2.fill")],
                        spatial: [.init(title: "Off", selected: false, symbol: "person.fill"),
                                  .init(title: "Fixed", selected: false, symbol: "person.spatialaudio.stereo.fill"),
                                  .init(title: "Head Tracked", selected: true, symbol: "spatialize-stereo-head-tracked")],
                        loaded: true))
                let before = AnyView(OutputDeviceRow(state: beforeRow, onSelect: {}, onSelectListeningMode: { _ in }))
                let after = AnyView(VStack(alignment: .leading, spacing: 2) {
                    OutputDeviceRow(state: headerRow, onSelect: {}, onSelectListeningMode: { _ in })
                    AirPodsSystemControlsView(model: preview, listeningMode: row.listeningMode)
                })
                for (name, view) in [("before", before), ("after", after)] {
                    let comparison = NSHostingView(rootView: view.padding(14).frame(width: 300)
                        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
                        .environmentObject(localization).environment(\.colorScheme, dark ? .dark : .light))
                    comparison.appearance = host.appearance
                    comparison.frame = NSRect(origin: .zero, size: comparison.fittingSize)
                    comparison.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(60))
                    comparison.frame = NSRect(origin: .zero, size: comparison.fittingSize)
                    comparison.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(comparison.bitmapImageRepForCachingDisplay(in: comparison.bounds))
                    comparison.cacheDisplay(in: comparison.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: directory)
                        .appendingPathComponent("airpods-\(name)-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
