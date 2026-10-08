import AppKit
import CoreGraphics
import Foundation
import ImageIO
@testable import StatusTrioCore

/// Composes the 1080×1440 cover used for social posts (小红书).
///
/// The app icon and the background tiles come from `DockIconRenderer`, and the
/// hero shot is cropped from `screenshots/status-trio-dock-light-1440x810.jpg`.
@MainActor
enum SocialCoverSheet {
    enum SheetError: Error {
        case missingScreenshot(String)
        case screenshotUnreadable(String)
        case iconUnavailable
        case gradientUnavailable
    }

    private static let canvasWidth: CGFloat = 1080
    private static let canvasHeight: CGFloat = 1440
    private static let margin: CGFloat = 72
    private static let rightColumnX: CGFloat = 560
    private static let columnWidth: CGFloat = 448
    private static let heroHeight: CGFloat = 608

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestSupport
            .deletingLastPathComponent()  // StatusTrioCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }

    private static var status: MenuBarStatus {
        MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 80,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.43, isMuted: false, deviceName: nil)
        )
    }

    static func pngData() throws -> Data {
        let context = try SheetCanvas.makeContext(
            width: canvasWidth,
            height: canvasHeight,
            scale: 1
        )

        let flip: (CGFloat) -> CGFloat = { canvasHeight - $0 }

        context.setFillColor(SheetCanvas.color(1, 1, 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        try drawHero(in: context)
        try drawBrandBlock(in: context, flip: flip)
        try drawRightColumn(in: context, flip: flip)

        SheetCanvas.draw(
            "statustrio.lingai.net · github.com/lingyired/status-trio",
            font: SheetCanvas.font("PingFangSC-Regular", 22),
            color: SheetCanvas.color(0.55, 0.55, 0.58),
            topLeft: CGPoint(x: margin, y: flip(1372)),
            in: context
        )

        return try SheetCanvas.pngData(context)
    }

    // MARK: - Hero

    private static func drawHero(in context: CGContext) throws {
        let image = try screenshot(named: "status-trio-dock-light-1440x810.jpg")
        let target = CGRect(x: 0, y: canvasHeight - heroHeight, width: canvasWidth, height: heroHeight)
        context.draw(image, in: target)

        drawVersionPill(in: context)
    }

    private static func drawVersionPill(in context: CGContext) {
        let text = "v1.1.0"
        let font = SheetCanvas.font("HelveticaNeue-Medium", 24)
        let padding: CGFloat = 22
        let height: CGFloat = 52
        let topY: CGFloat = 36
        let width = SheetCanvas.textWidth(of: text, font: font) + padding * 2
        let frame = CGRect(
            x: canvasWidth - margin - width,
            y: canvasHeight - topY - height,
            width: width,
            height: height
        )

        context.setFillColor(SheetCanvas.color(1, 1, 1, 0.88))
        context.addPath(SheetCanvas.roundedRect(frame, cornerRadius: height / 2))
        context.fillPath()

        SheetCanvas.draw(
            text,
            font: font,
            color: SheetCanvas.color(0.10, 0.10, 0.12),
            topLeft: CGPoint(x: frame.minX + padding, y: canvasHeight - topY - 13),
            in: context
        )
    }

    // MARK: - Brand block

    private static func drawBrandBlock(in context: CGContext, flip: (CGFloat) -> CGFloat) throws {
        let iconSide: CGFloat = 176
        guard let icon = renderDockFixture(
                status: status, backgroundStyle: .light) else {
            throw SheetError.iconUnavailable
        }
        var proposed = CGRect(origin: .zero, size: icon.size)
        guard let tile = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw SheetError.iconUnavailable
        }

        context.draw(
            tile,
            in: CGRect(x: margin, y: flip(832), width: iconSide, height: iconSide)
        )

        SheetCanvas.draw(
            "Status Trio",
            font: SheetCanvas.font("HelveticaNeue-Bold", 56),
            color: SheetCanvas.color(0.07, 0.07, 0.08),
            topLeft: CGPoint(x: margin, y: flip(886)),
            in: context
        )

        drawBadge(
            "iPhone Duo 同款",
            at: CGPoint(x: margin, y: 956),
            flip: flip,
            in: context
        )

        let lines = [
            "Wi-Fi · 电池 · 音量",
            "合成一个状态图标",
            "菜单栏 / 程序坞都能放"
        ]
        for (index, line) in lines.enumerated() {
            SheetCanvas.draw(
                line,
                font: SheetCanvas.font("PingFangSC-Semibold", 31),
                color: SheetCanvas.color(0.13, 0.13, 0.15),
                topLeft: CGPoint(x: margin, y: flip(1046 + CGFloat(index) * 48)),
                in: context
            )
        }

        SheetCanvas.draw(
            "原生 macOS · 12 种语言 · 免费开源",
            font: SheetCanvas.font("PingFangSC-Regular", 23),
            color: SheetCanvas.color(0.48, 0.48, 0.52),
            topLeft: CGPoint(x: margin, y: flip(1214)),
            in: context
        )

        SheetCanvas.draw(
            "1.1.0 新增：程序坞实时图标 · Wi-Fi / 蓝牙面板",
            font: SheetCanvas.font("PingFangSC-Regular", 23),
            color: SheetCanvas.color(0.48, 0.48, 0.52),
            topLeft: CGPoint(x: margin, y: flip(1264)),
            in: context
        )
    }

    private static func drawBadge(
        _ text: String,
        at topLeft: CGPoint,
        flip: (CGFloat) -> CGFloat,
        in context: CGContext
    ) {
        let font = SheetCanvas.font("PingFangSC-Semibold", 24)
        let textWidth = SheetCanvas.textWidth(of: text, font: font)
        let padding: CGFloat = 20
        let height: CGFloat = 48
        let width = textWidth + padding * 2

        context.setFillColor(SheetCanvas.color(0.04, 0.52, 1.00))
        context.addPath(SheetCanvas.roundedRect(
            CGRect(x: topLeft.x, y: flip(topLeft.y + height), width: width, height: height),
            cornerRadius: height / 2
        ))
        context.fillPath()

        SheetCanvas.draw(
            text,
            font: font,
            color: SheetCanvas.color(1, 1, 1),
            topLeft: CGPoint(x: topLeft.x + padding, y: flip(topLeft.y + 11)),
            in: context
        )
    }

    // MARK: - Right column

    private static func drawRightColumn(in context: CGContext, flip: (CGFloat) -> CGFloat) throws {
        let hero = try screenshot(named: "status-trio-dock-light-1440x810.jpg")

        // Magnified crop of the Dock around the live icon.
        let dockRegion = CGRect(x: 1030, y: 706, width: 320, height: 100)
        guard let dockCrop = hero.cropping(to: dockRegion) else {
            throw SheetError.screenshotUnreadable("status-trio-dock-light-1440x810.jpg")
        }

        drawCard(
            frame: CGRect(x: rightColumnX, y: flip(656 + 150), width: columnWidth, height: 150),
            in: context
        ) {
            context.draw(dockCrop, in: CGRect(x: rightColumnX, y: flip(656 + 150), width: columnWidth, height: 150))
        }

        SheetCanvas.draw(
            "放大：程序坞里的实时图标",
            font: SheetCanvas.font("PingFangSC-Regular", 23),
            color: SheetCanvas.color(0.48, 0.48, 0.52),
            topLeft: CGPoint(x: rightColumnX, y: flip(840)),
            in: context
        )

        try drawBackgroundTiles(in: context, flip: flip)
    }

    private static func drawBackgroundTiles(
        in context: CGContext,
        flip: (CGFloat) -> CGFloat
    ) throws {
        let cardTop: CGFloat = 892
        let cardHeight: CGFloat = 150
        let card = CGRect(x: rightColumnX, y: flip(cardTop + cardHeight), width: columnWidth, height: cardHeight)

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
        context.addPath(SheetCanvas.roundedRect(card, cornerRadius: 16))
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: card.minX, y: card.maxY),
            end: CGPoint(x: card.minX, y: card.minY),
            options: []
        )
        context.restoreGState()

        let styles: [(DockIconBackgroundStyle, String)] = [
            (.dark, "深色"),
            (.light, "浅色"),
            (.clear, "透明")
        ]
        let tileSide: CGFloat = 116
        let gap: CGFloat = 22
        let totalWidth = tileSide * 3 + gap * 2
        let startX = rightColumnX + (columnWidth - totalWidth) / 2
        let tileTop = cardTop + (cardHeight - tileSide) / 2

        for (index, entry) in styles.enumerated() {
            guard let icon = renderDockFixture(
                status: status, backgroundStyle: entry.0) else {
                throw SheetError.iconUnavailable
            }
            var proposed = CGRect(origin: .zero, size: icon.size)
            guard let tile = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                throw SheetError.iconUnavailable
            }

            context.draw(
                tile,
                in: CGRect(
                    x: startX + CGFloat(index) * (tileSide + gap),
                    y: flip(tileTop + tileSide),
                    width: tileSide,
                    height: tileSide
                )
            )
        }

        SheetCanvas.draw(
            "图标背景可选：深色 / 浅色 / 透明",
            font: SheetCanvas.font("PingFangSC-Regular", 23),
            color: SheetCanvas.color(0.48, 0.48, 0.52),
            topLeft: CGPoint(x: rightColumnX, y: flip(1076)),
            in: context
        )
    }

    private static func drawCard(
        frame: CGRect,
        in context: CGContext,
        drawing: () -> Void
    ) {
        context.saveGState()
        context.setFillColor(SheetCanvas.color(1, 1, 1))
        context.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 16,
            color: SheetCanvas.color(0, 0, 0, 0.16)
        )
        context.addPath(SheetCanvas.roundedRect(frame, cornerRadius: 16))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(SheetCanvas.roundedRect(frame, cornerRadius: 16))
        context.clip()
        drawing()
        context.restoreGState()

        context.setStrokeColor(SheetCanvas.color(0, 0, 0, 0.08))
        context.setLineWidth(1)
        context.addPath(SheetCanvas.roundedRect(frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 16))
        context.strokePath()
    }

    // MARK: - Files

    private static func screenshot(named name: String) throws -> CGImage {
        let url = repositoryRoot.appendingPathComponent("screenshots").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SheetError.missingScreenshot(url.path)
        }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SheetError.screenshotUnreadable(url.path)
        }
        return image
    }
}
