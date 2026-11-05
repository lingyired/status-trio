import AppKit
import SwiftUI

/// The Brightness settings tab (#241/#239).
///
/// One row per connected display: a "show in the status panel" toggle and, for
/// external displays, the brightness backend choice (direct DDC or the optional
/// BetterDisplay backend). Built-in displays are fixed to DisplayServices, so
/// their row carries a read-only note instead of a picker.
///
/// A closing note explains the DDC compatibility limit and points at
/// BetterDisplay, because a display whose vendor DDC dialect Status Trio cannot
/// speak is still adjustable through that app.
struct BrightnessSectionView: View {
    /// The BetterDisplay project site, linked from the compatibility note.
    static let betterDisplayWebsiteURL = URL(string: "https://betterdisplay.pro")

    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            panelVisibilityGroup
            displaysGroup
            compatibilityGroup
        }
        .onAppear {
            // Reading brightness is demand-gated: keep it alive only while this
            // tab is on screen, so browsing another tab stops the DDC reads.
            statusStore.setBrightnessSettingsVisible(true)
        }
        .onDisappear {
            statusStore.setBrightnessSettingsVisible(false)
        }
    }

    /// Quick show/hide of the whole brightness module in the status panel.
    private var panelVisibilityGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkPanelGroup)) {
            SettingsToggleRow(
                symbol: PopupSection.brightness.systemImage,
                tint: .orange,
                title: localization.string(.settingsPanelShowBrightness),
                subtitle: localization.string(.settingsPanelShowItemDescription),
                isOn: Binding(
                    get: { store.enabledPopupSections.contains(.brightness) },
                    set: { store.setPopupSection(.brightness, enabled: $0) }
                )
            )
        }
    }

    private var displays: [DisplayBrightness] {
        statusStore.liveBrightness.displays
    }

    private var displaysGroup: some View {
        SettingsGroup(
            localization.string(.settingsBrightnessGroupTitle),
            footnote: localization.string(.settingsBrightnessDescription)
        ) {
            if displays.isEmpty {
                SettingsHintRow(text: localization.string(.settingsBrightnessEmpty))
            } else {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    if index > 0 {
                        SettingsDivider()
                    }
                    displayRow(for: display)
                }
            }
        }
    }

    /// Closing note for displays Status Trio cannot drive directly: vendor DDC
    /// implementations differ, so the honest answer is to hand those displays to
    /// a dedicated app rather than claim full coverage.
    ///
    /// The link is its own button under the paragraph rather than an inline
    /// `subtitleLink`: that keeps only the link tappable and stops a long label
    /// from breaking mid-word inside the sentence.
    private var compatibilityGroup: some View {
        SettingsGroup {
            SettingsCustomRow(
                title: localization.string(.settingsBrightnessCompatibilityTitle),
                subtitle: localization.string(.settingsBrightnessCompatibilityDescription),
                leading: {
                    SettingsIcon(symbol: "questionmark.circle", tint: .secondary)
                },
                content: {
                    Button(localization.string(.settingsBrightnessCompatibilityLink)) {
                        openBetterDisplayWebsite()
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            )
        }
    }

    private func openBetterDisplayWebsite() {
        guard let url = Self.betterDisplayWebsiteURL else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func displayRow(for display: DisplayBrightness) -> some View {
        SettingsRow(
            display.isBuiltin ? "laptopcomputer" : "display",
            tint: display.isBuiltin ? .teal : .orange,
            title: display.name,
            subtitle: display.isBuiltin
                ? localization.string(.settingsBrightnessInternalBackendDescription)
                : localization.string(.settingsBrightnessExternalBackendDescription)
        ) {
            HStack(spacing: 12) {
                if display.isBuiltin {
                    Text(localization.string(.settingsBrightnessBuiltIn))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                } else {
                    Picker(
                        localization.string(.settingsBrightnessBackend),
                        selection: backendBinding(for: display)
                    ) {
                        ForEach(externalBackendOptions, id: \.self) { backend in
                            Text(backendLabel(backend)).tag(backend)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .settingsMenuPickerWidth()
                    .accessibilityIdentifier("settings.brightness.backend.\(display.id)")
                }

                Toggle(
                    localization.string(.settingsBrightnessGroupTitle),
                    isOn: Binding(
                        get: { !store.hiddenBrightnessDisplayIDs.contains(display.id) },
                        set: { store.setBrightnessDisplayHidden(display.id, hidden: !$0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityIdentifier("settings.brightness.display.\(display.id)")
            }
        }

        if !display.isBuiltin, shouldShowBetterDisplayHint(for: display) {
            SettingsDivider()
            SettingsHintRow(
                text: localization.string(.settingsBrightnessBackendBetterDisplayNeeded)
            )
        }
    }

    /// The backend the row currently stores. External displays only ever use
    /// direct DDC or BetterDisplay; built-in displays are excluded from the
    /// picker entirely.
    private func backendBinding(for display: DisplayBrightness) -> Binding<BrightnessBackend> {
        Binding(
            get: { store.externalBrightnessConfiguration(for: display.id).backend },
            set: { backend in
                let current = store.externalBrightnessConfiguration(for: display.id)
                let updated = ExternalBrightnessConfiguration(
                    backend: backend,
                    betterDisplayUUID: backend == .betterDisplay
                        ? current.betterDisplayUUID
                        : nil
                )
                store.setExternalBrightnessConfiguration(updated, for: display.id)
            }
        )
    }

    private func backendLabel(_ backend: BrightnessBackend) -> String {
        switch backend {
        case .directDDC, .displayServices:
            return localization.string(.brightnessBackendDirectDDC)
        case .betterDisplay:
            return localization.string(.brightnessBackendBetterDisplay)
        }
    }

    /// The choices an external display can store: direct DDC (the default) or
    /// the optional BetterDisplay backend. DisplayServices is built-in only.
    private var externalBackendOptions: [BrightnessBackend] {
        [.directDDC, .betterDisplay]
    }

    /// When BetterDisplay is selected but the app is not running (or its
    /// notification integration is off) the row explains why the panel row
    /// reads "Requires BetterDisplay".
    private func shouldShowBetterDisplayHint(for display: DisplayBrightness) -> Bool {
        guard store.externalBrightnessConfiguration(for: display.id).backend == .betterDisplay
        else { return false }
        return statusStore.betterDisplayAvailability == .appAbsent
    }
}
