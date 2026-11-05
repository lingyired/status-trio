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
    /// Outer margin of a settings page. The scrolling card groups and the pinned
    /// menu bar preview above them both span it, so the preview is exactly as
    /// wide as the groups.
    static let pageMargin: CGFloat = 24
    /// The page's top margin, owned by the pinned menu bar preview when the page
    /// has one.
    static let pageTopMargin: CGFloat = 20
    /// How far the selection ring is drawn outside its card: the gap plus the
    /// stroke, on every side.
    static let selectionRingInset: CGFloat = 5
    /// Shared preview dimensions for the three-choice app icon settings.
    static let appIconPictureOptionPreviewSize = CGSize(width: 64, height: 42)
    static let appIconPictureOptionSpacing: CGFloat = 6
    /// Every pop-up menu in Settings keeps one width, independent of its items.
    static let menuPickerWidth: CGFloat = 160
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

/// A full-width explanatory row separated from the setting controls above it.
struct SettingsHintRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 8)
    }
}

/// The mark a settings tile draws.
///
/// Most rows hand the tile an SF Symbol. Bluetooth cannot: no macOS release
/// ships a Bluetooth symbol, and the two nearest stand-ins misread at tile
/// size — `wave.3.right.circle.fill` fills the squircle with a disc, and
/// `wave.3.right` repeats the Wi-Fi fan drawn one row above it. The rune is
/// stroked here instead so the tile carries the mark System Settings carries.
enum SettingsGlyph: Equatable {
    case symbol(String)
    case bluetoothRune
}

/// The rounded, tinted squircle icon that carries a row's symbol, matching System Settings.
struct SettingsIcon: View {
    let glyph: SettingsGlyph
    var tint: Color = .accentColor
    /// Side length of the tinted tile. Defaults to the settings-row size; the
    /// sidebar passes a smaller value to stay compact.
    var size: CGFloat = SettingsMetrics.iconSize

    init(glyph: SettingsGlyph, tint: Color = .accentColor, size: CGFloat = SettingsMetrics.iconSize) {
        self.glyph = glyph
        self.tint = tint
        self.size = size
    }

    init(symbol: String, tint: Color = .accentColor, size: CGFloat = SettingsMetrics.iconSize) {
        self.init(glyph: .symbol(symbol), tint: tint, size: size)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(mark.foregroundStyle(.white))
    }

    @ViewBuilder
    private var mark: some View {
        switch glyph {
        case .symbol(let symbol):
            Image(systemName: SymbolFallback.name(symbol, "questionmark.circle"))
                .font(.system(size: size * 0.52, weight: .semibold))
        case .bluetoothRune:
            BluetoothRuneShape()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: size * BluetoothRuneShape.strokeRatio,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
    }
}

/// The Bluetooth rune as one continuous stroke: down the stem, then through
/// both chevrons, which is how the mark is drawn rather than an outline of it.
///
/// The path is normalized inside a box smaller than the tile so the mark holds
/// the same optical size as the 13.5 pt SF Symbols beside it.
private struct BluetoothRuneShape: Shape {
    /// How much of the tile's side the rune spans.
    static let widthRatio: CGFloat = 0.50
    static let heightRatio: CGFloat = 0.58
    /// Stroke width as a fraction of the tile, tuned against the tile size
    /// rather than the box so it stays legible at 26 pt. Wider reads heavy:
    /// the chevrons close up and the mark turns into a blob.
    static let strokeRatio: CGFloat = 0.070

    func path(in rect: CGRect) -> Path {
        let box = CGRect(
            x: rect.midX - rect.width * Self.widthRatio / 2,
            y: rect.midY - rect.height * Self.heightRatio / 2,
            width: rect.width * Self.widthRatio,
            height: rect.height * Self.heightRatio
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
        }

        var path = Path()
        path.move(to: point(0.16, 0.28))
        path.addLine(to: point(0.84, 0.72))
        path.addLine(to: point(0.50, 1.00))
        path.addLine(to: point(0.50, 0.00))
        path.addLine(to: point(0.84, 0.28))
        path.addLine(to: point(0.16, 0.72))
        return path
    }
}

/// A standardized setting row with an icon, title, optional description, and control.
struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    /// A link that is concatenated onto the end of the description.
    ///
    /// Rendered inside the description's own `Text` so it wraps with the
    /// sentence instead of claiming a column of its own, which would leave a
    /// gap beside every line that does not reach it.
    var subtitleLink: Text? = nil

