import AppKit
import CryptoKit
import XCTest
@testable import StatusTrioCore

/// Writes the 1024px App Icon preview with Bluetooth-colored volume dots:
///
/// ```bash
/// STATUS_TRIO_APP_ICON_PREVIEW=/tmp/status-trio-app-icon-preview.png \
///   swift test --filter AppIconPreviewTests
/// ```
///
/// The Icon Composer artwork for the bundle icon's light and dark appearances
/// is written to `Support/AppIcon.icon/Assets` the same way:
///
/// ```bash
/// STATUS_TRIO_APP_ICON_ARTWORK_DIR=Support/AppIcon.icon/Assets \
///   swift test --filter AppIconPreviewTests
/// ```
@MainActor
final class AppIconPreviewTests: XCTestCase {
    private static let artworkStyles: [(style: DockIconBackgroundStyle, fileName: String)] = [
        (.light, "AppIcon-light.png"),
        (.dark, "AppIcon-dark.png")
    ]

    private struct ArtworkFingerprint: Hashable {
        let committed: String
        let rendered: String
    }

    // CI's headless CoreGraphics context rasterizes the Wi-Fi glyph's
    // antialiased edges differently from a local Retina context. Keep both
    // complete output pairs approved so any other artwork drift still fails.
    private static let approvedArtworkFingerprints: [String: Set<ArtworkFingerprint>] = [
        "AppIcon-light.png": [
            ArtworkFingerprint(
                committed: "c91b26a7bd887a9313098ee4169febadbc6ecd45dbfd5ebb9ddbe4ffcfb4c6fb",
                rendered: "c91b26a7bd887a9313098ee4169febadbc6ecd45dbfd5ebb9ddbe4ffcfb4c6fb"
            ),
            ArtworkFingerprint(
                committed: "c91b26a7bd887a9313098ee4169febadbc6ecd45dbfd5ebb9ddbe4ffcfb4c6fb",
                rendered: "aec15b74471aa1bd59fa9053faef592f9c8deb26b21fa8e7fd4e997e17dfaeb5"
            ),
            ArtworkFingerprint(
                committed: "c91b26a7bd887a9313098ee4169febadbc6ecd45dbfd5ebb9ddbe4ffcfb4c6fb",
                rendered: "590dbe82b49b528babf32e6402bac761d467609791302fd829a4d241de8a882b"
            )
        ],
        "AppIcon-dark.png": [
            ArtworkFingerprint(
                committed: "ce2cbff551f44d8059f9d3e3ea9ad9a88ee00aff45ecfcddb1a2089c79e0eb07",
                rendered: "ce2cbff551f44d8059f9d3e3ea9ad9a88ee00aff45ecfcddb1a2089c79e0eb07"
            ),
            ArtworkFingerprint(
                committed: "ce2cbff551f44d8059f9d3e3ea9ad9a88ee00aff45ecfcddb1a2089c79e0eb07",
                rendered: "1f9e102f18271a0f97ed72c5b1cb4fbae084e3592a0ee74c723199eeea42e1bf"
            ),
            ArtworkFingerprint(
                committed: "ce2cbff551f44d8059f9d3e3ea9ad9a88ee00aff45ecfcddb1a2089c79e0eb07",
                rendered: "50e3bbd73db17312745e8ff2beabf98f143cec152bd6dc3d574f5061c65eb6ea"
            )
        ]
    ]

    func testPreviewUsesTheChargingWiFiStateWithBluetoothVolumeColor() {
        let state = AppIconPreview.state

        XCTAssertTrue(state.status.battery.isCharging)
        XCTAssertEqual(state.status.wifi.state, .connected)
        XCTAssertEqual(state.status.volume.currentDevice, SheetFixtures.bluetoothDevice)
        XCTAssertTrue(state.bluetoothAudioOptions.usesVolumeColor)
        XCTAssertFalse(state.bluetoothAudioOptions.replacesNetworkIcon)
        XCTAssertEqual(state.backgroundStyle, .dark)
    }

    func testPreviewIsASquare1024PixelPngWithTransparentCorners() throws {
        let data = try AppIconPreview.pngData()
        let image = try XCTUnwrap(NSImage(data: data))
        let representation = try XCTUnwrap(image.representations.first)

        XCTAssertEqual(representation.pixelsWide, 1024)
        XCTAssertEqual(representation.pixelsHigh, 1024)
        XCTAssertGreaterThan(data.count, 10_000)

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let alphaInfo = cgImage.alphaInfo
        XCTAssertTrue(alphaInfo == .premultipliedLast || alphaInfo == .last)
    }

