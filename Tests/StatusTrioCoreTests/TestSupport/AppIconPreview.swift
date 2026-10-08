import AppKit
import CoreGraphics
import Foundation
@testable import StatusTrioCore

/// Produces the proposed App Icon without changing the bundled icon.
///
/// The center glyph remains Wi-Fi while the volume dots use the renderer's
/// Bluetooth blue, matching the requested variation of the first Dock state.
@MainActor
enum AppIconPreview {
    struct State {
        let backgroundStyle: DockIconBackgroundStyle
        let status: MenuBarStatus
        let bluetoothAudioOptions: BluetoothAudioIconOptions
    }

    static let state = State(
        backgroundStyle: .dark,
        status: MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: SheetFixtures.bluetoothDevice.name,
                currentDevice: SheetFixtures.bluetoothDevice
            )
        ),
        bluetoothAudioOptions: BluetoothAudioIconOptions(
            replacesNetworkIcon: false,
            usesVolumeColor: true
        )
    )

    static func pngData() throws -> Data {
        let canvasSize: CGFloat = 1024
        let context = try SheetCanvas.makeContext(width: canvasSize, height: canvasSize, scale: 1)
        context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

        guard let image = renderDockFixture(
                status: state.status,
            bluetoothAudioOptions: state.bluetoothAudioOptions,
            backgroundStyle: state.backgroundStyle
        ) else {
            throw PreviewError.iconUnavailable
        }

        var proposed = CGRect(origin: .zero, size: image.size)
        guard let tile = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw PreviewError.iconUnavailable
        }

        context.interpolationQuality = .high
        context.draw(tile, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
        return try SheetCanvas.pngData(context)
    }

    enum PreviewError: Error {
        case iconUnavailable
    }
}
