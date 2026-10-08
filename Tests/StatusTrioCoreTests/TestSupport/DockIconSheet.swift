import AppKit
import CoreGraphics
import Foundation
@testable import StatusTrioCore

/// Renders the Dock icon sheet used by the READMEs: the three background
/// styles, once for the Wi-Fi state and once for Bluetooth audio taking over
/// the middle glyph. Every tile comes from `DockIconRenderer`.
@MainActor
enum DockIconSheet {
    enum SheetError: Error {
        case iconUnavailable
        case gradientUnavailable
    }

    struct Variant {
        let zh: String
        let en: String
        let style: DockIconBackgroundStyle
    }

    /// One row of tiles: the heading that documents it and the status it draws.
    struct Row {
        let zh: String
        let en: String
        let tint: CGColor
        let status: MenuBarStatus
        let bluetoothAudioOptions: BluetoothAudioIconOptions
    }

    private static let margin: CGFloat = 36
    private static let panelWidth: CGFloat = 262
    private static let panelHeight: CGFloat = 268
    private static let panelSpacing: CGFloat = 18
    private static let iconSize: CGFloat = 190
    private static let titleHeight: CGFloat = 96
    private static let headingHeight: CGFloat = 46
    private static let labelHeight: CGFloat = 58
    private static let footerHeight: CGFloat = 96

    private static var totalWidth: CGFloat {
        margin * 2 + panelWidth * 3 + panelSpacing * 2
    }

    private static var totalHeight: CGFloat {
        titleHeight
            + CGFloat(rows.count) * (headingHeight + panelHeight + labelHeight)
            + footerHeight
    }

    static var variants: [Variant] {
        [
            Variant(zh: "深色背景", en: "Dark background", style: .dark),
            Variant(zh: "浅色背景", en: "Light background", style: .light),
            Variant(zh: "透明背景", en: "Clear background", style: .clear)
        ]
    }

    /// The Dock shows the same combined icon as the menu bar, so the sheet
    /// documents both the network glyph and the Bluetooth audio device that
    /// replaces it.
    static var rows: [Row] {
        [
            Row(
                zh: "Wi-Fi 状态",
                en: "Wi-Fi connected",
                tint: SheetCanvas.Palette.light.networkTint,
                status: status(playsBluetoothAudio: false),
                bluetoothAudioOptions: .standard
            ),
            Row(
                zh: "蓝牙音频取代 Wi-Fi 图标",
                en: "Bluetooth audio replaces the Wi-Fi icon",
                tint: SheetCanvas.Palette.light.bluetoothTint,
                status: status(playsBluetoothAudio: true),
                bluetoothAudioOptions: BluetoothAudioIconOptions(
                    replacesNetworkIcon: true,
                    usesVolumeColor: true
                )
            )
        ]
    }

