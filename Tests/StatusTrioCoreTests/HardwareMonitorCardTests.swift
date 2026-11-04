import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
struct HardwareMonitorPresentationTests {
    @Test func unavailableMetricsKeepAllFourSlotsWithoutOldValuesOrProgress() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        for availability in [HardwareMetricAvailability.collecting, .unsupported, .temporarilyUnavailable, .stale] {
            let snapshot = fixture.snapshot(availability: availability)
            let tiles = HardwareMetricTilePresentation.tiles(snapshot: snapshot, localization: fixture.localization)
            #expect(tiles.map(\.metric) == [.cpu, .gpu, .temperature, .fan])
            #expect(tiles.allSatisfy { $0.valueText == "—" && $0.progress == nil })
            #expect(tiles[0].availability == availability)
            #expect(!tiles[0].accessibilityValue.isEmpty)
            #expect(!tiles[0].accessibilityValue.contains("99"))
        }
    }

    @Test func loadingFanIsDistinctFromConfirmedFanlessMac() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        let loading = HardwareMetricTilePresentation.tiles(snapshot: .empty, localization: fixture.localization)[3]
        #expect(loading.accessibilityValue == fixture.localization.string(.hardwareMonitorCollecting))
        let fanless = HardwareMetricTilePresentation.tiles(
            snapshot: .init(fanCount: 0), localization: fixture.localization
        )[3]
        #expect(fanless.valueText == "—")
        #expect(fanless.progress == nil)
        #expect(fanless.accessibilityValue == fixture.localization.string(.hardwareMonitorFanless))
    }

    @Test func fanShowsHighestCurrentRPMAndUsesThatFansOwnMaximum() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        var snapshot = fixture.snapshot()
        snapshot.samples[.fanRPM(index: 0)] = fixture.sample(value: 2_000, unit: .rpm, maximum: 9_000)
        snapshot.samples[.fanRPM(index: 1)] = fixture.sample(value: 4_200, unit: .rpm, maximum: 5_000)
        let fan = HardwareMetricTilePresentation.tiles(snapshot: snapshot, localization: fixture.localization)[3]
        #expect(fan.valueText == "4,200")
        #expect(fan.accessibilityValue == "4,200 RPM")
        #expect(fan.progress == 0.84)

        snapshot.samples[.fanRPM(index: 1)]?.metadata.maximum = nil
        let unknownMaximum = HardwareMetricTilePresentation.tiles(snapshot: snapshot, localization: fixture.localization)[3]
        #expect(unknownMaximum.valueText == "4,200")
        #expect(unknownMaximum.progress == nil)
    }

    @Test func actualZeroAndAboveScaleValuesRemainHonest() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        var snapshot = fixture.snapshot()
        snapshot.samples[.cpuTemperature] = fixture.sample(value: 125, unit: .celsius)
        snapshot.samples[.fanRPM(index: 0)] = fixture.sample(value: 0, unit: .rpm, maximum: 5_000)
        snapshot.samples.removeValue(forKey: .fanRPM(index: 1))
        let tiles = HardwareMetricTilePresentation.tiles(snapshot: snapshot, localization: fixture.localization)
        #expect(tiles[2].valueText == "125°C")
        #expect(tiles[2].progress == 1)
        #expect(tiles[2].help.contains("30–100°C"))
        #expect(tiles[2].help.contains("Average"))
        #expect(tiles[3].valueText == "0")
        #expect(tiles[3].progress == 0)
        #expect(tiles[3].accessibilityValue == "0 RPM")
    }

    @Test func invalidMeasuredValuesRemainUnavailable() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            let tile = HardwareMetricTilePresentation.make(
                metric: .cpu, sample: fixture.sample(value: invalid, unit: .percent), localization: fixture.localization
            )
            #expect(tile.valueText == "—")
            #expect(tile.progress == nil)
            #expect(tile.availability == .temporarilyUnavailable)
        }
    }

    @Test func onlyContinuousMeasuredProgressAnimates() {
        // SwiftUI's accessibilityReduceMotion / accessibilityReduceTransparency
        // environment values are read-only on this SDK, so the animation policy
        // is tested through the pure decision function the track calls.
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        func tile(_ value: Double, _ availability: HardwareMetricAvailability = .measured) -> HardwareMetricTilePresentation {
            HardwareMetricTilePresentation.make(
                metric: .cpu, sample: fixture.sample(value: value, unit: .percent, availability: availability),
                localization: fixture.localization
            )
        }
        let first = tile(20)
        let next = tile(70)
        #expect(!HardwareMetricTilePresentation.shouldAnimateProgress(from: nil, to: first, reduceMotion: false))
        #expect(HardwareMetricTilePresentation.shouldAnimateProgress(from: first, to: next, reduceMotion: false))
        #expect(!HardwareMetricTilePresentation.shouldAnimateProgress(from: first, to: next, reduceMotion: true))
        #expect(!HardwareMetricTilePresentation.shouldAnimateProgress(from: first, to: first, reduceMotion: false))
        for availability in [HardwareMetricAvailability.collecting, .unsupported, .temporarilyUnavailable, .stale] {
            let unavailable = tile(99, availability)
            #expect(!HardwareMetricTilePresentation.shouldAnimateProgress(from: first, to: unavailable, reduceMotion: false))
            #expect(!HardwareMetricTilePresentation.shouldAnimateProgress(from: unavailable, to: next, reduceMotion: false))
        }
    }

    @Test func reduceTransparencyRaisesTheCardFill() {
        #expect(HardwareMonitorCardView.backgroundOpacity(reduceTransparency: false) == 0.045)
        #expect(HardwareMonitorCardView.backgroundOpacity(reduceTransparency: true) == 0.10)
    }

    @Test func hardwareCopyExistsInEveryShippedLanguageWithoutFallback() throws {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        let keys = LocalizationKey.allCases.filter { $0.rawValue.hasPrefix("hardware.monitor.") }
        #expect(keys.count == 13)
        for language in AppLanguage.allCases {
            let bundle = try #require(Localization.resourceBundle(for: language))
            for key in keys {
                let translated = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                #expect(!translated.isEmpty && translated != key.rawValue,
                        "Missing \(key.rawValue) in \(language.rawValue)")
            }
        }
    }
}

