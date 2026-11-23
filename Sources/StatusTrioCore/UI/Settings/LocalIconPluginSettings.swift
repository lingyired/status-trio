import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LocalIconPluginCatalogModel: ObservableObject {
    @Published private(set) var catalog = LocalIconPluginCatalog()

    func reload(directories: [URL]) async {
        catalog = await LocalIconPluginCatalog.load(directories: directories)
    }
}

struct LocalIconPluginSlotOption: Identifiable, Hashable {
    let binding: IconContentBinding
    let title: String

    var id: IconContentBinding { binding }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.binding == rhs.binding && lhs.title == rhs.title
    }

    func hash(into hasher: inout Hasher) { hasher.combine(binding) }
}

/// External presentations offered by the enabled packages for one slot.
enum LocalIconPluginSlotCatalog {
    static func options(for slot: IconSlot, in catalog: LocalIconPluginCatalog) -> [LocalIconPluginSlotOption] {
        catalog.packages.flatMap { package in
            package.manifest.presentations
                .filter { $0.slot.iconSlot == slot }
                .map { presentation in
                    LocalIconPluginSlotOption(
                        binding: IconContentBinding(
                            pluginID: package.manifest.pluginID,
                            presentationID: presentation.id),
                        title: "\(package.manifest.title) — \(presentation.id)"
                    )
                }
        }
    }
}

enum LocalIconPluginSlotPickerPolicy {
    /// Keep the menu reachable while any bound presentation is external, even
    /// when every package disappeared. That is the only product path back to a
    /// built-in source after the last package is removed.
    static func showsMenu(hasOptions: Bool, selection: IconSlotBindingSelection) -> Bool {
        hasOptions || selection.hasExternalBinding
    }

    /// "Use Built-in Source" must not leave an external fallback behind.
    static func builtinFallback(for selection: IconSlotBindingSelection) -> IconContentBinding? {
        selection.fallback?.isBuiltinSource == true ? selection.fallback : nil
    }
}

/// A compact source menu for packages enabled under **App Icon → Local JSON
/// Plugins**. Built-in choices stay on the existing picker; this row only adds
/// the external presentations that the picker cannot represent.
struct LocalIconPluginSlotPicker: View {
    let slot: IconSlot
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization
    @StateObject private var model = LocalIconPluginCatalogModel()

    private var options: [LocalIconPluginSlotOption] {
        LocalIconPluginSlotCatalog.options(for: slot, in: model.catalog)
    }

    private var selection: IconSlotBindingSelection {
        store.iconSlotBindings.selection(for: slot)
    }

    var body: some View {
        content
            .task(id: store.localIconPluginDirectories) {
                await model.reload(directories: store.resolvedLocalIconPluginDirectories())
            }
    }