    /// A charging battery keeps the green accent visible in every variant.
    private static func status(playsBluetoothAudio: Bool) -> MenuBarStatus {
        let device = playsBluetoothAudio ? SheetFixtures.bluetoothDevice : nil

        return MenuBarStatus(
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
                deviceName: device?.name,
                currentDevice: device
            )
        )
    }

    static func pngData(scale: CGFloat = 2) throws -> Data {
        let context = try SheetCanvas.makeContext(width: totalWidth, height: totalHeight, scale: scale)
        context.setFillColor(SheetCanvas.pageFill)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }

        SheetCanvas.draw(
            "Status Trio 程序坞图标",
            font: SheetCanvas.font("PingFangSC-Semibold", 21),
            color: SheetCanvas.ink,
            topLeft: CGPoint(x: margin, y: flip(38)),
            in: context
        )
        SheetCanvas.draw(
            "Dock icons · drawn by the app's own renderer",
            font: SheetCanvas.font("HelveticaNeue", 12),
            color: SheetCanvas.mutedInk,
            topLeft: CGPoint(x: margin, y: flip(64)),
            in: context
        )

        var cursor = titleHeight
        for row in rows {
            SheetCanvas.drawSectionHeading(
                zh: row.zh,
                en: row.en,
                tint: row.tint,
                ink: SheetCanvas.ink,
                mutedInk: SheetCanvas.mutedInk,
                left: margin,
                topY: cursor,
                totalHeight: totalHeight,
                in: context
            )

            context.setStrokeColor(SheetCanvas.hairline)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: margin, y: flip(cursor + 34)))
            context.addLine(to: CGPoint(x: totalWidth - margin, y: flip(cursor + 34)))
            context.strokePath()

            cursor += headingHeight

            for (index, variant) in variants.enumerated() {
                let left = margin + CGFloat(index) * (panelWidth + panelSpacing)
                try drawPanel(
                    row,
                    variant,
                    left: left,
                    topY: cursor,
                    totalHeight: totalHeight,
                    in: context
                )
                drawLabel(
                    variant,
                    left: left,
                    topY: cursor + panelHeight + 16,
                    totalHeight: totalHeight,
                    in: context
                )
            }

            cursor += panelHeight + labelHeight
        }

        for footer in footerLines {
            SheetCanvas.draw(
                footer.text,
                font: SheetCanvas.font(footer.font, 11),
                color: SheetCanvas.mutedInk,
                topLeft: CGPoint(x: margin, y: flip(totalHeight - footerHeight + footer.offset)),
                in: context
            )
        }

        return try SheetCanvas.pngData(context)
    }

    private static var footerLines: [(text: String, font: String, offset: CGFloat)] {
        [
            (
                "深色 / 浅色在「设置 › 应用图标 › Dock 图标背景」中选择；透明对应系统「图标与小组件样式」为透明时的近似效果。",
                "PingFangSC-Regular",
                24
            ),
            (
                "Choose dark or light in Settings › App Icon › Dock icon background; clear approximates the system's Clear icon style.",
                "HelveticaNeue",
                42
            ),
            (
                "蓝牙图标需先在「设置 › 蓝牙音频」中开启「使用蓝牙音频设备图标代替网络图标」。",
                "PingFangSC-Regular",
                62
            ),
            (
                "The Bluetooth icon needs “Replace the network icon with the Bluetooth audio device” turned on in Settings › Bluetooth Audio.",
                "HelveticaNeue",
                80
            )
        ]
    }

    private static func drawPanel(
        _ row: Row,
        _ variant: Variant,
        left: CGFloat,
        topY: CGFloat,
        totalHeight: CGFloat,
        in context: CGContext
    ) throws {
        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }
        let panel = CGRect(x: left, y: flip(topY + panelHeight), width: panelWidth, height: panelHeight)

        // Stand-in for a wallpaper behind the Dock, so the clear tile reads as
        // translucent instead of as a plain white square.
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                SheetCanvas.color(0.93, 0.93, 0.95),
                SheetCanvas.color(0.76, 0.76, 0.82)
            ] as CFArray,
            locations: [0, 1]
        ) else {
            throw SheetError.gradientUnavailable
        }

        context.saveGState()
        context.addPath(SheetCanvas.roundedRect(panel, cornerRadius: 18))
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: panel.minX, y: panel.maxY),
            end: CGPoint(x: panel.minX, y: panel.minY),
            options: []
        )
        context.restoreGState()

        context.setStrokeColor(SheetCanvas.hairline)
        context.setLineWidth(1)
        context.addPath(SheetCanvas.roundedRect(panel.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 18))
        context.strokePath()

        guard let image = renderDockFixture(
                status: row.status,
            bluetoothAudioOptions: row.bluetoothAudioOptions,
            backgroundStyle: variant.style
        ) else {
            throw SheetError.iconUnavailable
        }

        var proposed = CGRect(origin: .zero, size: image.size)
        guard let tile = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw SheetError.iconUnavailable
        }

        let inset = (panelWidth - iconSize) / 2
        context.draw(
            tile,
            in: CGRect(
                x: left + inset,
                y: flip(topY + (panelHeight - iconSize) / 2 + iconSize),
                width: iconSize,
                height: iconSize
            )
        )
    }

    private static func drawLabel(
        _ variant: Variant,
        left: CGFloat,
        topY: CGFloat,
        totalHeight: CGFloat,
        in context: CGContext
    ) {
        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }
        let zhFont = SheetCanvas.font("PingFangSC-Semibold", 14)
        let enFont = SheetCanvas.font("HelveticaNeue", 11.5)

        let zhWidth = SheetCanvas.textWidth(of: variant.zh, font: zhFont)
        SheetCanvas.draw(
            variant.zh,
            font: zhFont,
            color: SheetCanvas.ink,
            topLeft: CGPoint(x: left + (panelWidth - zhWidth) / 2, y: flip(topY + 14)),
            in: context
        )

        let enWidth = SheetCanvas.textWidth(of: variant.en, font: enFont)
        SheetCanvas.draw(
            variant.en,
            font: enFont,
            color: SheetCanvas.mutedInk,
            topLeft: CGPoint(x: left + (panelWidth - enWidth) / 2, y: flip(topY + 36)),
            in: context
        )
    }
}
