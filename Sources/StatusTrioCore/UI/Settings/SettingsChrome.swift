import AppKit
import SwiftUI

/// Standard metrics matching macOS System Settings and Reff Mac App design language.
enum SettingsMetrics {
    static let groupSpacing: CGFloat = 20
    static let cardCorner: CGFloat = 10
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 10
    /// Standard icon size matching System Settings.
    static let iconSize: CGFloat = 26
    static let iconCorner: CGFloat = 6.5
    /// Where a divider starts, clearing the icon column.
    static let dividerInset: CGFloat = rowPaddingH + iconSize + 12
}

/// A titled, rounded card group for settings rows.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    @ViewBuilder let content: Content

    init(
        _ title: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 1)
            }
        }
    }
}

/// The rounded, tinted squircle icon that carries a row's symbol, matching System Settings.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.iconCorner, style: .continuous)
            .fill(tint.gradient)
            .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: SettingsMetrics.iconSize * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A standardized setting row with an icon, title, optional description, and control.
struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
                .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

extension SettingsRow where Leading == SettingsIcon {
    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            trailing: trailing
        )
    }
}

extension SettingsRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

/// A convenient row with an SF symbol, title, and a switch toggle.
struct SettingsToggleRow: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(symbol, tint: tint, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// A row whose choice is made from a pop-up menu on the right.
struct SettingsMenuRow<T: Hashable & Identifiable>: View {
    var symbol: String? = nil
    var tint: Color = .accentColor
    let title: String
    var subtitle: String? = nil
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        SettingsRow(
            title: title,
            subtitle: subtitle,
            leading: {
                if let symbol {
                    SettingsIcon(symbol: symbol, tint: tint)
                }
            },
            trailing: {
                Picker("", selection: $selection) {
                    ForEach(options) { option in
                        Text(label(option)).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        )
    }
}

/// A full-width custom row, useful for sliders and embedded views.
struct SettingsCustomRow<Leading: View, Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .center, spacing: 12) {
                    leading
                        .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .regular))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            content
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

extension SettingsCustomRow where Leading == SettingsIcon {
    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            content: content
        )
    }
}

extension SettingsCustomRow where Leading == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            content: content
        )
    }
}

/// Inset divider between rows in a SettingsGroup card.
struct SettingsDivider: View {
    var inset: CGFloat = SettingsMetrics.dividerInset

    var body: some View {
        Divider()
            .opacity(0.4)
            .padding(.leading, inset)
    }
}

/// A scrolling page container with standard macOS settings padding and background.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
                content
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Standard background material for sidebar views.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
