import AppKit
import Combine
import SwiftUI

/// Human-centered, multi-column settings window matching modern macOS standards.
struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the restrained, unemphasized selection colour while the window is
    /// not key.
    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var localization: Localization
    /// Drives the live centre-slot source in the previews. `nil` in tests and
    /// guides that do not carry the app's controller.
    var inputSourceController: InputSourceController? = nil
    var globalShortcutController: GlobalShortcutController? = nil
    var chargeToFullNow: ChargeToFullNowController? = nil
    let onShowIconGuide: () -> Void
    /// Returns the tab the window controller wants to reveal, if any. The
    /// controller stores the request because the first presentation can post
    /// its notification before SwiftUI has subscribed.
    var consumePendingSection: () -> Section? = { nil }
    /// The optional leaf within `consumePendingSection`'s tab, for deep links
    /// that target a specific subpage.
    var consumePendingSubtopic: () -> SettingsSubtopic? = { nil }

    @StateObject private var navigation = SettingsNavigationModel()
    /// The live system appearance, so the menu bar preview starts in the same
    /// light/dark mode as the real menu bar instead of always opening dark.
    @Environment(\.colorScheme) private var systemColorScheme
    /// `nil` means "follow the live system appearance". It only becomes a value
    /// after the user taps the preview card's dark/light toggle, so that manual
    /// choice overrides the system for the rest of the window's lifetime.
    @State private var previewOverrideIsDark: Bool?

    enum Section: String, CaseIterable, Identifiable {
        case appIcon
        case battery
        case network
        case bluetooth
        case audio
        case brightness
        case popover
        case general
        case about

        var id: String { rawValue }

        /// The mark the sidebar tile carries.
        ///
        /// Bluetooth has no SF Symbol on any release, so its tile draws the
        /// rune. Audio borrows the speaker the Audio page's own rows use, so
        /// the sidebar and the page it opens agree on one glyph.
        var glyph: SettingsGlyph {
            switch self {
            case .appIcon: return .symbol("macwindow.on.rectangle")
            case .battery: return .symbol(SymbolFallback.name("battery.100percent", "battery.100"))
            case .network: return .symbol("wifi")
            case .bluetooth: return .bluetoothRune
            case .audio:   return .symbol("speaker.wave.3.fill")
            case .brightness: return .symbol(SymbolFallback.name("sun.max.fill", "sun.max"))
            case .popover: return .symbol("list.bullet.rectangle")
            case .general: return .symbol("gearshape.fill")
            case .about:   return .symbol("info.circle.fill")
            }
        }

        /// The tile colour for the coloured sidebar icon, matching the old
        /// System-Settings-style sidebar (one hue per category).
        var tint: Color {
            switch self {
            case .appIcon: return .indigo
            case .battery: return .green
            case .network: return .blue
            case .bluetooth: return .blue
            case .audio:   return .cyan
            case .brightness: return .orange
            case .popover: return .purple
            case .general: return .gray
            case .about:   return .orange
            }
        }

        @MainActor
        func title(_ localization: Localization) -> String {
            switch self {
            case .appIcon: return localization.string(.settingsTabAppIcon)
            case .battery: return localization.string(.settingsTabBattery)
            case .network: return localization.string(.settingsTabNetwork)
            case .bluetooth: return localization.string(.settingsTabBluetooth)
            case .audio:   return localization.string(.settingsTabAudio)
            case .brightness: return localization.string(.settingsTabBrightness)
            case .popover: return localization.string(.settingsTabPanel)
            case .general: return localization.string(.settingsPageGeneral)
            case .about:   return localization.string(.settingsTabAbout)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .background(SidebarMaterial())

            Divider()

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environmentObject(localization)
        .onAppear { applyRequestedSectionIfAvailable() }
        .onReceive(NotificationCenter.default.publisher(for: .settingsSelectSection)) { _ in
            applyRequestedSectionIfAvailable()
        }
    }

    private func applyRequestedSectionIfAvailable() {
        guard let section = consumePendingSection() else { return }
        let subtopic = consumePendingSubtopic()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: SettingsSidebarMetrics.expandAnimationDuration)) {
            navigation.apply(section: section, subtopic: subtopic)
        }
    }

    private func subtopics(for section: Section) -> [SettingsSubtopic] {
        section.subtopics
    }

    /// Moves the selection. Kept as a thin animated wrapper so the sidebar
    /// buttons and the model stay decoupled.
    private func select(_ section: Section) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: SettingsSidebarMetrics.expandAnimationDuration)) {
            navigation.select(section)
        }
    }

    /// Reveals one leaf subtopic beneath its parent category.
    private func selectSubtopic(_ subtopic: SettingsSubtopic) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: SettingsSidebarMetrics.expandAnimationDuration)) {
            navigation.selectSubtopic(subtopic)
        }
    }

    // MARK: - Sidebar

    /// Functional status categories shown in the scrollable top group.
    private static let scrollableSections: [Section] = [
        .appIcon, .battery, .network, .bluetooth, .audio, .brightness, .popover,
    ]

    /// App-wide panes pinned below the divider so they stay reachable when the
    /// window is short and the top list scrolls.
    private static let pinnedSections: [Section] = [.general, .about]

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Breathing space below traffic lights stays fixed; only the top
            // group below it scrolls.
            Color.clear.frame(height: SettingsSidebarMetrics.topInset)

            // The functional categories scroll on their own so a long expanded
            // category can never clip the traffic-light header, and the current
            // selection is kept in view.
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SettingsSidebarMetrics.categoryGroupSpacing) {
                        ForEach(Self.scrollableSections) { section in
                            categoryBlock(section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsSidebarMetrics.horizontalPadding)
                    .padding(.bottom, 6)
                }
                .onAppear { revealSelection(proxy, animated: false) }
                // macOS 13-compatible single-parameter onChange closures.
                .onChange(of: navigation.selectedSection) { _ in revealSelection(proxy) }
                .onChange(of: navigation.selectedSubtopic) { _ in revealSelection(proxy) }
                .onChange(of: navigation.expandedSection) { _ in revealSelection(proxy) }
            }

            // Subtle system hairline between functional and app-wide groups.
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1 / max(NSScreen.main?.backingScaleFactor ?? 2, 1))
                .opacity(0.6)
                .padding(.horizontal, SettingsSidebarMetrics.groupSeparatorInset)

            // App-wide panes stay pinned; they never scroll out of reach.
            VStack(alignment: .leading, spacing: SettingsSidebarMetrics.categoryGroupSpacing) {
                ForEach(Self.pinnedSections) { section in
                    categoryBlock(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsSidebarMetrics.horizontalPadding)
            .padding(.vertical, SettingsSidebarMetrics.pinnedGroupVerticalPadding)
            .padding(.bottom, 2)
        }
    }

    /// A category row plus its leaves when expanded, shared by both groups so
    /// the top and bottom lists render identically.
    @ViewBuilder
    private func categoryBlock(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow(section)

            if navigation.expandedSection == section, section.hasSubtopics {
                ForEach(subtopics(for: section)) { subtopic in
                    subtopicRow(subtopic)
                }
            }
        }
    }

    /// Scrolls the active row into view without ever shifting it horizontally.
    private func revealSelection(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable?
        if
            navigation.selectedSection.hasSubtopics,
            Self.scrollableSections.contains(navigation.selectedSection),
            let subtopic = navigation.selectedSubtopic
        {
            target = AnyHashable(subtopic)
        } else if Self.scrollableSections.contains(navigation.selectedSection) {
            target = AnyHashable(navigation.selectedSection)
        } else {
            // The pinned app-wide group is always visible; nothing to scroll.
            target = nil
        }
        guard let target else { return }

        if animated {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: SettingsSidebarMetrics.expandAnimationDuration)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    /// A key window uses a light accent wash; a background window uses the
    /// system's unemphasized selection colour so no saturated accent lingers.
    private var selectionFill: Color {
        controlActiveState == .inactive
            ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
            : Color.accentColor.opacity(SettingsSidebarMetrics.activeSelectionOpacity)
    }

    private func categoryRow(_ section: Section) -> some View {
        let isSelected = navigation.selectedSection == section
        let isParent = section.hasSubtopics
        let isExpanded = navigation.expandedSection == section
        // A simple category shows its own selection pill. An expandable parent
        // never paints one: its selected leaf carries the highlight instead.
        let showsSelection = isSelected && !isParent

        return Button {
            select(section)
        } label: {
            HStack(alignment: .center, spacing: SettingsSidebarMetrics.iconTextSpacing) {
                SettingsIcon(
                    glyph: section.glyph,
                    tint: section.tint,
                    size: SettingsSidebarMetrics.tileSize
                )

                Text(section.title(localization))
                    .font(.system(
                        size: SettingsSidebarMetrics.categoryFontSize,
                        weight: isSelected ? .medium : .regular
                    ))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if section == .about {
                    Text("v\(AppMetadata.versionShortString)")
                        .font(.system(
                            size: SettingsSidebarMetrics.aboutVersionFontSize,
                            weight: .regular,
                            design: .rounded
                        ))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }

                if isParent {
                    Image(systemName: "chevron.right")
                        .font(.system(
                            size: SettingsSidebarMetrics.chevronPointSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(.secondary)
                        // Rotate in lockstep with the expand animation rather
                        // than swapping glyphs, so the arrow never jumps.
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, SettingsSidebarMetrics.rowHorizontalPadding)
            .frame(height: SettingsSidebarMetrics.categoryRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsSidebarMetrics.categoryCornerRadius,
                    style: .continuous
                )
                .fill(showsSelection ? selectionFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showsSelection ? [.isSelected] : [])
        // The About row shows only the short version so it cannot wrap or
        // truncate; the full identity (version + development codename) stays
        // available in the tooltip and in the About pane itself.
        .help(
            section == .about
                ? DevelopmentBuildPresentation.aboutSidebarDetail(
                    version: AppMetadata.versionDisplayString,
                    codename: AppMetadata.developmentCodename
                )
                : section.title(localization)
        )
        // Stable scroll target for `ScrollViewReader`.
        .id(section)
    }

    private func subtopicRow(_ subtopic: SettingsSubtopic) -> some View {
        let isSelected = navigation.selectedSubtopic == subtopic

        return Button {
            selectSubtopic(subtopic)
        } label: {
            HStack(spacing: 0) {
                Text(subtopic.title(localization))
                    .font(.system(
                        size: SettingsSidebarMetrics.subtopicFontSize,
                        weight: isSelected ? .medium : .regular
                    ))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    // Compact rows stay one line where the locale fits; longer
                    // translations wrap to a second line instead of truncating.
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsSidebarMetrics.subtopicRowHorizontalPadding)
            .frame(minHeight: SettingsSidebarMetrics.subtopicRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsSidebarMetrics.subtopicCornerRadius,
                    style: .continuous
                )
                .fill(isSelected ? selectionFill : Color.clear)
            )
            // Inset the whole row (background included) so the highlight never
            // spans the full sidebar and the text nests under its parent.
            .padding(.leading, SettingsSidebarMetrics.subtopicIndent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(subtopic.title(localization))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Stable scroll target for `ScrollViewReader`.
        .id(subtopic)
    }

    // MARK: - Menu bar preview appearance

    /// `true` when the preview should draw the dark menu bar backdrop. It follows
    /// the live system appearance until the user taps the card's toggle, so the
    /// preview opens in the same light/dark mode as the real menu bar (#290).
    private var previewIsDark: Bool {
        Self.previewIsDark(override: previewOverrideIsDark, systemColorScheme: systemColorScheme)
    }

    /// Resolves the preview backdrop: a manual override wins, otherwise the live
    /// system appearance decides. Kept as a static so it can be tested without a
    /// live window.
    static func previewIsDark(override: Bool?, systemColorScheme: ColorScheme) -> Bool {
        override ?? (systemColorScheme == .dark)
    }

    /// Binding for the section panes: a manual toggle is remembered for this
    /// window, while an untouched preview keeps tracking the system appearance.
    private var previewIsDarkBinding: Binding<Bool> {
        Binding(
            get: { previewIsDark },
            set: { previewOverrideIsDark = $0 }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch navigation.selectedSection {
        case .appIcon:
            AppIconSectionView(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                previewIsDark: previewIsDarkBinding,
                onShowIconGuide: onShowIconGuide,
                subtopic: subtopicIfSelectionMatches(.appIcon)
            )
        case .battery:
            BatterySectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: previewIsDarkBinding,
                chargeToFullNow: chargeToFullNow,
                subtopic: subtopicIfSelectionMatches(.battery)
            )
        case .network:
            NetworkSectionView(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                previewIsDark: previewIsDarkBinding
            )
        case .bluetooth:
            BluetoothSectionView(
                store: store,
                statusStore: statusStore,
                bluetoothDevices: statusStore.bluetoothDevices,
                appleDeviceDiscovery: statusStore.appleDeviceDiscovery,
                previewIsDark: previewIsDarkBinding,
                subtopic: subtopicIfSelectionMatches(.bluetooth)
            )
        case .audio:
            AudioSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: previewIsDarkBinding,
                subtopic: subtopicIfSelectionMatches(.audio)
            )
        case .brightness:
            BrightnessSectionView(store: store, statusStore: statusStore)
        case .popover:
            PopoverSectionView(store: store, statusStore: statusStore)
        case .general:
            GeneralSectionView(
                store: store,
                localization: localization,
                globalShortcutController: globalShortcutController,
                statusStore: statusStore,
                chargeToFullNow: chargeToFullNow
            )
        case .about:
            AboutSectionView()
        }
    }

    /// Reveals the active subtopic only when it belongs to the given section,
    /// so a single-pane or cross-category selection never bleeds into detail.
    private func subtopicIfSelectionMatches(_ section: Section) -> SettingsSubtopic? {
        guard let selected = navigation.selectedSubtopic, selected.section == section else {
            return nil
        }
        return selected
    }

    static let sidebarWidth: CGFloat = 196
    static let width: CGFloat = 720
    static let height: CGFloat = 530
}
