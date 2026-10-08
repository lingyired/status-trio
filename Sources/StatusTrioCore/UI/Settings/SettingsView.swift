import AppKit
import SwiftUI

/// Human-centered, multi-column settings window matching modern macOS standards.
struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var localization: Localization
    let onShowIconGuide: () -> Void

    @State private var navigation = SettingsNavigationModel()
    @State private var previewIsDark: Bool = true

    typealias Section = SettingsNavigationModel.Page

    private var selectedSection: Section {
        get { navigation.selection }
        nonmutating set { navigation.selection = newValue }
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
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        SettingsIcon(symbol: section.symbol, tint: section.tint)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.title(localization))
                                .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                                .foregroundStyle(selectedSection == section ? Color.white : Color.primary)
                                .lineLimit(1)

                            if section == .about {
                                Text("v\(AppMetadata.versionDisplayString)")
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundStyle(
                                        selectedSection == section
                                            ? Color.white.opacity(0.72)
                                            : Color.secondary
                                    )
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
        case .iconDesigner:
            IconDesignerView(
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
            GeneralSectionView(store: store, localization: localization)
        case .about:
            AboutSectionView()
        }
    }

    static let sidebarWidth: CGFloat = 190
    static let width: CGFloat = 720
    static let height: CGFloat = 530
}
