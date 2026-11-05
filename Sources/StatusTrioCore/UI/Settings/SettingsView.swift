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
    @State private var previewIsDark: Bool = true

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

        /// The monochrome mark the sidebar row carries.
        ///
        /// Bluetooth has no SF Symbol on any release, so its row keeps the
        /// project's custom rune. Audio borrows the speaker the Audio page's
        /// own rows use, so the sidebar and the page it opens agree on one
        /// glyph.
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            navigation.apply(section: section, subtopic: subtopic)
        }
    }

    private func subtopics(for section: Section) -> [SettingsSubtopic] {
        section.subtopics
    }

    /// Moves the selection. Kept as a thin animated wrapper so the sidebar
    /// buttons and the model stay decoupled.
    private func select(_ section: Section) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            navigation.select(section)
        }
    }

    /// Reveals one leaf subtopic beneath its parent category.
    private func selectSubtopic(_ subtopic: SettingsSubtopic) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            navigation.selectSubtopic(subtopic)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Breathing space below traffic lights stays fixed; only the rows
            // below it scroll.
            Color.clear.frame(height: SettingsSidebarMetrics.topInset)

            // The sidebar scrolls on its own so a long expanded category can
            // never push the detail page or clip the traffic-light header.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sidebarGroups) { group in
                        Text(localization.string(group.title))
                            .font(.system(
                                size: SettingsSidebarMetrics.captionFontSize,
                                weight: .semibold
                            ))
                            .foregroundStyle(.secondary)
                            .padding(.leading, SettingsSidebarMetrics.rowHorizontalPadding)
                            .padding(.top, SettingsSidebarMetrics.groupCaptionTopSpacing)
                            .padding(.bottom, SettingsSidebarMetrics.groupCaptionBottomSpacing)

                        VStack(
                            alignment: .leading,
                            spacing: SettingsSidebarMetrics.categoryGroupSpacing
                        ) {
                            ForEach(group.sections) { section in
                                sectionBlock(section)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsSidebarMetrics.horizontalPadding)
                .padding(.bottom, 8)
            }
        }
    }

    private struct SidebarGroupSpec: Identifiable {
        let id: String
        let title: LocalizationKey
        let sections: [Section]
    }

    /// Two caption groups keeping the existing category order (Magpie-style
    /// sidebar). Grouping is visual only; routes and settings are unchanged.
    private var sidebarGroups: [SidebarGroupSpec] {
        [
            SidebarGroupSpec(
                id: "status",
                title: .settingsSidebarGroupStatus,
                sections: [.appIcon, .battery, .network, .bluetooth, .audio, .brightness]
            ),
            SidebarGroupSpec(
                id: "system",
                title: .settingsSidebarGroupSystem,
                sections: [.popover, .general, .about]
            ),
        ]
    }

    private func sectionBlock(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow(section)

            if navigation.expandedSection == section, section.hasSubtopics {
                // A thin vertical guide runs under the parent's icon so the
                // leaves read as its subtree.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(subtopics(for: section)) { subtopic in
                        subtopicRow(subtopic)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(SettingsSidebarMetrics.treeGuideOpacity))
                        .frame(width: SettingsSidebarMetrics.treeGuideWidth)
                        .padding(.leading, SettingsSidebarMetrics.treeGuideInset)
                        .padding(.top, SettingsSidebarMetrics.treeGuideTopInset)
                        .padding(.bottom, SettingsSidebarMetrics.treeGuideBottomInset)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// A calm, neutral selection fill: a translucent label colour in the key
    /// window and the system's unemphasized colour when the window is not
    /// focused. No saturated accent block.
    private var selectionFill: Color {
        controlActiveState == .inactive
            ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
            : Color.primary.opacity(SettingsSidebarMetrics.selectedRowFillOpacity)
    }

    /// An even softer wash for an expanded parent, so the two levels never
    /// carry the same visual weight.
    private var parentFill: Color {
        controlActiveState == .inactive
            ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.6)
            : Color.primary.opacity(SettingsSidebarMetrics.selectedParentFillOpacity)
    }

    private func categoryRow(_ section: Section) -> some View {
        let isSelected = navigation.selectedSection == section
        let isParent = section.hasSubtopics
        let isExpanded = navigation.expandedSection == section
        // A simple category shows the row fill. An expandable parent gets only
        // a softer wash; its selected leaf carries the stronger highlight.
        let showsSelection = isSelected && !isParent
        let showsParentFill = isParent && isSelected && isExpanded

        return Button {
            select(section)
        } label: {
            HStack(alignment: .center, spacing: SettingsSidebarMetrics.iconTextSpacing) {
                SettingsSidebarGlyph(glyph: section.glyph)

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
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(
                            size: SettingsSidebarMetrics.chevronPointSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, SettingsSidebarMetrics.rowHorizontalPadding)
            .frame(height: SettingsSidebarMetrics.categoryRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsSidebarMetrics.categoryCornerRadius,
                    style: .continuous
                )
                .fill(
                    showsSelection
                        ? selectionFill
                        : (showsParentFill ? parentFill : Color.clear)
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsSidebarMetrics.rowHorizontalPadding)
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
                previewIsDark: $previewIsDark,
                onShowIconGuide: onShowIconGuide,
                subtopic: subtopicIfSelectionMatches(.appIcon)
            )
        case .battery:
            BatterySectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: $previewIsDark,
                chargeToFullNow: chargeToFullNow,
                subtopic: subtopicIfSelectionMatches(.battery)
            )
        case .network:
            NetworkSectionView(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                previewIsDark: $previewIsDark
            )
        case .bluetooth:
            BluetoothSectionView(
                store: store,
                statusStore: statusStore,
                bluetoothDevices: statusStore.bluetoothDevices,
                appleDeviceDiscovery: statusStore.appleDeviceDiscovery,
                previewIsDark: $previewIsDark,
                subtopic: subtopicIfSelectionMatches(.bluetooth)
            )
        case .audio:
            AudioSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: $previewIsDark,
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

    static let sidebarWidth: CGFloat = 190
    static let width: CGFloat = 720
    static let height: CGFloat = 530
}
