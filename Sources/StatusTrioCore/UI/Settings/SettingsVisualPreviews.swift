import AppKit
import SwiftUI

// MARK: - Shared Preview Helpers

/// Menu bar backdrop shared by the mock menu bar and the option preview cards.
///
/// The cards render the real menu bar artwork, so they follow the pane's
/// light/dark preview toggle instead of the current system appearance. That
/// keeps every card in the pane in step and avoids a bitmap that was baked for
/// the other appearance.
struct MenuBarPreviewBackdrop: View {
    let isDarkBackground: Bool
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
    }

    /// `nil` lets AppKit resolve the colors while it draws, which is what the
    /// real menu bar icon does.
    static func appearance(isDarkBackground: Bool) -> NSAppearance? {
        NSAppearance(named: isDarkBackground ? .darkAqua : .aqua)
    }
}

/// Live status with a guaranteed audible volume reading, so a preview card still
/// shows meaningful artwork while the machine is muted or has no volume source.
@MainActor
private func menuBarPreviewStatus(from statusStore: SystemStatusStore) -> MenuBarStatus {
    let base = MenuBarStatus(snapshot: statusStore.snapshot)
    let scalar = base.volume.scalar ?? 0
    let volume = MenuBarVolumeStatus(
        scalar: scalar > 0 && !base.volume.isMuted ? scalar : 0.75,
        isMuted: false,
        deviceName: base.volume.deviceName
    )
    return MenuBarStatus(
        battery: base.battery,
        wifi: base.wifi,
        connection: base.connection,
        volume: volume
    )
}

// MARK: - Volume Indicator Preview

struct VolumeIndicatorPreview: View {
    let style: VolumeDisplayStyle
    let isDarkBackground: Bool
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore

    var previewScene: IconSceneState {
        IconPreviewScene.make(
            status: menuBarPreviewStatus(from: statusStore),
            configuration: IconPresentationConfiguration(
                battery: store.batteryIconOptions,
                connection: store.connectionIconOptions,
                volume: VolumeIconOptions(
                    displayStyle: style,
                    ringStrokeScale: store.ringStrokeStyle.scale
                ),
                bluetooth: .standard
            )
        )
    }

    var body: some View {
        ZStack {
            MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground)

            Image(nsImage: StatusIconRenderer.image(
                scene: previewScene,
                size: 28,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: isDarkBackground)
            ) ?? NSImage(size: NSSize(width: 28, height: 28)))
            .accessibilityHidden(true)
        }
    }
}

// MARK: - App Icon Placement Preview

struct AppIconPlacementPreview: View {
    let placement: AppIconPlacement

    var body: some View {
        ZStack {
            // Mini screen body
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Mini Menu Bar at top
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 2.5, height: 2.5)
                        .padding(.leading, 3.5)
                    Spacer()
                    if placement.showsMenuBarIcon {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 3.5)
                            .padding(.trailing, 3.5)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 9, height: 2.5)
                            .padding(.trailing, 3.5)
                    }
                }
                .frame(height: 7)
                .background(Color.primary.opacity(placement.showsMenuBarIcon ? 0.12 : 0.05))

                Spacer()

                // Mini Dock at bottom
                if placement.showsDockIcon {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: 4, height: 4)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    )
                    .padding(.bottom, 3)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 20, height: 2.5)
                        .padding(.bottom, 3)
                }
            }
        }
    }
}

// MARK: - Dock Background Preview

struct DockBackgroundPreview: View {
    let preference: DockIconBackgroundPreference
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore

    private var designerScene: IconSceneState {
        let snapshot = statusStore.snapshot
        return IconDesignerPreviewResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationResourceResolver.inputs(snapshot: snapshot),
                sources: IconPresentationResourceResolver.sourceSnapshot(snapshot: snapshot)
            ),
            configuration: store.iconConfiguration
        ).scene
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            switch preference {
            case .system:
                // Split light/dark macOS Dock tile
                ZStack {
                    DockIconPreviewTile(
                        store: store,
                        statusStore: statusStore,
                        size: 30,
                        overrideStyle: .light,
                        resolvedScene: designerScene
                    )

                    DockIconPreviewTile(
                        store: store,
                        statusStore: statusStore,
                        size: 30,
                        overrideStyle: .dark,
                        resolvedScene: designerScene
                    )
                    .clipShape(HalfSplitShape())

                    // Hairline divider down the middle
                    Rectangle()
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 0.5, height: 28)
                }
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            case .dark:
                DockIconPreviewTile(
                    store: store,
                    statusStore: statusStore,
                    size: 30,
                    overrideStyle: .dark,
                    resolvedScene: designerScene
                )
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

            case .light:
                DockIconPreviewTile(
                    store: store,
                    statusStore: statusStore,
                    size: 30,
                    overrideStyle: .light,
                    resolvedScene: designerScene
                )
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            }
        }
    }
}

/// Right half of the Dock tile, used to show the light and dark Dock
/// backgrounds side by side in the "match the system" preview.
private struct HalfSplitShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height))
        return path
    }
}

// MARK: - Ring Stroke Style Preview

struct RingStrokeStylePreview: View {
    let style: RingStrokeStyle
    let isDarkBackground: Bool
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore

    var previewScene: IconSceneState {
        IconPreviewScene.make(
            status: menuBarPreviewStatus(from: statusStore),
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(
                    showsPercentage: store.showsBatteryPercentage,
                    showsChargingIndicator: store.showsChargingIndicator,
                    usesStatusColors: store.usesBatteryStatusColors,
                    criticalThreshold: Int(store.batteryCriticalThreshold.rounded()),
                    showsPercentageWhenConnected: store.showsPercentageWhenConnected,
                    textScale: store.batterySymbolScale * BatteryIconOptions.defaultTextScale,
                    ringStrokeScale: style.scale
                ),
                connection: store.connectionIconOptions,
                volume: VolumeIconOptions(
                    displayStyle: store.volumeDisplayStyle,
                    ringStrokeScale: style.scale
                ),
                bluetooth: .standard
            )
        )
    }

    var body: some View {
        ZStack {
            MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground)

            Image(nsImage: StatusIconRenderer.image(
                scene: previewScene,
                size: 28,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: isDarkBackground)
            ) ?? NSImage(size: NSSize(width: 28, height: 28)))
            .accessibilityHidden(true)
        }
    }
}