    /// What `subtitleLink` does when tapped. Without this the link is plain
    /// text, which would read as clickable and do nothing.
    var subtitleLinkAction: (() -> Void)? = nil

    /// Live status text concatenated onto the end of the description.
    ///
    /// Same wrapping as `subtitleLink` — it is part of the sentence, not a
    /// second line — but it is not interactive and carries its own colour, so a
    /// row can report state without spending a row on it.
    var subtitleStatus: Text? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
                .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                if let subtitle {
                    // The link is concatenated onto the description rather than
                    // stacked beside it, so it flows with the sentence and
                    // wraps with it instead of claiming its own column.
                    (
                        Text(subtitle)
                            + (subtitleStatus.map { Text(" ") + $0 } ?? Text(""))
                            + (subtitleLink.map { Text(" ") + $0 } ?? Text(""))
                    )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            subtitleLinkAction?()
                        }
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
        subtitleStatus: Text? = nil,
        subtitleLink: Text? = nil,
        subtitleLinkAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            glyph: .symbol(symbol),
            tint: tint,
            title: title,
            subtitle: subtitle,
            subtitleStatus: subtitleStatus,
            subtitleLink: subtitleLink,
            subtitleLinkAction: subtitleLinkAction,
            trailing: trailing
        )
    }

    /// The same row with a tile that is not an SF Symbol, such as the rune.
    init(
        glyph: SettingsGlyph,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        subtitleStatus: Text? = nil,
        subtitleLink: Text? = nil,
        subtitleLinkAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { SettingsIcon(glyph: glyph, tint: tint) },
            trailing: trailing,
            subtitleLink: subtitleLink,
            subtitleLinkAction: subtitleLinkAction,
            subtitleStatus: subtitleStatus
        )
    }
}

extension SettingsRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        subtitleStatus: Text? = nil,
        subtitleLink: Text? = nil,
        subtitleLinkAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            trailing: trailing,
            subtitleLink: subtitleLink,
            subtitleLinkAction: subtitleLinkAction,
            subtitleStatus: subtitleStatus
        )
    }
}

/// A convenient row with an SF symbol, title, and a switch toggle.
struct SettingsToggleRow: View {
    let glyph: SettingsGlyph
    var tint: Color = .accentColor
    let title: String
    var subtitle: String? = nil
    var subtitleStatus: Text? = nil
    @Binding var isOn: Bool

    init(
        symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        subtitleStatus: Text? = nil,
        isOn: Binding<Bool>
    ) {
        self.init(
            glyph: .symbol(symbol),
            tint: tint,
            title: title,
            subtitle: subtitle,
            subtitleStatus: subtitleStatus,
            isOn: isOn
        )
    }

    /// The same row whose tile is not an SF Symbol, such as the rune.
    init(
        glyph: SettingsGlyph,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        subtitleStatus: Text? = nil,
        isOn: Binding<Bool>
    ) {
        self.glyph = glyph
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.subtitleStatus = subtitleStatus
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(
            glyph: glyph,
            tint: tint,
            title: title,
            subtitle: subtitle,
            subtitleStatus: subtitleStatus
        ) {
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
                .settingsMenuPickerWidth()
            }
        )
    }
}

/// Keeps the picture-card keyboard path native on every supported release.
///
/// macOS 14+ keeps the existing `onKeyPress` handling and suppresses the
/// duplicate system focus effect. Ventura has neither API, so it keeps the
/// system focus ring and maps arrow keys through `onMoveCommand`; Space and
/// Return remain native `Button` activation.
private struct SettingsPictureRowKeyboardBehavior: ViewModifier {
    let backwardStep: Int
    let forwardStep: Int
    let onSelect: () -> Void
    let onMove: (Int) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) {
                    onMove(backwardStep)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    onMove(forwardStep)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    onMove(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onMove(1)
                    return .handled
                }
                .onKeyPress(.space) {
                    onSelect()
                    return .handled
                }
                .onKeyPress(.return) {
                    onSelect()
                    return .handled
                }
        } else {
            content
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        onMove(backwardStep)
                    case .right:
                        onMove(forwardStep)
                    case .up:
                        onMove(-1)
                    case .down:
                        onMove(1)
                    default:
                        break
                    }
                }
        }
    }
}

