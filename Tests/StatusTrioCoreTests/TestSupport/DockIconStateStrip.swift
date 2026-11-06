import AppKit
import CoreGraphics
import Foundation
@testable import StatusTrioCore

/// Renders eight representative Dock states as one text-free horizontal strip.
/// The background styles are arranged so the same live glyph can be compared
/// across both appearances at a glance.
@MainActor
enum DockIconStateStrip {
    struct State {
        let backgroundStyle: DockIconBackgroundStyle
        let status: MenuBarStatus
        let batteryOptions: BatteryIconOptions
        let connectionOptions: ConnectionIconOptions
        let volumeOptions: VolumeIconOptions
        let bluetoothAudioOptions: BluetoothAudioIconOptions
        let inputSource: InputSourceDescriptor?
        let systemPower: SystemPowerSample?

        init(
            backgroundStyle: DockIconBackgroundStyle,
            status: MenuBarStatus,
            batteryOptions: BatteryIconOptions,
            connectionOptions: ConnectionIconOptions,
            volumeOptions: VolumeIconOptions,
            bluetoothAudioOptions: BluetoothAudioIconOptions,
            inputSource: InputSourceDescriptor? = nil,
            systemPower: SystemPowerSample? = nil
        ) {
            self.backgroundStyle = backgroundStyle
            self.status = status
            self.batteryOptions = batteryOptions
            self.connectionOptions = connectionOptions
            self.volumeOptions = volumeOptions
            self.bluetoothAudioOptions = bluetoothAudioOptions
            self.inputSource = inputSource
            self.systemPower = systemPower
        }

        var volumeStyle: VolumeDisplayStyle { volumeOptions.displayStyle }

        var usesBluetoothAudio: Bool {
            status.volume.currentDevice?.isBluetoothAudio == true
        }

        var usesBluetoothVolumeColor: Bool {
            usesBluetoothAudio && bluetoothAudioOptions.usesVolumeColor
        }

        func withBackgroundStyle(_ backgroundStyle: DockIconBackgroundStyle) -> State {
            State(
                backgroundStyle: backgroundStyle,
                status: status,
                batteryOptions: batteryOptions,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                bluetoothAudioOptions: bluetoothAudioOptions,
                inputSource: inputSource,
                systemPower: systemPower
            )
        }
    }

    private static let iconSize: CGFloat = 220
    private static let gap: CGFloat = 14
    private static let horizontalMargin: CGFloat = 24
    private static let verticalMargin: CGFloat = 24
    private static let canvasHeight = iconSize + verticalMargin * 2

    static let states: [State] = [
        State(
            backgroundStyle: .dark,
            status: status(battery: battery(76, charging: true, connected: true), wifi: connectedWiFi, volume: volume(0.6)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(72, charging: true, connected: true), wifi: connectedWiFi, volume: volume(0.5)),
            batteryOptions: .standard,
            connectionOptions: ConnectionIconOptions(centerSource: .power),
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: .standard,
            systemPower: SystemPowerSample(watts: 23.6, readAt: Date())
        ),
        State(
            backgroundStyle: .dark,
            status: status(battery: battery(64), wifi: connectedWiFi, volume: volume(0.4)),
            batteryOptions: .standard,
            connectionOptions: ConnectionIconOptions(centerSource: .inputSource),
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard,
            inputSource: pinyinInputSource
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(76, charging: true, connected: true), wifi: connectedWiFi, volume: volume(0.7)),
            batteryOptions: .standard,
            connectionOptions: ConnectionIconOptions(centerSource: .chargingStatus),
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .dark,
            status: status(battery: battery(88, connected: true), wifi: connectedWiFi, volume: volume(0.75)),
            batteryOptions: BatteryIconOptions(connectedIndicator: .percentage),
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .light,
            status: bluetoothStatus(battery: battery(82), volume: volume(0.62)),
            batteryOptions: .standard,
            connectionOptions: ConnectionIconOptions(centerSource: .bluetoothDevice),
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .dark,
            status: status(battery: battery(15), wifi: WiFiStatus(state: .connected, rssi: -85), volume: volume(0.6, muted: true)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(54, lowPower: true), wifi: WiFiStatus(state: .hotspot, rssi: -48), volume: volume(0.45)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        )
    ]

