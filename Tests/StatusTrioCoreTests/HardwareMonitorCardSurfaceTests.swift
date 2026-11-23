import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Pins the neutral hardware-monitor card surface (#296 solid branch). The
/// glass and material branches must stay byte-for-byte identical to the shared
/// panel card surface; only the opaque solid branch uses these numbers.
@MainActor
final class HardwareMonitorCardSurfaceTests: XCTestCase {
    private func channel(_ value: Double) -> Int { Int((value * 255).rounded()) }

    private func assertRGB(_ color: PowerCardRGB, _ r: Int, _ g: Int, _ b: Int,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(channel(color.red), r, "red", file: file, line: line)
        XCTAssertEqual(channel(color.green), g, "green", file: file, line: line)
        XCTAssertEqual(channel(color.blue), b, "blue", file: file, line: line)
    }

    func testDarkPaletteMatchesSpec() {
        let v = HardwareMonitorCardSurface.values(scheme: .dark)
        assertRGB(v.background, 0x29, 0x2B, 0x2F)
        assertRGB(v.border, 0x39, 0x3C, 0x42)
        assertRGB(v.hover, 0x32, 0x35, 0x3A)
        assertRGB(v.progressTrack, 0x41, 0x44, 0x4A)
    }

    func testLightPaletteMatchesSpec() {
        let v = HardwareMonitorCardSurface.values(scheme: .light)
        assertRGB(v.background, 0xF2, 0xF3, 0xF5)
        assertRGB(v.border, 0xDF, 0xE2, 0xE6)
        assertRGB(v.hover, 0xE9, 0xEB, 0xEF)
        assertRGB(v.progressTrack, 0xDD, 0xE0, 0xE4)
    }

    /// The complaint was a blue-grey cast. Every channel of every token has to
    /// sit within a hair of the others: neutral, not cool.
    func testPaletteIsNeutralNotBlue() {
        for scheme: ColorScheme in [.light, .dark] {
            let v = HardwareMonitorCardSurface.values(scheme: scheme)
            for token in [v.background, v.border, v.hover, v.progressTrack] {
                let values = [token.red, token.green, token.blue]
                let spread = (values.max() ?? 0) - (values.min() ?? 0)
                XCTAssertLessThan(spread, 0.045, "token is neutral in \(scheme)")
            }
        }
    }

    func testLightSolidCardIsLowContrastGreyWhite() {
        let v = HardwareMonitorCardSurface.values(scheme: .light)
        // Light: a pale grey that is dimmer than paper white but still bright.
        XCTAssertLessThan(channel(v.background.red), 0xFA)
        XCTAssertGreaterThan(channel(v.background.red), 0xDD)
        // Hover darkens the light card; it must not lighten it.
        XCTAssertLessThan(channel(v.hover.red), channel(v.background.red))
    }

    func testTrendAreaFillThinsOnlyInSolid() {
        let glass = HardwareMonitorCardSurface.trendAreaFillOpacities(cardStyle: .glass)
        let material = HardwareMonitorCardSurface.trendAreaFillOpacities(cardStyle: .material)
        let solid = HardwareMonitorCardSurface.trendAreaFillOpacities(cardStyle: .solid)
        XCTAssertEqual(glass.top, 0.78)
        XCTAssertEqual(glass.bottom, 0.38)
        XCTAssertEqual(material.top, 0.78)
        XCTAssertEqual(material.bottom, 0.38)
        XCTAssertLessThan(solid.top, glass.top)
        XCTAssertLessThan(solid.bottom, glass.bottom)
    }

    // MARK: - Offscreen rendering

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> PixelBuffer {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return try PixelBuffer(image: image)
    }

    private func assertPixel(_ pixel: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
                             _ token: PowerCardRGB, tolerance: Int = 2,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Int(pixel.red), channel(token.red), accuracy: tolerance, "red", file: file, line: line)
        XCTAssertEqual(Int(pixel.green), channel(token.green), accuracy: tolerance, "green", file: file, line: line)
        XCTAssertEqual(Int(pixel.blue), channel(token.blue), accuracy: tolerance, "blue", file: file, line: line)
    }

    func testSolidCardRendersNeutralFillAndRim() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let palette = HardwareMonitorCardSurface.values(scheme: scheme)
            let view = Color.clear
                .frame(width: 120, height: 60)
                .hardwareMonitorCardSurface(cornerRadius: 12)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.solid)
                .environment(\.colorScheme, scheme)
            let buffer = try render(view, width: 120, height: 60)
            assertPixel(buffer.rgba(x: 60, y: 30), palette.background)
            let rim = buffer.rgba(x: 0, y: 30)
            XCTAssertGreaterThan(rim.alpha, 200, "the rim is painted in \(scheme)")
            XCTAssertNotEqual(rim.red, buffer.rgba(x: 60, y: 30).red, "rim differs from fill")
        }
    }

    func testSolidHoverUsesPaletteHoverFill() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let palette = HardwareMonitorCardSurface.values(scheme: scheme)
            let view = Color.clear
                .frame(width: 120, height: 60)
                .hardwareMonitorCardSurface(cornerRadius: 12, hovered: true)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.solid)
                .environment(\.colorScheme, scheme)
            let buffer = try render(view, width: 120, height: 60)
            assertPixel(buffer.rgba(x: 60, y: 30), palette.hover)
        }
    }

    /// Glass and material must delegate to the shared panel card surface; the
    /// pixels have to match the direct panelCardSurface call exactly.
    /// Liquid Glass must still delegate to the shared panel card surface.
    func testGlassMatchesSharedPanelSurface() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let viaHardware = Color.clear.frame(width: 120, height: 60)
                .hardwareMonitorCardSurface(PowerCardSurface.silver(.connected), cornerRadius: 12)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.glass)
                .environment(\.colorScheme, scheme)
                .background(Color(white: 0.5))
            let viaPanel = Color.clear.frame(width: 120, height: 60)
                .panelCardSurface(PowerCardSurface.silver(.connected), tint: .clear, cornerRadius: 12)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.glass)
                .environment(\.colorScheme, scheme)
                .background(Color(white: 0.5))
            let a = try render(viaHardware, width: 120, height: 60)
            let b = try render(viaPanel, width: 120, height: 60)
            for point in [(60, 30), (10, 10), (110, 50), (60, 3)] {
                let pa = a.rgba(x: point.0, y: point.1)
                let pb = b.rgba(x: point.0, y: point.1)
                XCTAssertEqual(pa.red, pb.red, "\(scheme) red at \(point)")
                XCTAssertEqual(pa.green, pb.green, "\(scheme) green at \(point)")
                XCTAssertEqual(pa.blue, pb.blue, "\(scheme) blue at \(point)")
                XCTAssertEqual(pa.alpha, pb.alpha, "\(scheme) alpha at \(point)")
            }
        }
    }

    /// Classic material now uses the same quiet neutral wash as the keep-awake
    /// capsule instead of the cool silver, so it must read grey, not blue.
    func testMaterialUsesNeutralWashNotSilver() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let neutral = Color.clear.frame(width: 120, height: 60)
                .hardwareMonitorCardSurface(PowerCardSurface.silver(.connected), cornerRadius: 12)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.material)
                .environment(\.colorScheme, scheme)
                .background(Color(white: 0.5))
            let silver = Color.clear.frame(width: 120, height: 60)
                .panelCardSurface(PowerCardSurface.silver(.connected), tint: .clear, cornerRadius: 12)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.material)
                .environment(\.colorScheme, scheme)
                .background(Color(white: 0.5))
            let a = try render(neutral, width: 120, height: 60)
            let b = try render(silver, width: 120, height: 60)
            let pa = a.rgba(x: 60, y: 30)
            let pb = b.rgba(x: 60, y: 30)
            XCTAssertLessThanOrEqual(abs(Int(pa.red) - Int(pa.blue)), 2, "material card is neutral, not blue")
            XCTAssertLessThanOrEqual(abs(Int(pa.green) - Int(pa.blue)), 2, "material card is neutral, not blue")
            XCTAssertGreaterThan(pa.alpha, 0, "material card is painted")
            // The old silver leaned cool; the neutral wash may not beat it per
            // channel, but it must never read more blue than red.
            XCTAssertLessThanOrEqual(Int(pa.blue), Int(pa.red) + 2, "\(scheme) has no blue cast")
        }
    }

    func testSolidProgressTrackUsesNeutralGroove() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let palette = HardwareMonitorCardSurface.values(scheme: scheme)
            let bar = HardwareDetailProgressBar(fraction: 0)
                .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.solid)
                .environment(\.colorScheme, scheme)
                .background(Color(white: 0.5))
            let buffer = try render(bar, width: 120, height: 6)
            assertPixel(buffer.rgba(x: 60, y: 3), palette.progressTrack)
        }
    }

    func testGlassProgressTrackKeepsPrimaryWash() throws {
        // primary at 10 % over a white card in light mode lands near 229.
        let bar = HardwareDetailProgressBar(fraction: 0)
            .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.glass)
            .environment(\.colorScheme, ColorScheme.light)
            .background(Color.white)
        let buffer = try render(bar, width: 120, height: 6)
        let pixel = buffer.rgba(x: 60, y: 3)
        XCTAssertEqual(Int(pixel.red), 229, accuracy: 8)
        XCTAssertEqual(Int(pixel.green), 229, accuracy: 8)
        XCTAssertEqual(Int(pixel.blue), 229, accuracy: 8)
    }

    // MARK: - Real views (offscreen, no window ordered)

    private func makeLocalization() -> Localization {
        let suite = "HardwareMonitorCardSurfaceTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func sampleSnapshot() -> HardwareMetricsSnapshot {
        var snapshot = HardwareMetricsSnapshot(fanCount: 2)
        let ts = Date(timeIntervalSince1970: 1_000)
        func sample(_ unit: HardwareMetricUnit, _ value: Double, _ source: HardwareMetricSource) -> HardwareMetricSample {
            HardwareMetricSample(value: value, unit: unit, sampledAt: ts, source: source, availability: .measured)
        }
        snapshot.samples[.cpuUsage] = sample(.percent, 61, .mach)
        snapshot.samples[.gpuUsage] = sample(.percent, 72, .ioAccelerator)
        snapshot.samples[.memoryUsage] = sample(.percent, 51, .mach)
        snapshot.samples[.cpuTemperature] = sample(.celsius, 61, .smc)
        snapshot.samples[.gpuTemperature] = sample(.celsius, 72, .smc)
        snapshot.samples[.fanRPM(index: 0)] = sample(.rpm, 2036, .smc)
        snapshot.samples[.networkDownload] = sample(.bytesPerSecond, 1_820_000, .network)
        snapshot.samples[.networkUpload] = sample(.bytesPerSecond, 184_000, .network)
        snapshot.samples[.diskRead] = sample(.bytesPerSecond, 18_400_000, .ioStorage)
        snapshot.samples[.diskWrite] = sample(.bytesPerSecond, 6_200_000, .ioStorage)
        return snapshot
    }

    func testSummaryViewRendersInAllCardStyles() throws {
        for style: PanelCardSurfaceStyle in [.glass, .material, .solid] {
            for scheme: ColorScheme in [.light, .dark] {
                let view = HardwareMonitorSummaryView(model: HardwareMonitorObservable(snapshot: sampleSnapshot()))
                    .environmentObject(makeLocalization())
                    .environment(\.panelCardSurfaceStyle, style)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view.frame(width: 330))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage, "\(style) \(scheme)")
                XCTAssertGreaterThan(image.width, 0)
                XCTAssertGreaterThan(image.height, 0)
            }
        }
    }

    func testAllDetailPagesRenderInSolidLightAndDark() throws {
        var full = sampleSnapshot()
        let date = Date(timeIntervalSince1970: 2_000)
        full.cpuDetail = CPUDetailReading(
            usage: 26.4,
            breakdown: CPUTimeBreakdown(user: 15.2, system: 4.1, idle: 79.6, nice: 1.1),
            perCoreUsage: Array(repeating: 12, count: 16),
            topology: CPUCoreTopology(kinds: Array(repeating: CPUCoreKind.efficiency, count: 4)
                + Array(repeating: CPUCoreKind.performance, count: 12)),
            groupUsage: CPUCoreGroupUsage(efficiencyAverage: 11, performanceAverage: 29.6, superAverage: nil, otherAverage: nil),
            frequency: CPUFrequencyReading(efficiencyGHz: 1.94, performanceGHz: 2.41, superGHz: nil, sampledAt: date),
            sampledAt: date)
        let points = (0..<30).map { index in
            HardwareDetailHistoryPoint(id: index, date: date.addingTimeInterval(Double(index) * 2), values: [26 + 14 * sin(Double(index) / 3.6)])
        }
        for kind in HardwareDetailKind.allCases {
            for scheme: ColorScheme in [.light, .dark] {
                let observable = HardwareMonitorObservable(snapshot: full)
                let view = HardwareDetailView(kind: kind, hardware: observable, onBack: {}, previewHistory: points)
                    .environmentObject(makeLocalization())
                    .environment(\.panelCardSurfaceStyle, PanelCardSurfaceStyle.solid)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view.frame(width: 330))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage, "\(kind) \(scheme)")
                XCTAssertGreaterThan(image.height, 0)
            }
        }
    }

    /// Reduce Transparency collapses the panel background to solid, so the
    /// hardware cards must fall back to this neutral surface rather than the
    /// cool power-card silver.
    func testReduceTransparencyFallsBackToNeutralSolid() {
        for style in PanelBackgroundStyle.allCases {
            let rendered = PanelBackgroundStyle.renderStyle(for: style, reduceTransparency: true)
            let card = PanelCardSurfaceStyle.resolve(rendered)
            XCTAssertEqual(card, .solid, "\(style) under Reduce Transparency")
            let palette = HardwareMonitorCardSurface.values(scheme: .dark)
            let values = [palette.background.red, palette.background.green, palette.background.blue]
            XCTAssertLessThan((values.max() ?? 0) - (values.min() ?? 0), 0.03)
        }
    }
}
