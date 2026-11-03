import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiNetworkListContrastTests: XCTestCase {
    func testConnectedMarkerStaysReadableWithAPaleAccent() throws {
        // Pale green is a legal accent and falls below 3:1 on a light panel.
        let background = 245.0 / 255
        let bitmap = try render(background: background)
        let scale = Double(bitmap.pixelsWide) / 330
        var ink: [NSColor] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in Int(14 * scale)..<Int(30 * scale) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let chroma = color.greenComponent - max(color.redComponent, color.blueComponent)
                if chroma > 0.02 { ink.append(color) }
            }
        }
        // The most saturated pixels are the solid stroke. Antialiased edges
        // blended with the panel are not required to meet the threshold.
        let peak = try XCTUnwrap(ink.map {
            $0.greenComponent - max($0.redComponent, $0.blueComponent)
        }.max(), "Missing connected-marker ink")
        let interior = ink.filter {
            $0.greenComponent - max($0.redComponent, $0.blueComponent) >= peak - 0.005
        }
        XCTAssertFalse(interior.isEmpty, "Missing solid interior ink")
        for sample in interior {
            XCTAssertGreaterThanOrEqual(contrast(sample, against: background), 3)
        }
    }

    private func render(background: Double) throws -> NSBitmapImageRep {
        let suite = "StatusTrioCoreTests.WiFiContrast.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let row = PanelWiFiNetworkRow(
            key: WiFiNetworkIdentity(ssid: "Contrast", security: .open),
            name: "Contrast",
            signalSymbol: .symbol(name: "wifi", variableValue: nil, fallback: nil),
            signalSystemImage: "wifi",
            securityMarker: nil,
            selected: true,
            accessibilityLabel: "Contrast",
            opensSettings: false
        )
        let state = WiFiPanelState(
            detail: PanelDetailState(
                title: "Wi-Fi", rows: [], isLoading: false, errorText: nil, explanation: nil
            ),
            knownRows: [row],
            otherRows: [],
            powerIsOn: false,
            canSetPower: false,
            canRefresh: false,
            isScanning: false,
            message: nil,
            messageIntent: .none
        )
        let view = WiFiNetworkListView(
            state: state,
            onBack: {},
            onRequestNameAccess: {},
            onOpenWiFiSettings: {},
            onOpenLocationSettings: {},
            onSetPower: { _ in },
            onRefresh: {},
            onOpenSharingSettings: {},
            onCopyValue: { _ in },
            showsDetails: false,
            showsMore: false,
            onSetShowsDetails: { _ in },
            onSetShowsMore: { _ in }
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(.sRGB, red: background, green: background, blue: background, opacity: 1))
        .accentColor(Color(.sRGB, red: 0.8, green: 1, blue: 0.8, opacity: 1))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func contrast(_ color: NSColor, against background: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let ink = 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
        let backdrop = linear(background)
        return (max(ink, backdrop) + 0.05) / (min(ink, backdrop) + 0.05)
    }
}
