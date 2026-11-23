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
                bluetoothAudioOptions: bluetoothAudioOptions
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
            status: status(battery: battery(76, connected: true), wifi: connectedWiFi, volume: volume(0.75)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: .standard
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
            status: status(battery: battery(55, lowPower: true), wifi: WiFiStatus(state: .noInternet, rssi: -58), volume: volume(0.25)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .dark,
            status: bluetoothStatus(battery: battery(76, charging: true, connected: true), volume: volume(0.75)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .light,
            status: bluetoothStatus(battery: battery(76), volume: volume(0.45)),
            batteryOptions: BatteryIconOptions(showsPercentage: true),
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .dark,
            status: bluetoothStatus(battery: battery(100, charged: true, connected: true), volume: volume(1)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(76), wifi: WiFiStatus(state: .hotspot, rssi: -58), volume: volume(0.65)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
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

// MARK: - Two-row design strip: custom left/right ring colours

extension DockIconStateStrip {
    /// One tile in the hand-composed design strip. Unlike `State` — which flows
    /// through the product mapper — these scenes are built directly so one strip
    /// can show ring-colour combinations and centre variants that the current
    /// settings cannot produce together.
    struct DesignTile {
        let backgroundStyle: DockIconBackgroundStyle
        let scene: IconSceneState
    }

    // Distinct, saturated ring colours that stay legible on both appearances.
    static let coral = rgba(1.00, 0.42, 0.42)
    static let teal = rgba(0.20, 0.82, 0.74)
    static let indigo = rgba(0.36, 0.45, 1.00)
    static let amber = rgba(1.00, 0.69, 0.13)
    static let magenta = rgba(1.00, 0.30, 0.65)
    static let lime = rgba(0.36, 0.85, 0.42)
    static let cyan = rgba(0.13, 0.77, 0.90)
    static let violet = rgba(0.61, 0.36, 0.90)

    private static func rgba(_ red: Double, _ green: Double, _ blue: Double) -> IconColorRole {
        .custom(IconRGBA(red: red, green: green, blue: blue, alpha: 1))
    }

    private static let twoRowRowGap: CGFloat = 18

    private static func textCenter(_ text: String) -> CenterState {
        .text(IconTextState(text: text, color: .primary, scale: 1))
    }

    private static func boltCenter() -> CenterState {
        .symbol(IconSymbolState(source: .primitive(.bolt), color: .primary, scale: 1))
    }

    /// The top-gap marker scale the first row's original icons use, so the
    /// dual ring's battery number / bolt / plug match that size instead of the
    /// smaller value the AirPods-style ring draws by default.
    private static let accessoryTextScale = BatteryIconOptions.standard.textScale

    /// Top-gap accessory for a dual ring: the battery percentage.
    private static func numberAccessory(_ text: String) -> RingAccessoryState {
        .text(IconTextState(text: text, color: .primary, scale: accessoryTextScale))
    }

    /// Top-gap accessory for a dual ring: a charging bolt or a power plug.
    private static func powerAccessory(_ primitive: IconPrimitive) -> RingAccessoryState {
        .symbol(IconSymbolState(source: .primitive(primitive), color: .primary, scale: accessoryTextScale))
    }

    /// The WeChat input method's own menu-bar glyph (a template image, so the
    /// renderer tints it like every other centre symbol). Falls back to a text
    /// marker if the IME is not installed on the machine that runs the test.
    private static func weChatCenter() -> CenterState {
        let path = "/Library/Input Methods/WeType.app/Contents/Resources/menu_icon.pdf"
        guard FileManager.default.fileExists(atPath: path) else { return textCenter("微") }
        let descriptor = InputSourceDescriptor(
            id: "com.tencent.inputmethod.wetype",
            localizedName: "微信输入法",
            primaryLanguage: "zh-Hans",
            iconURL: URL(fileURLWithPath: path),
            shortLabel: nil
        )
        return IconPresentationMapper.inputSourceCenterState(descriptor, scale: 1)
    }

    private static func designTile(
        _ background: DockIconBackgroundStyle,
        left: (progress: Double, color: IconColorRole),
        right: (progress: Double, color: IconColorRole),
        center: CenterState? = nil,
        accessory: RingAccessoryState? = nil,
        footerProgress: Double
    ) -> DesignTile {
        let ring = OuterRingState(
            segments: [
                RingSegmentState(progress: left.progress, color: left.color, position: .left),
                RingSegmentState(progress: right.progress, color: right.color, position: .right),
            ],
            gap: accessory == nil ? .closed : .value,
            layout: .leftRight,
            accessory: accessory,
            strokeScale: BatteryIconOptions.standard.ringStrokeScale
        )
        let footer = FooterState.arc(ArcState(progress: footerProgress, color: .primary))
        return DesignTile(
            backgroundStyle: background,
            scene: IconSceneState(outerRing: ring, center: center, footer: footer)
        )
    }

    private static func designTile(from state: State) -> DesignTile {
        DesignTile(
            backgroundStyle: state.backgroundStyle,
            scene: dockScene(
                status: state.status,
                options: state.batteryOptions,
                connectionOptions: state.connectionOptions,
                volumeOptions: state.volumeOptions,
                bluetoothAudioOptions: state.bluetoothAudioOptions
            )
        )
    }

    /// The eight custom-ring tiles. Colour pairs mirror about the canvas centre.
    /// Every tile keeps a centre glyph (微信 / 简 / A / 数字), and the second,
    /// fourth, fifth and seventh tiles additionally carry a battery number,
    /// bolt, plug or number in the ring's top gap:
    /// 微信 · 简+76 · A · 76+闪电 | 76+插座 · 简 · A+42 · 微信.
    static let designRow: [DesignTile] = [
        designTile(
            .dark,
            left: (0.55, coral), right: (0.55, teal),
            center: weChatCenter(), footerProgress: 0.65
        ),
        designTile(
            .light,
            left: (0.58, indigo), right: (0.58, amber),
            center: textCenter("简"),
            accessory: numberAccessory("58"), footerProgress: 0.55
        ),
        designTile(
            .dark,
            left: (0.52, magenta), right: (0.52, lime),
            center: textCenter("A"), footerProgress: 0.70
        ),
        designTile(
            .light,
            left: (0.60, cyan), right: (0.60, violet),
            center: textCenter("54"),
            accessory: powerAccessory(.bolt), footerProgress: 0.45
        ),
        designTile(
            .light,
            left: (0.60, violet), right: (0.60, cyan),
            center: textCenter("56"),
            accessory: powerAccessory(.plug), footerProgress: 0.80
        ),
        designTile(
            .dark,
            left: (0.52, lime), right: (0.52, magenta),
            center: textCenter("简"), footerProgress: 0.60
        ),
        designTile(
            .light,
            left: (0.58, amber), right: (0.58, indigo),
            center: textCenter("A"),
            accessory: numberAccessory("52"), footerProgress: 0.75
        ),
        designTile(
            .dark,
            left: (0.55, teal), right: (0.55, coral),
            center: weChatCenter(), footerProgress: 0.50
        ),
    ]

    /// Row one is the existing symmetric strip; row two is the new design row.
    static let twoRowTiles: [[DesignTile]] = [
        symmetricStates.map { designTile(from: $0) },
        designRow,
    ]

    /// Renders equal-width rows of design tiles, separated by a small gap, into
    /// one sheet. Row 0 is drawn at the top.
    static func pngGridData(
        rows: [[DesignTile]],
        scale: CGFloat = 2,
        cornerRadius: CGFloat = 0
    ) throws -> Data {
        let columns = rows.map(\.count).max() ?? 0
        let rowCount = rows.count
        let canvasWidth = horizontalMargin * 2
            + iconSize * CGFloat(columns)
            + gap * CGFloat(max(0, columns - 1))
        let canvasHeight = verticalMargin * 2
            + iconSize * CGFloat(rowCount)
            + twoRowRowGap * CGFloat(max(0, rowCount - 1))
        let context = try SheetCanvas.makeContext(width: canvasWidth, height: canvasHeight, scale: scale)

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

        for (rowIndex, row) in rows.enumerated() {
            let y = verticalMargin
                + CGFloat(rowCount - 1 - rowIndex) * (iconSize + twoRowRowGap)
            for (columnIndex, tile) in row.enumerated() {
                guard let image = DockIconRenderer.image(
                    scene: tile.scene,
                    backgroundStyle: tile.backgroundStyle
                ) else {
                    throw StripError.iconUnavailable
                }
                var proposed = CGRect(origin: .zero, size: image.size)
                guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                    throw StripError.iconUnavailable
                }
                let x = horizontalMargin + CGFloat(columnIndex) * (iconSize + gap)
                context.draw(cgImage, in: CGRect(x: x, y: y, width: iconSize, height: iconSize))
            }
        }

        return try SheetCanvas.pngData(context)
    }

    /// The two-row sheet used for the second sharing image.
    static func twoRowPNGData(scale: CGFloat = 2, cornerRadius: CGFloat = 18) throws -> Data {
        try pngGridData(rows: twoRowTiles, scale: scale, cornerRadius: cornerRadius)
    }
}
