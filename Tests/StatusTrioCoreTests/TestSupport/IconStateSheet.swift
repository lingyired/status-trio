import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import StatusTrioCore

/// Renders the bilingual sheet of menu bar icon states used by the READMEs.
///
/// Every glyph comes from `StatusIconRenderer`, so the sheet can never drift
/// from what the app draws.
@MainActor
enum IconStateSheet {
    struct Entry {
        let zh: String
        let en: String
        let status: MenuBarStatus
        let batteryOptions: BatteryIconOptions
        let connectionOptions: ConnectionIconOptions
        let volumeOptions: VolumeIconOptions
        let bluetoothAudioOptions: BluetoothAudioIconOptions
    }

    /// Which part of the combined icon a section documents.
    enum Zone {
        case battery
        case network
        case bluetooth
        case volume

        func tint(in palette: SheetCanvas.Palette) -> CGColor {
            switch self {
            case .battery: palette.batteryTint
            case .network: palette.networkTint
            case .bluetooth: palette.bluetoothTint
            case .volume: palette.volumeTint
            }
        }
    }

    struct Section {
        let zh: String
        let en: String
        let zone: Zone
        let entries: [Entry]
    }

    // MARK: - Layout

    private static let margin: CGFloat = 36
    private static let cardWidth: CGFloat = 262
    private static let cardSpacing: CGFloat = 18
    private static let rowSpacing: CGFloat = 12
    private static let chipSize: CGFloat = 56
    private static let iconSize: CGFloat = 42
    private static let textGap: CGFloat = 14
    private static let titleHeight: CGFloat = 96
    private static let sectionHeaderHeight: CGFloat = 46
    private static let footerHeight: CGFloat = 44
    private static let cardsPerRow = 3

    private static var totalWidth: CGFloat {
        margin * 2
            + cardWidth * CGFloat(cardsPerRow)
            + cardSpacing * CGFloat(cardsPerRow - 1)
    }

    // MARK: - Palette

    // MARK: - Baseline statuses