/// Offscreen sizing only: no window is ever created or ordered on screen.
@MainActor
struct HardwareMonitorCardLayoutTests {
    @Test func fixedSizeAcrossLanguagesAppearancesAndAvailabilityStates() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        for language in AppLanguage.allCases {
            fixture.localization.setPreference(.language(language))
            for dark in [false, true] {
                for availability in [HardwareMetricAvailability.collecting, .measured, .unsupported, .temporarilyUnavailable, .stale] {
                    let host = makeHost(snapshot: fixture.snapshot(availability: availability), fixture: fixture, dark: dark)
                    #expect(abs(host.fittingSize.width - 302) < 0.5, "\(language) \(availability)")
                    #expect(abs(host.fittingSize.height - 84) < 0.5, "\(language) \(availability)")
                    #expect(host.window == nil)
                }
            }
        }
    }

    @Test func fanlessSnapshotKeepsTheSameSize() {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        let model = HardwareMonitorObservable(snapshot: .init(fanCount: 0))
        let host = NSHostingView(rootView: HardwareMonitorCardView(model: model)
            .environmentObject(fixture.localization)
            .frame(width: 302))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.width - 302) < 0.5)
        #expect(abs(host.fittingSize.height - 84) < 0.5)
        #expect(host.window == nil)
    }

    @Test func snapshotsRenderOffscreen() throws {
        let fixture = HardwareMonitorTestFixture()
        defer { fixture.cleanup() }
        let outputDirectory = ProcessInfo.processInfo.environment["STATUS_TRIO_HARDWARE_SNAPSHOTS"]
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            fixture.localization.setPreference(.language(language))
            for dark in [false, true] {
                for availability in [HardwareMetricAvailability.measured, .collecting, .stale] {
                    let host = makeHost(snapshot: fixture.snapshot(availability: availability), fixture: fixture, dark: dark)
                    let size = host.fittingSize
                    #expect(abs(size.width - 302) < 0.5)
                    #expect(abs(size.height - 84) < 0.5)
                    #expect(host.window == nil)
                    guard let outputDirectory else { continue }
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let filename = "hardware-\(language.rawValue)-\(dark ? "dark" : "light")-\(availability).png"
                    try png.write(to: directory.appendingPathComponent(filename))
                }
            }
        }
    }

    private func makeHost(
        snapshot: HardwareMetricsSnapshot,
        fixture: HardwareMonitorTestFixture,
        dark: Bool
    ) -> NSHostingView<AnyView> {
        let model = HardwareMonitorObservable(snapshot: snapshot)
        let host = NSHostingView(rootView: AnyView(HardwareMonitorCardView(model: model)
            .environmentObject(fixture.localization)
            .environment(\.locale, fixture.localization.resolvedLanguage.locale)
            .environment(\.layoutDirection, fixture.localization.resolvedLanguage.layoutDirection)
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: 302)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 302, height: 84)
        host.layoutSubtreeIfNeeded()
        return host
    }
}

@MainActor
private struct HardwareMonitorTestFixture {
    let suiteName = "StatusTrioCoreTests.HardwareMonitor.\(UUID().uuidString)"
    let defaults: UserDefaults
    let localization: Localization

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        localization = Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    func cleanup() { defaults.removeTestSuite(named: suiteName) }

    func sample(value: Double, unit: HardwareMetricUnit, maximum: Double? = nil,
                availability: HardwareMetricAvailability = .measured) -> HardwareMetricSample {
        .init(value: value, unit: unit, sampledAt: Date(), source: unit == .percent ? .mach : .smc,
              availability: availability, metadata: .init(maximum: maximum))
    }

    func snapshot(availability: HardwareMetricAvailability = .measured) -> HardwareMetricsSnapshot {
        .init(samples: [
            .cpuUsage: sample(value: 99, unit: .percent, availability: availability),
            .gpuUsage: sample(value: 8, unit: .percent, availability: availability),
            .cpuTemperature: sample(value: 62, unit: .celsius, availability: availability),
            .fanRPM(index: 0): sample(value: 2_450, unit: .rpm, maximum: 5_000, availability: availability),
            .fanRPM(index: 1): sample(value: 2_400, unit: .rpm, maximum: 6_000, availability: availability)
        ], fanCount: 2)
    }
}