    /// Reuses the original eight states while arranging their backgrounds symmetrically.
    /// The original `states` array remains unchanged for the previously generated strip.
    static let symmetricStates: [State] = {
        let backgroundStyles: [DockIconBackgroundStyle] = [.dark, .light, .dark, .light, .light, .dark, .light, .dark]
        return states.enumerated().map { index, state in
            state.withBackgroundStyle(backgroundStyles[index])
        }
    }()

    static func pngData(
        for renderStates: [State] = Self.states,
        scale: CGFloat = 2,
        cornerRadius: CGFloat = 0
    ) throws -> Data {
        let canvasWidth = horizontalMargin * 2
            + iconSize * CGFloat(renderStates.count)
            + gap * CGFloat(renderStates.count - 1)
        let context = try SheetCanvas.makeContext(width: canvasWidth, height: canvasHeight, scale: scale)

        // Keep the default output square-cornered for the original reference
        // image; the README variant opts into a subtle transparent corner.
        if cornerRadius > 0 {
            let bounds = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
            context.addPath(CGPath(
                roundedRect: bounds,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            ))
            context.clip()
        }

        context.setFillColor(SheetCanvas.color(0.93, 0.93, 0.95))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        let y = verticalMargin
        for (index, state) in renderStates.enumerated() {
            guard let image = renderDockFixture(
                status: state.status,
                options: state.batteryOptions,
                connectionOptions: state.connectionOptions,
                volumeOptions: state.volumeOptions,
                bluetoothAudioOptions: state.bluetoothAudioOptions,
                inputSource: state.inputSource,
                systemPower: state.systemPower,
                backgroundStyle: state.backgroundStyle
            ) else {
                throw StripError.iconUnavailable
            }

            var proposed = CGRect(origin: .zero, size: image.size)
            guard let tile = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                throw StripError.iconUnavailable
            }

            let x = horizontalMargin + CGFloat(index) * (iconSize + gap)
            context.draw(tile, in: CGRect(x: x, y: y, width: iconSize, height: iconSize))
        }

        return try SheetCanvas.pngData(context)
    }

    enum StripError: Error {
        case iconUnavailable
    }

    private static let connectedWiFi = WiFiStatus(state: .connected, rssi: -52)
    private static let bluetoothOptions = BluetoothAudioIconOptions(usesVolumeColor: true)
    private static let pinyinInputSource = InputSourceDescriptor(
        id: "com.apple.inputmethod.SCIM.ITABC",
        localizedName: "简体拼音",
        primaryLanguage: "zh-Hans",
        iconURL: nil,
        shortLabel: "拼"
    )

    private static func battery(
        _ percentage: Int,
        charging: Bool = false,
        charged: Bool = false,
        connected: Bool = false,
        lowPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isCharged: charged,
            isLowPowerMode: lowPower,
            isConnectedToPower: connected
        )
    }

    private static func volume(
        _ scalar: Double,
        muted: Bool = false,
        bluetooth: Bool = false
    ) -> MenuBarVolumeStatus {
        let device = bluetooth ? SheetFixtures.bluetoothDevice : nil
        return MenuBarVolumeStatus(
            scalar: scalar,
            isMuted: muted,
            deviceName: device?.name,
            currentDevice: device
        )
    }

    private static func status(
        battery: BatteryStatus,
        wifi: WiFiStatus,
        volume: MenuBarVolumeStatus
    ) -> MenuBarStatus {
        MenuBarStatus(battery: battery, wifi: wifi, connection: .wifi, volume: volume)
    }

    private static func bluetoothStatus(
        battery: BatteryStatus,
        volume: MenuBarVolumeStatus
    ) -> MenuBarStatus {
        status(battery: battery, wifi: connectedWiFi, volume: MenuBarVolumeStatus(
            scalar: volume.scalar,
            isMuted: volume.isMuted,
            deviceName: SheetFixtures.bluetoothDevice.name,
            currentDevice: SheetFixtures.bluetoothDevice
        ))
    }
}
