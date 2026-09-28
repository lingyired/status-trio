import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BatteryActionSettingsView: View {
    @ObservedObject var store: SettingsStore
    let launcher: BatteryActionLauncher

    @EnvironmentObject private var localization: Localization
    @State private var installedApps: [KnownBatteryAppID] = []
    @State private var customApplicationAvailable = true

    var body: some View {
        SettingsGroup(
            localization.string(.settingsBatteryActionTitle),
            footnote: localization.string(.settingsBatteryActionDescription)
        ) {
            SettingsRow(
                "battery.100percent",
                tint: .green,
                title: localization.string(.batteryActionChooseTarget)
            ) {
                Menu {
                    ForEach(
                        Self.choices(current: store.batteryActionTarget, installed: installedApps)
                    ) { choice in
                        Button {
                            select(choice)
                        } label: {
                            if choice == currentChoice {
                                Label(choiceLabel(choice), systemImage: "checkmark")
                            } else {
                                Text(choiceLabel(choice))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(currentSelectionName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(localization.string(.batteryActionChangeTarget))
            }

            if case .customURL = store.batteryActionTarget {
                SettingsDivider()
                customURLRow
                if let message = Self.invalidURLMessage(
                    for: customURLText,
                    localization: localization
                ) {
                    SettingsHintRow(text: message)
                }
            }

            if let message = Self.unavailableMessage(
                for: store.batteryActionTarget,
                installed: installedApps,
                customApplicationAvailable: customApplicationAvailable,
                localization: localization
            ) {
                SettingsDivider()
                SettingsHintRow(text: message)
            }
        }
        .onAppear {
            refreshAvailability()
        }
    }

    private var customURLRow: some View {
        SettingsRow(
            "link",
            tint: .blue,
            title: localization.string(.batteryActionCustomURL)
        ) {
            TextField(localization.string(.batteryActionCustomURL), text: customURLBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .accessibilityLabel(localization.string(.batteryActionCustomURL))
        }
    }

    private var customURLBinding: Binding<String> {
        Binding(
            get: {
                guard case .customURL(let value) = store.batteryActionTarget else { return "" }
                return value
            },
            set: { store.batteryActionTarget = .customURL($0) }
        )
    }

    private var customURLText: String {
        guard case .customURL(let value) = store.batteryActionTarget else { return "" }
        return value
    }

    private var currentChoice: BatteryActionChoice {
        switch store.batteryActionTarget {
        case .systemSettings:
            .systemSettings
        case .knownApp(let id):
            .knownApp(id)
        case .customApp:
            .customApplication
        case .customURL:
            .customURL
        }
    }

    private var currentSelectionName: String {
        BatteryActionPresentation.selectionName(
            for: store.batteryActionTarget,
            localization: localization
        )
    }

    private func choiceLabel(_ choice: BatteryActionChoice) -> String {
        switch choice {
        case .systemSettings:
            return localization.string(.batteryActionSystemSettings)
        case .knownApp(let id):
            let name = KnownBatteryApps.definition(for: id).displayName
            if id == selectedUnavailableKnownApp {
                return "\(name): \(localization.string(.batteryActionUnavailable))"
            }
            return name
        case .customApplication:
            return localization.string(.batteryActionCustomApplication)
        case .customURL:
            return localization.string(.batteryActionCustomURL)
        }
    }

    private var selectedUnavailableKnownApp: KnownBatteryAppID? {
        guard case .knownApp(let id) = store.batteryActionTarget,
              !installedApps.contains(id) else { return nil }
        return id
    }

    private func select(_ choice: BatteryActionChoice) {
        switch choice {
        case .systemSettings:
            store.batteryActionTarget = .systemSettings
        case .knownApp(let id):
            store.batteryActionTarget = .knownApp(id)
        case .customApplication:
            chooseApplication()
        case .customURL:
            if case .customURL = store.batteryActionTarget { return }
            store.batteryActionTarget = .customURL("")
        }
        refreshAvailability()
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK else { return }
        Self.applySelectedApplication(panel.url, to: store)
        refreshAvailability()
    }

    private func refreshAvailability() {
        installedApps = KnownBatteryAppID.allCases.filter { id in
            launcher.isInstalled(KnownBatteryApps.definition(for: id))
        }
        if case .customApp(let application) = store.batteryActionTarget {
            customApplicationAvailable = launcher.isAvailable(application: application)
        } else {
            customApplicationAvailable = true
        }
    }

    static func choices(
        current: BatteryActionTarget,
        installed: [KnownBatteryAppID]
    ) -> [BatteryActionChoice] {
        var result: [BatteryActionChoice] = [.systemSettings]
        for id in KnownBatteryAppID.allCases where installed.contains(id) || current == .knownApp(id) {
            result.append(.knownApp(id))
        }
        result.append(.customApplication)
        result.append(.customURL)
        return result
    }

    static func invalidURLMessage(for value: String, localization: Localization) -> String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              BatteryActionLauncher.validatedURL(value) == nil else {
            return nil
        }
        return localization.string(.batteryActionInvalidURL)
    }

    static func unavailableMessage(
        for target: BatteryActionTarget,
        installed: [KnownBatteryAppID],
        customApplicationAvailable: Bool,
        localization: Localization
    ) -> String? {
        let selectionName: String
        switch target {
        case .systemSettings, .customURL:
            return nil
        case .knownApp(let id):
            guard !installed.contains(id) else { return nil }
            selectionName = KnownBatteryApps.definition(for: id).displayName
        case .customApp(let application):
            guard !customApplicationAvailable else { return nil }
            selectionName = application.displayName
        }
        return "\(selectionName): \(localization.string(.batteryActionUnavailable))"
    }

    static func applySelectedApplication(_ url: URL?, to store: SettingsStore) {
        guard let url else { return }
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        store.batteryActionTarget = .customApp(ExternalApplicationTarget(
            displayName: displayName,
            bundleIdentifier: bundle?.bundleIdentifier,
            fallbackPath: url.path
        ))
    }
}
