import AppKit
import Combine
import SwiftUI

/// Human-centered, multi-column settings window matching modern macOS standards.
struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            Color.clear.frame(height: 42)

            // The sidebar scrolls on its own so a long expanded category can
            // never push the detail page or clip the traffic-light header.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Section.allCases) { section in
                        categoryRow(section)

                        if navigation.expandedSection == section, !subtopics(for: section).isEmpty {
                            ForEach(subtopics(for: section)) { subtopic in
                                subtopicRow(subtopic)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    private func categoryRow(_ section: Section) -> some View {
        // A simple category paints a filled pill; an expandable category whose
        // leaf is selected only gets a weight emphasis, so the two highlights
        // never compete.
        let showsPill = navigation.selectedSection == section && subtopics(for: section).isEmpty
        return Button {
            select(section)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                SettingsIcon(glyph: section.glyph, tint: section.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title(localization))
                        .font(.system(size: 13, weight: navigation.selectedSection == section ? .medium : .regular))
                        .foregroundStyle(showsPill ? Color.white : Color.primary)
                        .lineLimit(1)

                    if section == .about {
                        Text(
                            DevelopmentBuildPresentation.aboutSidebarDetail(
                                version: AppMetadata.versionDisplayString,
                                codename: AppMetadata.developmentCodename
                            )
                        )
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(
                                showsPill
                                    ? Color.white.opacity(0.72)
                                    : Color.secondary
                            )
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(showsPill ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtopicRow(_ subtopic: SettingsSubtopic) -> some View {
        Button {
            selectSubtopic(subtopic)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // Leave a matching overhang so the indented leaf aligns with its
                // category's icon-space and reads as nested beneath it.
                Text(subtopic.title(localization))
                    .font(.system(size: 12))
                    .foregroundStyle(
                        navigation.selectedSubtopic == subtopic
                            ? Color.white
                            : Color.primary.opacity(0.9)
                    )
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 44)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        navigation.selectedSubtopic == subtopic
                            ? Color.accentColor
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
