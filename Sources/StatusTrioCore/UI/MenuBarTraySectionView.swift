import AppKit
import SwiftUI

struct MenuBarTraySectionView: View {
    @ObservedObject var controller: MenuBarTrayController
    var dismissPanel: () -> Void = {}
    @EnvironmentObject private var localization: Localization
    @State private var hoveredItemID: CGWindowID?

    private static let columns = Array(
        repeating: GridItem(.flexible(minimum: 44, maximum: 60), spacing: 6),
        count: 5
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            trayBox
            permissionBanners
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: SymbolFallback.name("menubar.rectangle", "rectangle.topthird.inset.filled"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            Text(headerTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button(action: { controller.refresh() }) {
                PanelActionGlyph(systemName: "arrow.clockwise", size: PanelSummaryActionMetrics.actionSlot)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(localization.string(.menuBarTrayRefresh))
            .accessibilityLabel(localization.string(.menuBarTrayRefresh))
        }
    }

    private var headerTitle: String {
        let base = localization.string(.settingsPopupOrderMenuBarTray)
        guard !controller.items.isEmpty else { return base }
        return "\(base) (\(controller.items.count))"
    }

    // MARK: - Tray Card Box

    @ViewBuilder
    private var trayBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.items.isEmpty {
                Text(localization.string(.menuBarTrayEmptyHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(controller.items) { item in
                        trayCell(for: item)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCardSurface(.silver(.disconnected), tint: .secondary, cornerRadius: 12)
    }

    private func trayCell(for item: MenuBarTrayItem) -> some View {
        let isHovered = hoveredItemID == item.windowID
        let label = displayLabel(for: item)
        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isHovered ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )

                itemIconView(for: item)
            }
            .frame(height: 32)

            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .overlay(
            TrayItemClickCatcher(
                onLeftClick: {
                    controller.open(item, click: .left, dismissPanel: dismissPanel)
                },
                onRightClick: {
                    controller.open(item, click: .right, dismissPanel: dismissPanel)
                },
                onHoverChange: { hovering in
                    hoveredItemID = hovering ? item.windowID : (hoveredItemID == item.windowID ? nil : hoveredItemID)
                }
            )
        )
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? localization.string(.settingsPopupOrderMenuBarTray) : label)
        .accessibilityAddTraits(.isButton)
    }

    private func displayLabel(for item: MenuBarTrayItem) -> String {
        if item.isInputMethodAgent {
            return localization.string(.settingsPopupOrderInputSource)
        }
        return item.displayName
    }

    @ViewBuilder
    private func itemIconView(for item: MenuBarTrayItem) -> some View {
        if let appIcon = item.appIcon {
            Image(nsImage: appIcon)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else if let snapshot = item.snapshot {
            Image(nsImage: snapshot.image)
                .renderingMode(snapshot.isMonochrome ? .template : .original)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 36, maxHeight: 20)
                .foregroundStyle(.primary)
        } else {
            Image(systemName: item.fallbackSymbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionBanners: some View {
        if !controller.permissions.accessibility {
            permissionRow(
                symbol: "hand.point.up.left",
                text: localization.string(.menuBarTrayAccessibilityPrompt),
                actionTitle: localization.string(.menuBarTrayGrantPermission),
                action: { controller.requestAccessibility() }
            )
        }
    }

    private func permissionRow(
        symbol: String,
        text: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: action) {
                Text(actionTitle)
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
}

private struct TrayItemClickCatcher: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrayClickNSView {
        let view = TrayClickNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: TrayClickNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onHoverChange = onHoverChange
    }
}

private final class TrayClickNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onRightClick?()
    }
}