private extension View {
    func settingsPictureRowKeyboardBehavior(
        backwardStep: Int,
        forwardStep: Int,
        onSelect: @escaping () -> Void,
        onMove: @escaping (Int) -> Void
    ) -> some View {
        modifier(SettingsPictureRowKeyboardBehavior(
            backwardStep: backwardStep,
            forwardStep: forwardStep,
            onSelect: onSelect,
            onMove: onMove
        ))
    }
}

/// Extension for concentric Apple-style selection rings around preview cards.
extension View {
    /// Concentric with the picture card: the ring's inner corner is the card's
    /// own corner plus the gap, matching macOS System Settings Appearance selection ring.
    ///
    /// This ring is the only selection *and* focus indicator for the card pickers.
    /// The option buttons stay focusable so Tab reaches them and the arrow keys
    /// move the selection, but their system focus effect is disabled: it drew a
    /// second ring on top of this one, and the two rings never lined up.
    ///
    /// The ring is drawn `selectionRingInset` outside the card on every side, so
    /// the ring's outer edge — not the card's — is what sits on the row's
    /// content column.
    func selectionRing(
        _ isOn: Bool,
        cornerRadius: CGFloat = 6,
        style: RoundedCornerStyle = .continuous
    ) -> some View {
        let gap = SettingsMetrics.selectionRingInset / 2
        let width = SettingsMetrics.selectionRingInset / 2
        return padding(SettingsMetrics.selectionRingInset)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + gap + width, style: style)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: width)
            )
    }
}

/// A row whose choices are visual preview cards matching macOS System Settings Appearance and Icon style pickers.
struct SettingsPictureRow<T: Hashable & Identifiable, Leading: View, Preview: View>: View {
    let title: String
    var subtitle: String? = nil
    var optionSymbol: ((T) -> String?)? = nil
    @Binding var selection: T
    let options: [T]
    var previewSize: CGSize = CGSize(width: 68, height: 44)
    @ViewBuilder var leading: Leading
    let caption: (T) -> String
    @ViewBuilder let preview: (T) -> Preview

    @FocusState private var focusedOption: T?
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if !(Leading.self == EmptyView.self) {
                    leading
                        .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                    if let subtitle {
                        subtitleText(subtitle)
                    }
                }

                Spacer(minLength: 12)

                HStack(alignment: .top, spacing: SettingsMetrics.appIconPictureOptionSpacing) {
                    ForEach(options) { option in
                        let isSelected = selection == option
                        Button {
                            selectOption(option)
                        } label: {
                            VStack(spacing: 5) {
                                preview(option)
                                    .frame(width: previewSize.width, height: previewSize.height)
                                    .overlay(alignment: .topTrailing) {
                                        if let symbol = optionSymbol?(option) {
                                            optionSymbolBadge(symbol)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                    .selectionRing(isSelected, cornerRadius: 6)

                                // The caption is capped to the card width and may
                                // wrap to two lines, so a long translation cannot
                                // stretch the row or push the cards out of the group.
                                Text(caption(option))
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: previewSize.width)
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedOption, equals: option)
                        // macOS 13 has no onKeyPress/focusEffectDisabled.
                        // Keep the selected card's own ring as the only visual
                        // focus treatment on macOS 14+, while Ventura keeps the
                        // system focus ring and handles arrows via onMoveCommand.
                        .settingsPictureRowKeyboardBehavior(
                            backwardStep: backwardStep,
                            forwardStep: forwardStep,
                            onSelect: { selectOption(option) },
                            onMove: { selectRelative(offset: $0) }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(caption(option))
                        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
            }

        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }

    private func subtitleText(_ subtitle: String) -> some View {
        Text(subtitle)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func optionSymbolBadge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 16, height: 16)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(4)
            .accessibilityHidden(true)
    }

    /// Left and right follow the reading direction: the option row mirrors in a
    /// right-to-left layout, so an unconditional -1/+1 would move the selection
    /// the wrong way on screen in Arabic.
    private var backwardStep: Int { layoutDirection == .rightToLeft ? 1 : -1 }
    private var forwardStep: Int { -backwardStep }

    private func selectOption(_ target: T) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            selection = target
            focusedOption = target
        }
    }

    /// Wraps at both ends so repeated presses keep cycling through the options.
    private func selectRelative(offset: Int) {
        let current = focusedOption ?? selection
        guard let next = SettingsPictureRowSelection.wrapped(
            in: options,
            from: current,
            offset: offset
        ) else { return }
        selectOption(next)
    }
}

