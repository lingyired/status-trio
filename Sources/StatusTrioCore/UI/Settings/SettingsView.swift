import AppKit
import SwiftUI

/// Human-centered, multi-column settings window matching modern macOS standards.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var localization: Localization

    @State private var selectedSection: Section = .menuBar

    enum Section: String, CaseIterable, Identifiable {
        case menuBar
        case popover
        case audio
        case general
        case about

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .menuBar: return "menubar.rectangle"
            case .popover: return "list.bullet.rectangle"
            case .audio:   return "hifispeaker.fill"
            case .general: return "gearshape.fill"
            case .about:   return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .menuBar: return .blue
            case .popover: return .indigo
            case .audio:   return .cyan
            case .general: return .gray
            case .about:   return .orange
            }
        }

        @MainActor
        func title(_ localization: Localization) -> String {
            switch self {
            case .menuBar: return localization.string(.settingsTabMenuBar)
            case .popover: return localization.string(.settingsPopupOrder)
            case .audio:   return localization.string(.settingsTabAudio)
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
        case .menuBar:
            MenuBarSectionView(store: store, statusStore: statusStore)
        case .popover:
            PopoverSectionView(store: store, statusStore: statusStore)
        case .audio:
            AudioSectionView(store: store, statusStore: statusStore)
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