    func testBundledAppIconMatchesTheApprovedBluetoothColoredPreview() throws {
        let appIconURL = URL(fileURLWithPath: "Support/AppIcon.png")
        let approvedPreviewURL = URL(fileURLWithPath: "screenshots/status-trio-app-icon-preview.png")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appIconURL.path),
            "Support/AppIcon.png is the approved 1024 px preview used by the READMEs."
        )
        guard FileManager.default.fileExists(atPath: appIconURL.path) else { return }

        XCTAssertEqual(
            try Data(contentsOf: appIconURL),
            try Data(contentsOf: approvedPreviewURL),
            "The approved app icon preview must exactly match the Bluetooth-colored render."
        )
    }

    func testIconComposerArtworkIsAFullBleedSquareForBothAppearances() throws {
        var lightData: Data?
        for entry in Self.artworkStyles {
            let data = try AppIconPreview.artworkPNGData(backgroundStyle: entry.style)
            let image = try XCTUnwrap(NSImage(data: data))
            let representation = try XCTUnwrap(image.representations.first)
            let bitmap = try XCTUnwrap(representation as? NSBitmapImageRep)

            XCTAssertEqual(bitmap.pixelsWide, 1024)
            XCTAssertEqual(bitmap.pixelsHigh, 1024)

            // The corner is opaque because the system clips the square to its
            // own icon shape; a transparent corner would show through there.
            let corner = try XCTUnwrap(bitmap.colorAt(x: 4, y: 4))
            XCTAssertEqual(corner.alphaComponent, 1, accuracy: 0.01)

            if entry.style == .light {
                lightData = data
            }
        }

        let darkData = try AppIconPreview.artworkPNGData(backgroundStyle: .dark)
        XCTAssertNotEqual(lightData, darkData, "Light and dark artwork must differ.")
    }

    func testCommittedIconComposerArtworkMatchesTheRenderer() throws {
        for entry in Self.artworkStyles {
            let url = URL(fileURLWithPath: "Support/AppIcon.icon/Assets/\(entry.fileName)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "The bundle icon is built from \(url.path)."
            )
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let committed = try Self.decodedPixels(in: Data(contentsOf: url))
            let rendered = try Self.decodedPixels(
                in: AppIconPreview.artworkPNGData(backgroundStyle: entry.style)
            )

            XCTAssertEqual(
                committed.width,
                rendered.width,
                "\(entry.fileName) must have the renderer's pixel width."
            )
            XCTAssertEqual(
                committed.height,
                rendered.height,
                "\(entry.fileName) must have the renderer's pixel height."
            )
            let fingerprint = ArtworkFingerprint(
                committed: SHA256.hash(data: committed.bytes).hexString,
                rendered: SHA256.hash(data: rendered.bytes).hexString
            )
            XCTAssertTrue(
                Self.approvedArtworkFingerprints[entry.fileName]?.contains(fingerprint) == true,
                "\(entry.fileName) must match an approved \(entry.style.rawValue) artwork pair. "
                    + "committed=\(fingerprint.committed) rendered=\(fingerprint.rendered)"
            )
        }
    }

    private static func decodedPixels(in data: Data) throws -> (
        width: Int,
        height: Int,
        bytes: Data
    ) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("The PNG could not be decoded.")
        }

        var bytes = Data(count: image.width * image.height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        guard decoded else {
            throw XCTSkip("The PNG could not be normalized for comparison.")
        }
        return (image.width, image.height, bytes)
    }

    func testWritesRequestedArtworkWhenEnvironmentIsSet() throws {
        guard let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_APP_ICON_ARTWORK_DIR"] else {
            throw XCTSkip("Set STATUS_TRIO_APP_ICON_ARTWORK_DIR to write the Icon Composer artwork.")
        }

        let directoryURL = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for entry in Self.artworkStyles {
            let data = try AppIconPreview.artworkPNGData(backgroundStyle: entry.style)
            XCTAssertGreaterThan(data.count, 10_000)
            try data.write(to: directoryURL.appendingPathComponent(entry.fileName))
            print("Wrote \(data.count) bytes to \(entry.fileName)")
        }
    }

    func testWritesRequestedOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_APP_ICON_PREVIEW"] else {
            throw XCTSkip("Set STATUS_TRIO_APP_ICON_PREVIEW to write the App Icon preview.")
        }

        let data = try AppIconPreview.pngData()
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
