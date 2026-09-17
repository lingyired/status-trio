import AppKit
import SwiftUI

/// Reusable menu bar simulation used by Settings and the icon guide.
struct MenuBarPreviewBar: View {
    let status: MenuBarStatus
    var iconSize: CGFloat = 24
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var isDarkBackground = true
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1
    var trailingInset: CGFloat = 0

    var body: some View {
        ZStack {
            backdrop

            HStack(spacing: 14) {
                leftContext

                Spacer(minLength: 16)

                ZStack {
                    Image(nsImage: StatusIconRenderer.image(
                        menuBarStatus: status,
                        size: iconSize,
                        options: batteryOptions,
                        connectionOptions: connectionOptions,
                        volumeOptions: volumeOptions,
                        appearance: NSAppearance(
                            named: isDarkBackground ? .darkAqua : .aqua
                        )
                    ))

                    if let highlightedPart {
                        StatusIconPartHighlight(
                            part: highlightedPart,
                            volumeDisplayStyle: volumeOptions.displayStyle,
                            lineWidth: max(2.5, iconSize * 0.075)
                        )
                        .frame(width: iconSize, height: iconSize)
                        .opacity(highlightOpacity)
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

                Spacer(minLength: 16)

                rightContext
            }
            .padding(.horizontal, 14)
            .padding(.trailing, trailingInset)
        }
        .frame(height: 40)
    }

    private var backdrop: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isDarkBackground
                    ? LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.16, blue: 0.19),
                            Color(red: 0.10, green: 0.10, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.96, blue: 0.98),
                            Color(red: 0.89, green: 0.89, blue: 0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isDarkBackground
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    private var leftContext: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.logo")
                .font(.system(size: 12, weight: .medium))
            Text(verbatim: "Finder")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(
            isDarkBackground
                ? Color.white.opacity(0.75)
                : Color.black.opacity(0.75)
        )
    }

    private var rightContext: some View {
        HStack(spacing: 6) {
            Image(systemName: "switch.2")
                .font(.system(size: 10))
            Text(verbatim: "9:41")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(
            isDarkBackground
                ? Color.white.opacity(0.65)
                : Color.black.opacity(0.65)
        )
    }
}

/// Reusable Dock simulation with the real Dock icon artwork centered among
/// native macOS app icons.
struct DockPreviewBar: View {
    let status: MenuBarStatus
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var backgroundStyle: DockIconBackgroundStyle = .dark
    var isDarkBackground = true
    var statusIconSize: CGFloat = 56
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1

    var body: some View {
        HStack(spacing: 12) {
            MacAppIcon(
                bundleIdentifier: "com.apple.finder",
                fallbackSymbol: "face.smiling.fill",
                size: statusIconSize * 0.64
            )
            MacAppIcon(
                bundleIdentifier: "com.apple.Safari",
                fallbackSymbol: "safari.fill",
                size: statusIconSize * 0.64
            )

            DockIconTile(
                status: status,
                batteryOptions: batteryOptions,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                backgroundStyle: backgroundStyle,
                size: statusIconSize,
                highlightedPart: highlightedPart,
                highlightOpacity: highlightOpacity
            )

            MacAppIcon(
                bundleIdentifier: "com.apple.MobileSMS",
                fallbackSymbol: "message.fill",
                size: statusIconSize * 0.64
            )
            MacAppIcon(
                bundleIdentifier: "com.apple.mail",
                fallbackSymbol: "envelope.fill",
                size: statusIconSize * 0.64
            )
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isDarkBackground
                        ? Color.black.opacity(0.42)
                        : Color.white.opacity(0.62)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDarkBackground
                        ? Color.white.opacity(0.16)
                        : Color.black.opacity(0.10),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)
    }
}

private struct MacAppIcon: View {
    let bundleIdentifier: String
    let fallbackSymbol: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }

    private var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Real Dock artwork at an arbitrary preview size.
struct DockIconTile: View {
    let status: MenuBarStatus
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var backgroundStyle: DockIconBackgroundStyle = .dark
    var size: CGFloat = 44
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1

    var body: some View {
        ZStack {
            if let image = DockIconRenderer.image(
                status: status,
                options: batteryOptions,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                backgroundStyle: backgroundStyle
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            }

            if let highlightedPart {
                let glyphFrame = DockIconGlyphLayout.frame(
                    in: CGRect(x: 0, y: 0, width: size, height: size)
                )
                StatusIconPartHighlight(
                    part: highlightedPart,
                    volumeDisplayStyle: volumeOptions.displayStyle,
                    lineWidth: max(3, size * 0.07)
                )
                .frame(width: glyphFrame.width, height: glyphFrame.height)
                .position(x: glyphFrame.midX, y: glyphFrame.midY)
                .opacity(highlightOpacity)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Production geometry overlaid at a larger optical weight for onboarding.
struct StatusIconPartHighlight: View {
    let part: IconGuidePart
    let volumeDisplayStyle: VolumeDisplayStyle
    var lineWidth: CGFloat

    var body: some View {
        StatusIconPartShape(
            part: part,
            volumeDisplayStyle: volumeDisplayStyle
        )
        .stroke(
            Color.accentColor,
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .shadow(
            color: Color.accentColor.opacity(0.75),
            radius: lineWidth * 0.9
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StatusIconPartShape: Shape {
    let part: IconGuidePart
    let volumeDisplayStyle: VolumeDisplayStyle

    func path(in rect: CGRect) -> Path {
        let source: Path = switch part {
        case .battery:
            Path(StatusIconGeometry.batteryTrack())
        case .network:
            Path(
                roundedRect: CGRect(x: 31.5, y: 34.4, width: 56, height: 56),
                cornerRadius: 17
            )
        case .volume:
            volumePath
        }

        let scale = min(
            rect.width / StatusIconGeometry.canvas.width,
            rect.height / StatusIconGeometry.canvas.height
        )
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.minX
                + (rect.width - StatusIconGeometry.canvas.width * scale) / 2,
            ty: rect.minY
                + (rect.height - StatusIconGeometry.canvas.height * scale) / 2
        )
        return source.applying(transform)
    }

    private var volumePath: Path {
        switch volumeDisplayStyle {
        case .arc:
            return Path(StatusIconGeometry.volumeArcTrack())
        case .dots:
            var path = Path()
            for point in StatusIconGeometry.volumeDots() {
                path.addEllipse(
                    in: CGRect(
                        x: point.x - 8,
                        y: point.y - 8,
                        width: 16,
                        height: 16
                    )
                )
            }
            return path
        }
    }
}
