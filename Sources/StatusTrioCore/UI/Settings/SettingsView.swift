import AppKit
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
    @ObservedObject var updaterManager: UpdateStateFacade
    @ObservedObject var helper: PrivilegedHelperFacade
    let capabilityPolicy: DistributionCapabilityPolicy
    let onShowIconGuide: () -> Void

    @State private var selectedSection: Section = .appIcon
    @State private var previewIsDark: Bool = true

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization,
        inputSourceController: InputSourceController? = nil,
        globalShortcutController: GlobalShortcutController? = nil,
        updaterManager: UpdateStateFacade = UpdateStateFacade(service: SystemManagedUpdateService()),
        helper: PrivilegedHelperFacade = PrivilegedHelperFacade(service: UnsupportedPrivilegedHelperService()),
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault,
        onShowIconGuide: @escaping () -> Void
    ) {
        self.store = store
        self.statusStore = statusStore
        self.localization = localization
        self.inputSourceController = inputSourceController
        self.globalShortcutController = globalShortcutController
        self.updaterManager = updaterManager
        self.helper = helper
        self.capabilityPolicy = capabilityPolicy
        self.onShowIconGuide = onShowIconGuide
    }

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

        var symbol: String {
            switch self {
            case .appIcon: return "macwindow.on.rectangle"
            case .battery: return SymbolFallback.name("battery.100percent", "battery.100")
            case .network: return "wifi"
            case .bluetooth: return "wave.3.right.circle.fill"
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
                previewIsDark: $previewIsDark,
                helper: helper,
                capabilityPolicy: capabilityPolicy
            )
        case .network:
            NetworkSectionView(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                previewIsDark: $previewIsDark,
                capabilityPolicy: capabilityPolicy
            )
        case .bluetooth:
            BluetoothSectionView(
                store: store,
                statusStore: statusStore,
                bluetoothDevices: statusStore.bluetoothDevices,
                appleDeviceDiscovery: statusStore.appleDeviceDiscovery,
                previewIsDark: $previewIsDark,
                capabilityPolicy: capabilityPolicy
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
                updaterManager: updaterManager,
                capabilityPolicy: capabilityPolicy
            )
        case .about:
            AboutSectionView(
                updaterManager: updaterManager,
                capabilityPolicy: capabilityPolicy
            )
        }
    }

    static let sidebarWidth: CGFloat = 190
    static let width: CGFloat = 720
    static let height: CGFloat = 530
}