/// Selection math for the picture-card option rows.
///
/// The card pickers disable their system focus effect, so the arrow keys are the
/// keyboard path that has to keep working: the offset wraps at both ends and the
/// reading direction decides which way "forward" points.
enum SettingsPictureRowSelection {
    static func wrapped<T: Hashable>(
        in options: [T],
        from current: T,
        offset: Int
    ) -> T? {
        guard !options.isEmpty else { return nil }
        guard let currentIndex = options.firstIndex(of: current) else { return nil }
        let count = options.count
        let newIndex = ((currentIndex + offset) % count + count) % count
        return options[newIndex]
    }
}

extension SettingsPictureRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        optionSymbol: ((T) -> String?)? = nil,
        selection: Binding<T>,
        options: [T],
        previewSize: CGSize = CGSize(width: 68, height: 44),
        caption: @escaping (T) -> String,
        @ViewBuilder preview: @escaping (T) -> Preview
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            optionSymbol: optionSymbol,
            selection: selection,
            options: options,
            previewSize: previewSize,
            leading: { EmptyView() },
            caption: caption,
            preview: preview
        )
    }
}

extension SettingsPictureRow where Leading == SettingsIcon {
    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        optionSymbol: ((T) -> String?)? = nil,
        selection: Binding<T>,
        options: [T],
        previewSize: CGSize = CGSize(width: 68, height: 44),
        caption: @escaping (T) -> String,
        @ViewBuilder preview: @escaping (T) -> Preview
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            optionSymbol: optionSymbol,
            selection: selection,
            options: options,
            previewSize: previewSize,
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            caption: caption,
            preview: preview
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
///
/// The optional `pinnedHeader` is the page's live menu bar simulation. It is a
/// pinned section header *inside* the scroll view, so it stays at the top of the
/// pane while the groups below it scroll, and so it shares their width exactly —
/// including on the panes whose content overflows and therefore shows a
/// scrollbar. The header must not sit outside the scroll view: a scrollbar that
/// takes layout space only narrows the scrolling content, which used to leave the
/// app icon page's card groups one scrollbar narrower than the preview above them.
struct SettingsPage<Content: View, PinnedHeader: View>: View {
    @ViewBuilder let pinnedHeader: PinnedHeader
    @ViewBuilder let content: Content