    private static var baselineBattery: BatteryStatus {
        BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    private static var baselineWiFi: WiFiStatus {
        WiFiStatus(state: .connected, rssi: -52)
    }

    private static var baselineVolume: MenuBarVolumeStatus {
        MenuBarVolumeStatus(scalar: 0.6, isMuted: false, deviceName: nil)
    }

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

    private static func entry(
        zh: String,
        en: String,
        battery: BatteryStatus? = nil,
        wifi: WiFiStatus? = nil,
        connection: NetworkConnection = .wifi,
        batteryOptions: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothOptions: BluetoothAudioIconOptions = .standard,
        volume: MenuBarVolumeStatus? = nil,
        bluetoothDevice: AudioOutputDevice? = nil,
        volumeScalar: Double = 0.6
    ) -> Entry {
        let resolvedVolume: MenuBarVolumeStatus
        if let volume {
            resolvedVolume = volume
        } else if let bluetoothDevice {
            resolvedVolume = MenuBarVolumeStatus(
                scalar: volumeScalar,
                isMuted: false,
                deviceName: bluetoothDevice.name,
                currentDevice: bluetoothDevice
            )
        } else {
            resolvedVolume = baselineVolume
        }

        return Entry(
            zh: zh,
            en: en,
            status: MenuBarStatus(
                battery: battery ?? baselineBattery,
                wifi: wifi ?? baselineWiFi,
                connection: connection,
                volume: resolvedVolume
            ),
            batteryOptions: batteryOptions,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothOptions
        )
    }

    // MARK: - Content

    static var sections: [Section] {
        [
            Section(
                zh: "电池（顶部）",
                en: "Battery (top)",
                zone: .battery,
                entries: [
                    entry(
                        zh: "充电中",
                        en: "Charging",
                        battery: battery(76, charging: true, connected: true)
                    ),
                    entry(
                        zh: "已连接电源，未充电",
                        en: "Plugged in, not charging",
                        battery: battery(76, connected: true)
                    ),
                    entry(
                        zh: "已充满",
                        en: "Fully charged",
                        battery: battery(100, charged: true, connected: true)
                    ),
                    entry(
                        zh: "用电中（电量数字）",
                        en: "On battery (percentage)",
                        battery: battery(76)
                    ),
                    entry(
                        zh: "低电量",
                        en: "Low battery",
                        battery: battery(15)
                    ),
                    entry(
                        zh: "低电量模式",
                        en: "Low Power Mode",
                        battery: battery(55, lowPower: true)
                    ),
                    entry(
                        zh: "只显示圆环",
                        en: "Ring only",
                        battery: battery(76),
                        batteryOptions: BatteryIconOptions(
                            showsPercentage: false,
                            showsChargingIndicator: false,
                            usesStatusColors: true,
                            criticalThreshold: 20
                        )
                    ),
                    entry(
                        zh: "已连接电源时显示数字",
                        en: "Percentage while plugged in",
                        battery: battery(76, connected: true),
                        batteryOptions: BatteryIconOptions(
                            showsPercentage: true,
                            showsChargingIndicator: true,
                            usesStatusColors: true,
                            criticalThreshold: 20,
                            showsPercentageWhenConnected: true
                        )
                    )
                ]
            ),
            Section(
                zh: "Wi-Fi（中部）",
                en: "Wi-Fi (middle)",
                zone: .network,
                entries: [
                    entry(
                        zh: "已连接（3 格）",
                        en: "Connected (3 bars)",
                        wifi: WiFiStatus(state: .connected, rssi: -52)
                    ),
                    entry(
                        zh: "已连接（2 格）",
                        en: "Connected (2 bars)",
                        wifi: WiFiStatus(state: .connected, rssi: -70)
                    ),
                    entry(
                        zh: "已连接（1 格）",
                        en: "Connected (1 bar)",
                        wifi: WiFiStatus(state: .connected, rssi: -85)
                    ),
                    entry(
                        zh: "Wi-Fi 开启，未关联",
                        en: "Wi-Fi on, not associated",
                        wifi: WiFiStatus(state: .notAssociated, rssi: nil)
                    ),
                    entry(
                        zh: "Wi-Fi 关闭或不可用",
                        en: "Wi-Fi off or unavailable",
                        wifi: WiFiStatus(state: .off, rssi: nil)
                    ),
                    entry(
                        zh: "无互联网",
                        en: "No internet",
                        wifi: WiFiStatus(state: .noInternet, rssi: -58)
                    ),
                    entry(
                        zh: "个人热点",
                        en: "Personal Hotspot",
                        wifi: WiFiStatus(state: .hotspot, rssi: -58)
                    ),
                    entry(
                        zh: "临时连接",
                        en: "Temporary connection",
                        wifi: WiFiStatus(state: .temporary, rssi: -58)
                    ),
                    entry(
                        zh: "互联网共享",
                        en: "Internet Sharing",
                        wifi: WiFiStatus(state: .shared, rssi: -58)
                    ),
                    entry(
                        zh: "有线连接（以太网）",
                        en: "Wired (Ethernet)",
                        connection: .ethernet
                    ),
                    entry(
                        zh: "有线连接改用 Wi-Fi 图标",
                        en: "Ethernet as Wi-Fi icon",
                        connection: .ethernet,
                        connectionOptions: ConnectionIconOptions(showsWiFiIconForEthernet: true)
                    ),
                    entry(
                        zh: "个人热点改用 Wi-Fi 图标",
                        en: "Hotspot as Wi-Fi icon",
                        wifi: WiFiStatus(state: .hotspot, rssi: -58),
                        connectionOptions: ConnectionIconOptions(showsWiFiIconForHotspot: true)
                    )
                ]
            ),
            Section(
                zh: "蓝牙音频（中部与底部）",
                en: "Bluetooth audio (middle and bottom)",
                zone: .bluetooth,
                entries: [
                    entry(
                        zh: "取代 Wi-Fi 图标",
                        en: "Replaces the Wi-Fi icon",
                        bluetoothOptions: BluetoothAudioIconOptions(
                            replacesNetworkIcon: true
                        ),
                        bluetoothDevice: SheetFixtures.bluetoothDevice
                    ),
                    entry(
                        zh: "网络异常时保留 Wi-Fi 图标",
                        en: "Keeps Wi-Fi when the network is down",
                        wifi: WiFiStatus(state: .noInternet, rssi: -58),
                        bluetoothOptions: BluetoothAudioIconOptions(
                            replacesNetworkIcon: true
                        ),
                        bluetoothDevice: SheetFixtures.bluetoothDevice
                    ),
                    entry(
                        zh: "未开启取代时仍显示 Wi-Fi 图标",
                        en: "Wi-Fi stays while replacement is off",
                        bluetoothDevice: SheetFixtures.bluetoothDevice
                    ),
                    entry(
                        zh: "音量圆点变蓝",
                        en: "Blue volume dots",
                        bluetoothOptions: BluetoothAudioIconOptions(
                            usesVolumeColor: true
                        ),
                        bluetoothDevice: SheetFixtures.bluetoothDevice,
                        volumeScalar: 0.75
                    ),
                    entry(
                        zh: "音量圆弧变蓝",
                        en: "Blue volume arc",
                        volumeOptions: VolumeIconOptions(displayStyle: .arc),
                        bluetoothOptions: BluetoothAudioIconOptions(
                            usesVolumeColor: true
                        ),
                        bluetoothDevice: SheetFixtures.bluetoothDevice
                    ),
                    entry(
                        zh: "未开启蓝色时保持单色",
                        en: "Monochrome volume while the color is off",
                        bluetoothDevice: SheetFixtures.bluetoothDevice,
                        volumeScalar: 0.75
                    )
                ]
            ),
            Section(
                zh: "音量（底部）",
                en: "Volume (bottom)",
                zone: .volume,
                entries: [
                    entry(
                        zh: "音量 100%（圆点）",
                        en: "Volume 100% (dots)",
                        volume: MenuBarVolumeStatus(scalar: 1.0, isMuted: false, deviceName: nil)
                    ),
                    entry(
                        zh: "音量 60%（圆点）",
                        en: "Volume 60% (dots)",
                        volume: MenuBarVolumeStatus(scalar: 0.6, isMuted: false, deviceName: nil)
                    ),
                    entry(
                        zh: "音量 25%（圆点）",
                        en: "Volume 25% (dots)",
                        volume: MenuBarVolumeStatus(scalar: 0.25, isMuted: false, deviceName: nil)
                    ),
                    entry(
                        zh: "静音（圆点）",
                        en: "Muted (dots)",
                        volume: MenuBarVolumeStatus(scalar: 0.6, isMuted: true, deviceName: nil)
                    ),
                    entry(
                        zh: "音量 75%（圆弧）",
                        en: "Volume 75% (arc)",
                        volumeOptions: VolumeIconOptions(displayStyle: .arc),
                        volume: MenuBarVolumeStatus(scalar: 0.75, isMuted: false, deviceName: nil)
                    ),
                    entry(
                        zh: "音量 30%（圆弧）",
                        en: "Volume 30% (arc)",
                        volumeOptions: VolumeIconOptions(displayStyle: .arc),
                        volume: MenuBarVolumeStatus(scalar: 0.3, isMuted: false, deviceName: nil)
                    ),
                    entry(
                        zh: "静音（圆弧）",
                        en: "Muted (arc)",
                        volumeOptions: VolumeIconOptions(displayStyle: .arc),
                        volume: MenuBarVolumeStatus(scalar: 0.6, isMuted: true, deviceName: nil)
                    )
                ]
            )
        ]
    }

    // MARK: - Rendering

    /// The sheet is drawn once per appearance because the renderer resolves its
    /// foreground and status colors from the menu bar appearance.
    enum Appearance {
        case light
        case dark

        var palette: SheetCanvas.Palette {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }

        var caption: String {
            switch self {
            case .light:
                "图标颜色随菜单栏外观自动切换，这里按浅色外观渲染。 · Colors follow the menu bar appearance; rendered here for light."
            case .dark:
                "图标颜色随菜单栏外观自动切换，这里按深色外观渲染。 · Colors follow the menu bar appearance; rendered here for dark."
            }
        }
    }

    static func pngData(appearance: Appearance = .light, scale: CGFloat = 2) throws -> Data {
        let palette = appearance.palette
        let content = sections
        let rows = content.map { (CGFloat($0.entries.count) / CGFloat(cardsPerRow)).rounded(.up) }
        let bodyHeight = zip(content, rows).reduce(CGFloat.zero) { partial, pair in
            let cardHeight = chipSize + rowSpacing
            return partial + sectionHeaderHeight + pair.1 * cardHeight - rowSpacing
        }
        let totalHeight = titleHeight + bodyHeight + footerHeight

        let context = try SheetCanvas.makeContext(width: totalWidth, height: totalHeight, scale: scale)
        context.setFillColor(palette.page)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        func flip(_ topY: CGFloat) -> CGFloat { totalHeight - topY }

        SheetCanvas.draw(
            "Status Trio 图标状态",
            font: SheetCanvas.font("PingFangSC-Semibold", 21),
            color: palette.ink,
            topLeft: CGPoint(x: margin, y: flip(38)),
            in: context
        )
        SheetCanvas.draw(
            "Menu bar and Dock icon states · drawn by the app's own renderer",
            font: SheetCanvas.font("HelveticaNeue", 12),
            color: palette.mutedInk,
            topLeft: CGPoint(x: margin, y: flip(64)),
            in: context
        )

        var cursor = titleHeight
        for (section, sectionRows) in zip(content, rows) {
            drawSectionHeader(
                section,
                palette: palette,
                topY: cursor,
                totalHeight: totalHeight,
                in: context
            )
            cursor += sectionHeaderHeight

            for (index, entry) in section.entries.enumerated() {
                let column = index % cardsPerRow
                let row = index / cardsPerRow
                let x = margin + CGFloat(column) * (cardWidth + cardSpacing)
                let topY = cursor + CGFloat(row) * (chipSize + rowSpacing)
                try drawCard(
                    entry,
                    palette: palette,
                    topLeft: CGPoint(x: x, y: topY),
                    totalHeight: totalHeight,
                    in: context
                )
            }

            cursor += sectionRows * (chipSize + rowSpacing) - rowSpacing
        }

        SheetCanvas.draw(
            appearance.caption,
            font: SheetCanvas.font("PingFangSC-Regular", 11),
            color: palette.mutedInk,
            topLeft: CGPoint(x: margin, y: flip(totalHeight - footerHeight + 26)),
            in: context
        )

        return try SheetCanvas.pngData(context)
    }

    private static func drawSectionHeader(
        _ section: Section,
        palette: SheetCanvas.Palette,
        topY: CGFloat,
        totalHeight: CGFloat,
        in context: CGContext
    ) {
        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }

        SheetCanvas.drawSectionHeading(
            zh: section.zh,
            en: section.en,
            tint: section.zone.tint(in: palette),
            ink: palette.ink,
            mutedInk: palette.mutedInk,
            left: margin,
            topY: topY,
            totalHeight: totalHeight,
            in: context
        )

        context.setStrokeColor(palette.hairline)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: margin, y: flip(topY + 34)))
        context.addLine(to: CGPoint(x: totalWidth - margin, y: flip(topY + 34)))
        context.strokePath()
    }

    private static func drawCard(
        _ entry: Entry,
        palette: SheetCanvas.Palette,
        topLeft: CGPoint,
        totalHeight: CGFloat,
        in context: CGContext
    ) throws {
        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }

        context.setFillColor(palette.chip)
        context.addPath(SheetCanvas.roundedRect(
            CGRect(x: topLeft.x, y: flip(topLeft.y + chipSize), width: chipSize, height: chipSize),
            cornerRadius: 13
        ))
        context.fillPath()

        guard let icon = renderMenuBarFixture(
                menuBarStatus: entry.status,
            size: iconSize,
            scale: 2,
            foreground: palette.glyph,
            options: entry.batteryOptions,
            connectionOptions: entry.connectionOptions,
            volumeOptions: entry.volumeOptions,
            bluetoothAudioOptions: entry.bluetoothAudioOptions
        ) else {
            throw SheetError.iconUnavailable
        }

        let inset = (chipSize - iconSize) / 2
        context.draw(
            icon,
            in: CGRect(
                x: topLeft.x + inset,
                y: flip(topLeft.y + chipSize - inset),
                width: iconSize,
                height: iconSize
            )
        )

        let textX = topLeft.x + chipSize + textGap
        SheetCanvas.draw(
            entry.zh,
            font: SheetCanvas.font("PingFangSC-Medium", 13),
            color: palette.ink,
            topLeft: CGPoint(x: textX, y: flip(topLeft.y + 17)),
            in: context
        )
        SheetCanvas.draw(
            entry.en,
            font: SheetCanvas.font("HelveticaNeue", 11),
            color: palette.mutedInk,
            topLeft: CGPoint(x: textX, y: flip(topLeft.y + 38)),
            in: context
        )
    }

    enum SheetError: Error {
        case iconUnavailable
    }
}