    @ViewBuilder
    private var content: some View {
        // Keep the menu reachable when every package disappeared: an external
        // primary without a readable package must still offer "Use Built-in
        // Source", otherwise the slot has no product path back.
        if store.isLocalIconPluginEntryAvailable,
           LocalIconPluginSlotPickerPolicy.showsMenu(hasOptions: !options.isEmpty, selection: selection) {
            SettingsDivider(inset: SettingsMetrics.rowPaddingH)
            SettingsRow(
                "doc.text",
                tint: .teal,
                title: localization.string(.settingsLocalPluginsSourceTitle)
            ) {
                Menu {
                    Button(localization.string(.settingsLocalPluginsBuiltinSource)) {
                        restoreBuiltin()
                    }
                    Divider()
                    ForEach(options) { option in
                        Button(option.title) {
                            store.selectExternalIconSlotSource(option.binding, for: slot)
                        }
                    }
                } label: {
                    Text(currentTitle)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("appIcon.localPlugin.\(slot.rawValue)")
            }
        }
    }

    private var currentTitle: String {
        guard let primary = selection.primary else {
            return localization.string(.settingsLocalPluginsBuiltinSource)
        }
        if let option = options.first(where: { $0.binding == primary }) {
            return option.title
        }
        if primary.pluginID.hasPrefix("builtin.") {
            return localization.string(.settingsLocalPluginsBuiltinSource)
        }
        return "\(primary.pluginID) — \(primary.presentationID)"
    }

    private func restoreBuiltin() {
        // "Use Built-in Source" removes external bindings entirely; keeping an
        // external fallback would leave this row visible while the built-in
        // source already draws.
        let fallback = LocalIconPluginSlotPickerPolicy.builtinFallback(for: selection)
        store.setIconSlotBinding(primary: builtinBinding, fallback: fallback, for: slot)
    }

    private var builtinBinding: IconContentBinding? {
        switch slot {
        case .outerRing:
            let source: RingSource
            switch store.outerRingContent {
            case .systemBattery: source = .systemBattery
            case .airPodsBattery: source = .airPodsBattery
            case .hardwareMonitor: source = .hardwareMonitor
            }
            return IconContentLegacyAdapter.binding(for: source)
        case .footer:
            return IconContentLegacyAdapter.binding(for: store.bottomIndicatorSource)
        case .center:
            let source: CenterSource
            switch store.connectionCenterSource {
            case .network: source = .network
            case .bluetoothDevice: source = .connectedBluetoothDevice
            case .inputSource: source = .inputSource
            case .batteryPercentage: source = .systemBatteryPercentage
            case .power: source = .power
            case .chargingStatus: source = .chargingStatus
            }
            return IconContentLegacyAdapter.binding(for: source)
        }
    }
}

/// One enabled directory as shown in the management list.
///
/// The row is keyed by the directory the user enabled, not by a successfully
/// loaded package, so a malformed manifest or a duplicate plugin ID can still be
/// removed without editing preferences by hand.
struct LocalIconPluginManageableDirectory: Identifiable, Equatable {
    let directory: URL
    let pluginID: String?
    let title: String

    var id: String { directory.path }
    var isValidPackage: Bool { pluginID != nil }
}

enum LocalIconPluginManageableDirectories {
    static func build(
        enabledPaths: [String],
        catalog: LocalIconPluginCatalog
    ) -> [LocalIconPluginManageableDirectory] {
        var seen = Set<String>()
        let packages = Dictionary(
            catalog.packages.map { ($0.directory.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return enabledPaths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let package = packages[path]
            return LocalIconPluginManageableDirectory(
                directory: url,
                pluginID: package?.manifest.pluginID,
                title: package?.manifest.title ?? url.lastPathComponent
            )
        }
    }
}

/// Enables and removes the directories the user explicitly authorizes.
struct LocalIconPluginPackageSettings: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization
    @StateObject private var model = LocalIconPluginCatalogModel()
    @State private var isImporting = false

    private var rows: [LocalIconPluginManageableDirectory] {
        LocalIconPluginManageableDirectories.build(
            enabledPaths: store.localIconPluginDirectories,
            catalog: model.catalog
        )
    }

    @ViewBuilder
    var body: some View {
        // A sandboxed build has no verified external-folder authorization in
        // this branch, so the whole entry is hidden rather than advertising a
        // folder picker that could not be read after a restart.
        if store.isLocalIconPluginEntryAvailable {
            SettingsGroup(localization.string(.settingsLocalPluginsTitle)) {
                ForEach(rows) { row in
                    SettingsRow(
                        row.isValidPackage ? "doc.text" : "exclamationmark.triangle.fill",
                        tint: row.isValidPackage ? .teal : .orange,
                        title: row.title,
                        subtitle: row.pluginID ?? localization.string(.settingsLocalPluginsLoadFailed)
                    ) {
                        Button(localization.string(.settingsLocalPluginsRemove)) {
                            store.removeLocalIconPluginDirectory(row.directory)
                        }
                        .buttonStyle(.borderless)
                    }
                    SettingsDivider()
                }
                SettingsRow(
                    "doc.badge.plus",
                    tint: .teal,
                    title: localization.string(.settingsLocalPluginsAdd)
                ) {
                    Button(localization.string(.settingsLocalPluginsAdd)) {
                        isImporting = true
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                store.addLocalIconPluginDirectory(url)
                Task {
                    await model.reload(directories: store.resolvedLocalIconPluginDirectories())
                }
            }
            .task(id: store.localIconPluginDirectories) {
                await model.reload(directories: store.resolvedLocalIconPluginDirectories())
            }
        }
    }
}
