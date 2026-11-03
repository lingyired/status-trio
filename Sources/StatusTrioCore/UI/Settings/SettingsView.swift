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
    var managedChargeLimit: ManagedChargeLimitController? = nil
    let onShowIconGuide: () -> Void
    /// Returns the tab the window controller wants to reveal, if any. The
    /// controller stores the request because the first presentation can post
    /// its notification before SwiftUI has subscribed.
    var consumePendingSection: () -> Section? = { nil }

    @State private var selectedSection: Section = .appIcon
    @State private var previewIsDark: Bool = true

    enum Section: String, CaseIterable, Identifiable {
        case appIcon
        case battery
        case network
        case bluetooth
        case audio
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
        select(section)
    }

    private func select(_ section: Section) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            selectedSection = section
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Breathing space below traffic lights
            Color.clear.frame(height: 42)

            ForEach(Section.allCases) { section in
                Button {
                    select(section)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        SettingsIcon(glyph: section.glyph, tint: section.tint)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.title(localization))
                                .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                                .foregroundStyle(selectedSection == section ? Color.white : Color.primary)
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
                                        selectedSection == section
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
                            .fill(selectedSection == section ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .appIcon:
            AppIconSectionView(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                previewIsDark: $previewIsDark,
                onShowIconGuide: onShowIconGuide
            )
        case .battery:
            BatterySectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: $previewIsDark,
                chargeToFullNow: chargeToFullNow,
                managedChargeLimit: managedChargeLimit
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
                previewIsDark: $previewIsDark
            )
        case .audio:
            AudioSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: $previewIsDark
            )
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

    static let sidebarWidth: CGFloat = 190
    static let width: CGFloat = 720
    static let height: CGFloat = 530
}
