import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class CompactAudioLayoutTests: XCTestCase {
    func testOutputDeviceListIsVisibleWithoutDisclosureWhenLimitAllowsIt() throws {
        let limited = try render(alwaysShowAll: false, language: .english, dark: false)
        let all = try render(alwaysShowAll: true, language: .english, dark: false)
        XCTAssertEqual(limited.size.height, all.size.height, accuracy: 1)
        XCTAssertEqual(limited.descendantCount, all.descendantCount)
    }

    func testLongDeviceNamesAndLocalizedControlsFitPopover() throws {
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            let size = try render(alwaysShowAll: false, language: language, dark: true)
            XCTAssertGreaterThan(size.size.height, 200)
            XCTAssertLessThan(size.size.height, 450)
        }
    }

    func testSummaryNameFallbackAndCachedIconConsistency() {
        let named = AudioOutputDevice(id: 1, name: "Studio AirPods Pro", isCurrent: true)
        let unnamed = AudioOutputDevice(id: 1, name: nil, isCurrent: true)
        let defaults = UserDefaults(suiteName: "StatusTrioCoreTests.CompactAudio.Summary")!
        defer { defaults.removeTestSuite(named: "StatusTrioCoreTests.CompactAudio.Summary") }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        func summary(_ liveName: String?, _ devices: [AudioOutputDevice]) -> VolumePanelState {
            AudioPanelMapper.volume(
                VolumeStatus(scalar: 0.2, isMuted: false, deviceName: liveName, outputDevices: devices),
                controllerAvailable: true,
                localization: localization
            )
        }
        XCTAssertEqual(summary(nil, [named]).summary.title, named.name)
        XCTAssertEqual(summary("Live output", []).summary.title, "Live output")
        XCTAssertEqual(summary("Live output", [unnamed]).summary.title, "Live output")
        XCTAssertEqual(summary(named.name, [named]).summary.symbol, AudioPanelMapper.iconSource(for: named))
        XCTAssertEqual(summary("New live output", [named]).summary.title, "New live output")
        XCTAssertEqual(
            summary("New live output", [named]).summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil),
            "Do not label a new output with the cached previous device's icon"
        )
        XCTAssertEqual(summary(nil, []).summary.title, localization.string(.volumeNoDefaultDevice))
    }

    private func render(alwaysShowAll: Bool, language: AppLanguage, dark: Bool) throws -> (size: NSSize, descendantCount: Int) {
        let hosting = try makeHostingView(alwaysShowAll: alwaysShowAll, language: language, dark: dark)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        // Private AppKit backing/focus frames can extend outside the host on
        // macOS 15. Their bounds are not evidence of visible clipping; inspect
        // the rendered fixtures for wrapping and use hierarchy growth here.
        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_LAYOUT_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let state = alwaysShowAll ? "all" : "limited"
            try png.write(to: url.appendingPathComponent("audio-\(language.rawValue)-\(dark ? "dark" : "light")-\(state).png"))
        }
        return (size, descendantCount(hosting))
    }

    private func makeHostingView(
        alwaysShowAll: Bool,
        language: AppLanguage,
        dark: Bool
    ) throws -> NSHostingView<AnyView> {
        let suite = "StatusTrioCoreTests.CompactAudio.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: [language.rawValue])
        let settings = SettingsStore(defaults: defaults)
        settings.alwaysShowsAllOutputDevices = alwaysShowAll
        let devices = [
            AudioOutputDevice(id: 1, name: "Studio AirPods Pro with a very long device name", isCurrent: true, volume: 0.19, transport: .bluetooth),
            AudioOutputDevice(id: 2, name: "MacBook Pro Speakers", isCurrent: false, volume: 0.51, transport: .builtIn),
            AudioOutputDevice(id: 3, name: "External Display", isCurrent: false, transport: .hdmi)
        ]
        let view = AnyView(
            VStack(alignment: .leading, spacing: 12) {
                VolumeControlsView(
                    state: AudioPanelMapper.volume(
                        VolumeStatus(scalar: 0.19, isMuted: false, deviceName: devices[0].name, outputDevices: devices),
                        controllerAvailable: true,
                        deviceList: AudioOutputListPreferences(
                            order: settings.outputDeviceOrder,
                            visibleLimit: settings.visibleOutputDeviceLimit
                        ),
                        localization: localization
                    ),
                    actions: StatusPanelActions(),
                    scrollTargets: PopoverScrollTargets(),
                    onOpenSoundSettings: {}
                )
                Divider()
                PopoverFooterView(openSettings: {}, quit: {})
            }
            .padding(14)
            .frame(width: 330)
            .background(dark ? Color(white: 0.15) : Color(white: 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
        )
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return hosting
    }

    private func descendantCount(_ view: NSView) -> Int {
        view.subviews.reduce(0) { $0 + 1 + descendantCount($1) }
    }
}

extension CompactAudioLayoutTests {
    /// A live output must keep the volume slider usable while the device list
    /// is still loading; only a genuinely absent output may show the empty hint.
    func testUnloadedOutputListKeepsTheLiveSlider() throws {
        let suite = "StatusTrioCoreTests.CompactAudio.Unloaded.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        func state(
            scalar: Double?,
            devices: [AudioOutputDevice]
        ) -> VolumePanelState {
            AudioPanelMapper.volume(
                VolumeStatus(
                    scalar: scalar,
                    isMuted: false,
                    deviceName: devices.first(where: \.isCurrent)?.name,
                    outputDevices: devices
                ),
                controllerAvailable: scalar != nil,
                localization: localization
            )
        }

        let liveButUnloaded = state(
            scalar: 0.42,
            devices: []
        )
        let absent = state(scalar: nil, devices: [])
        let loaded = state(
            scalar: 0.42,
            devices: [AudioOutputDevice(id: 1, name: "Studio Display", isCurrent: true, volume: 0.42)]
        )

        XCTAssertTrue(liveButUnloaded.rows.isEmpty, "device rows have not loaded yet")
        XCTAssertTrue(liveButUnloaded.hasUsableOutput)
        XCTAssertFalse(absent.hasUsableOutput)
        XCTAssertTrue(liveButUnloaded.previewRows.isEmpty)
        XCTAssertNil(liveButUnloaded.deviceListPlaceholder)

        // The live row must be a real slider, not merely a non-zero height: it
        // hosts an NSSlider and registers the volume scroll target. A genuinely
        // absent output renders neither.
        let window = makeMarkerWindow()
        let targets = PopoverScrollTargets()
        let liveRow = host(
            liveButUnloaded,
            targets: targets,
            localization: localization,
            in: window
        )
        let slider = try XCTUnwrap(
            subview(of: NSSlider.self, in: liveRow),
            "a live output must keep the volume slider while its device list loads"
        )
        XCTAssertGreaterThan(slider.frame.width, 0)
        let marker = try XCTUnwrap(
            scrollTargetViews(in: liveRow).first,
            "the live volume slider must register a scroll target"
        )
        XCTAssertGreaterThan(marker.bounds.height, 0)
        let markerCenter = marker.convert(
            NSPoint(x: marker.bounds.midX, y: marker.bounds.midY),
            to: nil
        )
        XCTAssertEqual(targets.target(at: markerCenter, in: window), .volume)

        let absentRow = host(
            absent,
            targets: PopoverScrollTargets(),
            localization: localization,
            in: window
        )
        XCTAssertNil(
            subview(of: NSSlider.self, in: absentRow),
            "a genuinely absent output must show the empty hint, not a dead slider"
        )
        XCTAssertTrue(
            scrollTargetViews(in: absentRow).isEmpty,
            "the empty hint must not register a volume scroll target"
        )

        // Loading the device list keeps the same live slider under the rows.
        // The with-device and empty rows may share a height, so height itself
        // is not the evidence for the slider.
        let loadedRow = host(
            loaded,
            targets: PopoverScrollTargets(),
            localization: localization,
            in: window
        )
        XCTAssertNotNil(
            subview(of: NSSlider.self, in: loadedRow),
            "loading the device list must not replace the live slider"
        )
    }

    private func makeMarkerWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func host(
        _ state: VolumePanelState,
        targets: PopoverScrollTargets,
        localization: Localization,
        in window: NSWindow
    ) -> NSView {
        let hosting = NSHostingView(rootView: AnyView(
            VStack(alignment: .leading, spacing: 8) {
                VolumeControlsView(
                    state: state,
                    actions: StatusPanelActions(),
                    scrollTargets: targets,
                    onOpenSoundSettings: {}
                )
            }
            .frame(width: 330)
            .environmentObject(localization)
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 120)
        window.contentView?.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func subview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = subview(of: type, in: child) { return match }
        }
        return nil
    }

    private func scrollTargetViews(in view: NSView) -> [ScrollTargetView] {
        var result: [ScrollTargetView] = []
        if let marker = view as? ScrollTargetView {
            result.append(marker)
        }
        for child in view.subviews {
            result.append(contentsOf: scrollTargetViews(in: child))
        }
        return result
    }
}
