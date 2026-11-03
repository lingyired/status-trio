import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The charger-input card is the one power card whose fill cannot come from its
/// foreground tint, so its silver surface is stated here as numbers a screenshot
/// cannot pin down: cool rather than neutral, still light in light mode, and the
/// same resolution in the summary bar and the details flow diagram.
final class PowerCardSurfaceStyleTests: XCTestCase {
    func testSummaryAndFlowInputCardsShareOneSurface() {
        XCTAssertEqual(PowerInfoBarView.surface(for: .input),
                       BatteryPowerFlowView.surface(for: .input))
        XCTAssertEqual(PowerInfoBarView.surface(for: .input), .silver(.connected))
    }

    func testConnectedSilverIsCoolInBothAppearances() {
        for scheme: ColorScheme in [.light, .dark] {
            let silver = PowerCardSilver.values(for: .connected, scheme: scheme)
            XCTAssertGreaterThan(silver.fillRGB.blue, silver.fillRGB.red,
                                 "the fill has to lean cool, not neutral (\(scheme))")
            XCTAssertGreaterThan(silver.strokeRGB.blue, silver.strokeRGB.red,
                                 "the rim has to lean cool, not neutral (\(scheme))")
            XCTAssertGreaterThan(luminance(silver.fillRGB), 0.6,
                                 "the wash itself stays light in \(scheme) mode")
        }
    }

    /// The light-mode complaint was a dirty grey: black at 18% over light glass.
    /// The silver fill has to land lighter and cooler, with a deeper rim so the
    /// card still reads as a surface rather than vanishing.
    func testLightSilverIsLighterAndCoolerThanTheOldBlackWash() {
        let lightBackdrop = PowerCardRGB(red: 0.95, green: 0.95, blue: 0.95)
        let silver = PowerCardSilver.values(for: .connected, scheme: .light)
        let fill = composite(silver.fillRGB, opacity: silver.fillOpacity, over: lightBackdrop)
        let oldBlack = composite(PowerCardRGB(red: 0, green: 0, blue: 0),
                                 opacity: 0.18, over: lightBackdrop)
        let rim = composite(silver.strokeRGB, opacity: silver.strokeOpacity, over: lightBackdrop)

        XCTAssertGreaterThan(luminance(fill), luminance(oldBlack))
        XCTAssertGreaterThan(fill.blue - fill.red, oldBlack.blue - oldBlack.red)
        XCTAssertLessThan(luminance(rim), luminance(fill),
                          "a deeper rim is what makes the fill read as metal")
    }

    /// Dark mode already looked right, so the silver only shifts the wash cooler
    /// and keeps its brightness: cropping it would change the card's weight.
    func testDarkSilverKeepsThePreviousWashBrightness() {
        let darkBackdrop = PowerCardRGB(red: 0.12, green: 0.12, blue: 0.13)
        let silver = PowerCardSilver.values(for: .connected, scheme: .dark)
        let fill = composite(silver.fillRGB, opacity: silver.fillOpacity, over: darkBackdrop)
        let oldWhite = composite(PowerCardRGB(red: 1, green: 1, blue: 1),
                                 opacity: 0.18, over: darkBackdrop)
        XCTAssertEqual(luminance(fill), luminance(oldWhite), accuracy: 0.03)
        XCTAssertGreaterThan(fill.blue - fill.red, oldWhite.blue - oldWhite.red)
    }

    func testDisconnectedSilverStaysInTheSameFamilyButPaler() {
        for scheme: ColorScheme in [.light, .dark] {
            let connected = PowerCardSilver.values(for: .connected, scheme: scheme)
            let disconnected = PowerCardSilver.values(for: .disconnected, scheme: scheme)
            XCTAssertEqual(disconnected.fillRGB, connected.fillRGB)
            XCTAssertEqual(disconnected.strokeRGB, connected.strokeRGB)
            XCTAssertLessThan(disconnected.fillOpacity, connected.fillOpacity)
            XCTAssertLessThan(disconnected.strokeOpacity, connected.strokeOpacity)
            XCTAssertEqual(PowerInfoBarView.surface(for: .inputDisconnected),
                           .silver(.disconnected))
        }
    }

    /// Only the neutral plug cards changed: the green / orange / blue rails keep
    /// their own tint wash at the opacities they already had.
    func testColouredRailsKeepTheirTintWash() {
        for kind: PowerInfoBarKind in [.batteryCharging, .batteryDischarging,
                                       .batteryIdle, .system] {
            XCTAssertEqual(PowerInfoBarView.surface(for: kind),
                           .tint(fillOpacity: 0.18, strokeOpacity: 0.3))
        }
        for kind: BatteryPowerFlowState.Kind in [.batterySource, .charging,
                                                 .display, .usb, .system] {
            XCTAssertEqual(BatteryPowerFlowView.surface(for: kind),
                           .tint(fillOpacity: 0.18, strokeOpacity: 0.3))
        }
    }

