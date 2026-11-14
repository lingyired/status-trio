import AppKit
import SwiftUI

/// Live preview of the menu-bar icon, laid out four per row under the System
/// Monitoring card so the size/style of a 4-up arrangement can be judged in
/// place. The scene is the real `IconPresentationViewModel` output, so it tracks
/// the menu bar icon rather than a canned sample.
struct MenuBarIconPreviewGrid: View {
    let scene: IconSceneState
    let menuBarSize: Double

    @Environment(\.colorScheme) private var colorScheme

    private var image: NSImage? {
        StatusIconPreviewCache.shared.image(
            scene: scene,
            size: 72,
            scale: 2,
            appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: colorScheme == .dark)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("菜单栏图标")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("实时 · 1 行 4 个")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }

            Text("每格约 70×70 pt（面板宽 330 时）· 菜单栏实际约 \(Int(menuBarSize)) pt")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("菜单栏图标预览，一行四个")
    }
}
