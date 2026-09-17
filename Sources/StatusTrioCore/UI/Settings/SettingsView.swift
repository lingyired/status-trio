import AppKit
import SwiftUI

/// Human-centered, multi-column settings window matching modern macOS standards.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var localization: Localization
    let onShowIconGuide: () -> Void

    @State private var selectedSection: Section = .appIcon
    @State private var previewIsDark: Bool = true

    enum Section: String, CaseIterable, Identifiable {
        case appIcon
        case battery
        case network
        case audio
        case popover
        case general
        case about

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .appIcon: return "macwindow.on.rectangle"
            case .battery: return "battery.100percent"
            case .network: return "wifi"
            case .audio:   return "hifispeaker.fill"
            case .popover: return "list.bullet.rectangle"
            case .general: return "gearshape.fill"
            case .about:   return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .appIcon: return .indigo
            case .battery: return .green
            case .network: return .blue
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Breathing space below traffic lights
            Color.clear.frame(height: 42)

            ForEach(Section.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        SettingsIcon(symbol: section.symbol, tint: section.tint)

                        Text(section.title(localization))
                            .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                            .foregroundStyle(selectedSection == section ? Color.white : Color.primary)
                            .lineLimit(1)

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
                previewIsDark: $previewIsDark,
                onShowIconGuide: onShowIconGuide
            )
        case .battery:
            BatterySectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: $previewIsDark
            )
        case .network:
            NetworkSectionView(
                store: store,
                statusStore: statusStore,
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
            GeneralSectionView(store: store, localization: localization)
        case .about:
            AboutSectionView()
        }
    }

    static let sidebarWidth: CGFloat = 190
    static let width: CGFloat = 720
    static let height: CGFloat = 530
}