    /// A tint-derived surface must ignore the scheme-dependent silver entirely.
    func testTintSurfaceResolvesToTheCardsOwnTint() {
        let surface = PowerCardSurface.tint(fillOpacity: 0.18, strokeOpacity: 0.3)
        XCTAssertEqual(surface.fill(tint: .green, scheme: .light),
                       surface.fill(tint: .green, scheme: .dark))
    }

    // MARK: - Helpers

    private func composite(_ rgb: PowerCardRGB, opacity: Double,
                           over backdrop: PowerCardRGB) -> PowerCardRGB {
        PowerCardRGB(
            red: backdrop.red * (1 - opacity) + rgb.red * opacity,
            green: backdrop.green * (1 - opacity) + rgb.green * opacity,
            blue: backdrop.blue * (1 - opacity) + rgb.blue * opacity)
    }

    private func luminance(_ rgb: PowerCardRGB) -> Double {
        0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }
}

/// Pixel proof that both "charger input" cards really paint the same surface.
///
/// The numbers test above states the recipe; these render the real
/// `PowerInfoBarView` and `BatteryPowerFlowView` headlessly with `ImageRenderer`
/// (no window, no ordering, no GUI) over a known opaque backdrop and read the
/// bitmap, so a future edit cannot quietly turn the card back into a black wash
/// or let the two "charger input" cards drift apart.
@MainActor
final class PowerCardSurfaceRenderingTests: XCTestCase {
    private let scale: CGFloat = 2
    private let lightBackdrop = Color(red: 0.95, green: 0.95, blue: 0.95)
    private let darkBackdrop = Color(red: 0.12, green: 0.12, blue: 0.13)

    func testLightInputCardIsCoolSilverNotTheOldBlackWash() throws {
        let buffer = try renderSummary(kind: .input, scheme: .light)
        let backdrop = try backdropPixel(in: buffer)
        let fill = try dominantFill(in: buffer, points: summarySampleRect)
        let oldBlack = composite((0, 0, 0), opacity: 0.18, over: backdrop)

        XCTAssertGreaterThan(fill.red, oldBlack.red + 10,
                             "the fill has to sit lighter than black at 18 %, got \(fill)")
        XCTAssertGreaterThan(fill.blue - fill.red, oldBlack.blue - oldBlack.red + 4,
                             "the fill has to lean cool, got \(fill)")
        XCTAssertLessThan(luminance255(fill), luminance255(backdrop) - 3,
                          "the card still has to read as a surface, got \(fill)")
    }

    func testDarkInputCardKeepsThePreviousBrightnessAndLeansCool() throws {
        let buffer = try renderSummary(kind: .input, scheme: .dark)
        let backdrop = try backdropPixel(in: buffer)
        let fill = try dominantFill(in: buffer, points: summarySampleRect)
        let oldWhite = composite((255, 255, 255), opacity: 0.18, over: backdrop)

        XCTAssertEqual(luminance255(fill), luminance255(oldWhite), accuracy: 8)
        XCTAssertGreaterThan(fill.blue - fill.red, oldWhite.blue - oldWhite.red + 3,
                             "dark mode keeps the wash but cooler, got \(fill)")
    }