    init(
        @ViewBuilder pinnedHeader: () -> PinnedHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.pinnedHeader = pinnedHeader()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            if PinnedHeader.self == EmptyView.self {
                contentColumn
                    .padding(.top, SettingsMetrics.pageTopMargin)
            } else {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        contentColumn
                    } header: {
                        pinnedHeader
                            .padding(
                                EdgeInsets(
                                    top: SettingsMetrics.pageTopMargin,
                                    leading: SettingsMetrics.pageMargin,
                                    bottom: SettingsMetrics.groupSpacing,
                                    trailing: SettingsMetrics.pageMargin
                                )
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // The groups scroll underneath the pinned preview, so
                            // it has to paint the page's own background.
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            content
        }
        .padding(
            EdgeInsets(
                top: 0,
                leading: SettingsMetrics.pageMargin,
                bottom: SettingsMetrics.pageMargin,
                trailing: SettingsMetrics.pageMargin
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsPage where PinnedHeader == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(pinnedHeader: { EmptyView() }, content: content)
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

/// macOS 26's `.buttonSizing(.flexible)` makes a menu picker fill its frame
/// instead of sizing to its current menu items. Older systems keep the frame.
private struct SettingsMenuPickerSizing: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonSizing(.flexible)
        } else {
            content
        }
    }
}

extension View {
    func settingsMenuPickerWidth() -> some View {
        frame(width: SettingsMetrics.menuPickerWidth)
            .modifier(SettingsMenuPickerSizing())
    }
}

// MARK: - Sidebar visual language

/// Visual parameters for the two-level settings sidebar.
///
/// Plan B: every category carries one monochrome glyph, and leaf subtopics are
/// text only. Keeping the numbers here (instead of scattering them through the
/// row builders) makes the sidebar easy to retune without touching behaviour.
enum SettingsSidebarMetrics {
    /// Space reserved below the traffic-light buttons.
    static let topInset: CGFloat = 42
    /// Outer horizontal margin of the scrolling sidebar content.
    static let horizontalPadding: CGFloat = 10
    /// Inner horizontal padding of a category row's own selection area.
    static let rowHorizontalPadding: CGFloat = 8
    /// Slightly tighter inner padding for leaf rows so their text keeps a usable
    /// width despite the extra indent.
    static let subtopicRowHorizontalPadding: CGFloat = 6

    static let categoryRowHeight: CGFloat = 32
    static let subtopicRowHeight: CGFloat = 26
    /// Gap between two category blocks (category plus its leaves). Kept in the
    /// 2–4 pt band so the list reads denser than the old 6 pt layout.
    static let categoryGroupSpacing: CGFloat = 4
    /// Vertical breathing room around the pinned app-wide group at the bottom.
    static let pinnedGroupVerticalPadding: CGFloat = 6
    /// Leading inset of the hairline between the scrollable and pinned groups.
    static let groupSeparatorInset: CGFloat = 18

    /// Side length of the coloured category tile in the sidebar.
    static let tileSize: CGFloat = 22
    /// Fixed glyph column so every category title starts at the same x.
    static let iconSlotWidth: CGFloat = 18
    static let iconPointSize: CGFloat = 16
    static let iconTextSpacing: CGFloat = 10
    /// Drawn box for the custom Bluetooth rune before it is centered in the slot.
    static let runeFrame: CGFloat = 26
    static let runeStroke: CGFloat = 1.8

    static let categoryFontSize: CGFloat = 13
    static let subtopicFontSize: CGFloat = 12
    static let aboutVersionFontSize: CGFloat = 10
    static let chevronPointSize: CGFloat = 10

    /// Leading inset of a leaf row from the sidebar content edge. It is chosen so
    /// the leaf *text* lines up on the same vertical column as the parent
    /// category's *text* (not its tile), so the whole group reads as one aligned
    /// text grid: outer padding + this indent + leaf row padding = parent text x.
    static let subtopicIndent: CGFloat = 34
    static let subtopicCornerRadius: CGFloat = 6
    static let categoryCornerRadius: CGFloat = 6

    /// Lightweight expand/collapse and selection animation (0.16–0.18 s).
    static let expandAnimationDuration: Double = 0.17

    /// How strongly the accent tint fills a selected row in the key window.
    static let activeSelectionOpacity: Double = 0.18

    /// Per-glyph optical scale so the sidebar icon column reads as one size.
    /// Derived by measuring each glyph's rendered bounding box; wide glyphs
    /// (battery, app icon) are trimmed slightly, narrow/tall ones (wifi, the
    /// Bluetooth rune) and the small outlined round glyphs are nudged up.
    static func opticalScale(for glyph: SettingsGlyph) -> CGFloat {
        switch glyph {
        case .symbol(let name):
            if name.hasPrefix("battery") { return 1.06 }
            if name == "wifi" { return 1.06 }
            if name.hasPrefix("speaker") { return 0.94 }
            if name.hasPrefix("sun.max") { return 1.0 }
            if name.hasPrefix("macwindow") { return 0.96 }
            if name.hasPrefix("list.bullet.rectangle") { return 1.0 }
            if name.hasPrefix("gearshape") { return 1.02 }
            if name.hasPrefix("info.circle") { return 1.04 }
            return 1.0
        case .bluetoothRune:
            return 1.18
        }
    }
}

/// A monochrome category glyph for the sidebar.
///
/// The Bluetooth category keeps the project's custom rune instead of an
/// inaccurate SF Symbol; it is only re-sized and tinted here. Every glyph is
/// centered in a fixed-width slot so category titles stay left-aligned.
struct SettingsSidebarGlyph: View {
    let glyph: SettingsGlyph
    var tint: Color = .secondary

    var body: some View {
        Group {
            switch glyph {
            case .symbol(let symbol):
                Image(systemName: SymbolFallback.name(symbol, "questionmark.circle"))
                    .font(.system(size: SettingsSidebarMetrics.iconPointSize, weight: .medium))
            case .bluetoothRune:
                BluetoothRuneShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: SettingsSidebarMetrics.runeStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: SettingsSidebarMetrics.runeFrame,
                        height: SettingsSidebarMetrics.runeFrame
                    )
            }
        }
        // SF Symbols of different aspect ratios render at noticeably different
        // apparent sizes in a fixed slot (a wide battery reads small, a narrow
        // rune reads thin). Nudge each one optically so the column looks even.
        .scaleEffect(SettingsSidebarMetrics.opticalScale(for: glyph))
        .foregroundStyle(tint)
        .frame(
            width: SettingsSidebarMetrics.iconSlotWidth,
            height: SettingsSidebarMetrics.iconSlotWidth
        )
    }
}
