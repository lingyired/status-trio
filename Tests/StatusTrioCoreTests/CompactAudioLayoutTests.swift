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
                    scrollTargets: PopoverScrollTargets()
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