    func testSummaryAndDetailsInputCardsRenderTheSameSurface() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let summary = try dominantFill(in: renderSummary(kind: .input, scheme: scheme),
                                           points: summarySampleRect)
            let details = try dominantFill(in: renderDetailsInput(scheme: scheme),
                                           points: detailsSampleRect)
            XCTAssertEqual(summary.red, details.red, accuracy: 1, "\(scheme)")
            XCTAssertEqual(summary.green, details.green, accuracy: 1, "\(scheme)")
            XCTAssertEqual(summary.blue, details.blue, accuracy: 1, "\(scheme)")
        }
    }

    func testDisconnectedInputCardIsPalerThanTheConnectedOne() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let connected = try renderSummary(kind: .input, scheme: scheme)
            let disconnected = try renderSummary(kind: .inputDisconnected, scheme: scheme)
            let connectedFill = try dominantFill(in: connected, points: summarySampleRect)
            let disconnectedFill = try dominantFill(in: disconnected, points: summarySampleRect)
            let backdrop = try backdropPixel(in: connected)

            XCTAssertLessThan(distance(disconnectedFill, backdrop),
                              distance(connectedFill, backdrop),
                              "an unplugged card reads lighter in \(scheme)")
        }
    }

    // MARK: - Rendering

    /// One card, so the sample rectangle only has to stay inside the single
    /// rounded surface and away from its corners.
    private var summarySampleRect: CGRect {
        CGRect(x: 14, y: 8, width: 212, height: 32)
    }

    private var detailsSampleRect: CGRect {
        CGRect(x: 14, y: 12, width: 212, height: 60)
    }

    private func renderSummary(kind: PowerInfoBarKind,
                               scheme: ColorScheme) throws -> PixelBuffer {
        let localization = makeLocalization()
        let state = PowerInfoBarState(items: [PowerInfoBarItem(kind: kind, value: "42.7 W")])
        let view = PowerInfoBarView(state: state)
            .environmentObject(localization)
            .frame(width: 240, height: 48)
        return try render(view, backdrop: backdrop(for: scheme), scheme: scheme)
    }

    private func renderDetailsInput(scheme: ColorScheme) throws -> PixelBuffer {
        let input = BatteryPowerFlowState.Metric(
            label: "Adapter", value: "42.7 W", watts: 42.7, kind: .input)
        let view = BatteryPowerFlowView(state: BatteryPowerFlowState(input: input, destinations: []))
            .frame(width: 240, height: 84)
        return try render(view, backdrop: backdrop(for: scheme), scheme: scheme)
    }

    private func render<V: View>(_ view: V, backdrop: Color,
                                 scheme: ColorScheme) throws -> PixelBuffer {
        let content = view
            .background(backdrop)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        let nsImage = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")
        let cgImage = try XCTUnwrap(
            nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        return try PixelBuffer(image: cgImage)
    }

    private func makeLocalization() -> Localization {
        let suite = "StatusTrioCoreTests.PowerCardSurface.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        addTeardownBlock {
            defaults.removeTestSuite(named: suite)
        }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func backdrop(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackdrop : lightBackdrop
    }

    // MARK: - Pixels

    private typealias RGB = (red: Int, green: Int, blue: Int)

    /// The backdrop is opaque and covers every edge pixel outside the rounded
    /// corners, so a corner sample states what the fill was composited over.
    private func backdropPixel(in buffer: PixelBuffer) throws -> RGB {
        let pixel = buffer.rgba(x: 1, y: 1)
        XCTAssertGreaterThan(pixel.alpha, 250, "the backdrop has to be opaque")
        return (Int(pixel.red), Int(pixel.green), Int(pixel.blue))
    }

    /// The fill is uniform, so the most frequent opaque colour in the sample
    /// rectangle is the card surface rather than a glyph or its antialiasing.
    private func dominantFill(in buffer: PixelBuffer, points rect: CGRect) throws -> RGB {
        var counts: [Int: Int] = [:]
        let step = Int(scale)
        for y in stride(from: Int(rect.minY) * step, to: Int(rect.maxY) * step, by: step) {
            for x in stride(from: Int(rect.minX) * step, to: Int(rect.maxX) * step, by: step) {
                guard x >= 0, y >= 0, x < buffer.width, y < buffer.height else { continue }
                let pixel = buffer.rgba(x: x, y: y)
                guard pixel.alpha > 250 else { continue }
                let key = Int(pixel.red) << 16 | Int(pixel.green) << 8 | Int(pixel.blue)
                counts[key, default: 0] += 1
            }
        }
        let key = try XCTUnwrap(counts.max(by: { $0.value < $1.value })?.key,
                                "the sample rectangle held no opaque pixels")
        return ((key >> 16) & 0xFF, (key >> 8) & 0xFF, key & 0xFF)
    }

    private func composite(_ rgb: RGB, opacity: Double, over backdrop: RGB) -> RGB {
        func channel(_ value: Int, _ over: Int) -> Int {
            Int((Double(over) * (1 - opacity) + Double(value) * opacity).rounded())
        }
        return (channel(rgb.red, backdrop.red),
                channel(rgb.green, backdrop.green),
                channel(rgb.blue, backdrop.blue))
    }

    /// Relative luminance on the 0–255 scale the pixels are reported in, so
    /// thresholds read as "three levels darker" rather than a normalised ratio.
    private func luminance255(_ rgb: RGB) -> Double {
        0.2126 * Double(rgb.red) + 0.7152 * Double(rgb.green) + 0.0722 * Double(rgb.blue)
    }

    private func distance(_ lhs: RGB, _ rhs: RGB) -> Double {
        let dr = Double(lhs.red - rhs.red)
        let dg = Double(lhs.green - rhs.green)
        let db = Double(lhs.blue - rhs.blue)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
