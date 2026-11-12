import AppKit
import SwiftUI

/// The four top-marker choices exposed in the settings pane. Mapped to/from
/// `HardwareRingTopContent`, which carries the metric for the symbol/value cases.
private enum HardwareTopMode: String, CaseIterable, Identifiable {
    case automatic
    case symbol
    case value
    case hidden
    var id: Self { self }
}

/// The "Ring" leaf under **App Icon**: how the battery arc / ring is drawn.
///
/// These controls used to sit in the Battery category, but they only describe
/// the icon's appearance, so they now live with the icon. The page is split into
/// top markers, progress, colours and animations. The actual charging controls
/// (temporary full charge, restore limit) stay in Battery → Charging.
struct AppIconRingView: View {
    @ObservedObject var store: SettingsStore
    /// Whether the Mac actually has a battery. A desktop (e.g. Mac mini) has no
    /// real level, so the ring controls collapse to a decorative top marker.
    var hasBattery: Bool = true
    /// Omitted on the dedicated "Ring" page, where the page title already names
    /// the section (like the middle-icon group); kept when the ring group sits
    /// among the other icon groups.
    var showsRingContentTitle: Bool = true
    @EnvironmentObject private var localization: Localization

    /// The battery presence this page draws with. In a development build the
    /// no-battery simulation forces the battery-less look so the UI can be
    /// checked on a Mac that has a battery.
    private var effectiveHasBattery: Bool {
        hasBattery && !store.isNoBatterySimulationActive
    }

    var body: some View {
        if !effectiveHasBattery {
            noBatteryHintGroup
        }
        outerRingContentGroup
        if store.outerRingContent == .airPodsBattery {
            airPodsTopMarkerGroup
            airPodsArcGroup
            airPodsFallbackGroup
        } else if store.outerRingContent == .hardwareMonitor {
            hardwareRingGroups
        } else {
            // #309: every battery ring control stays visible without a battery.
            // The settings are kept; the ring colour still follows connected
            // power and Low/High Power Mode, while the level and charging marker
            // do not apply. The hint above says so.
            // Unified order: top marker → progress → colours → animations.
            batteryTopMarkerGroup
            progressGroup
            colorsGroup
            effectsGroup
        }
    }

    // MARK: Outer ring content

    /// Chooses what the ring shows: the Mac battery (with all the existing
    /// battery options below it) or the AirPods battery. Uses the same shared
    /// picture-card picker as the middle-icon source chooser so the two rows
    /// share one layout and interaction contract.
    ///
    /// The top-marker options belong to the Mac battery source, so they sit in
    /// the same card as the picker (like the middle-icon source picker owns its
    /// sub-options) and only appear while the Mac battery is selected.
    private var outerRingContentGroup: some View {
        // The subtopic already names this page, so the dedicated ring page drops
        // the extra group heading (matching the middle-icon page); the full App
        // Icon overview keeps it so the section stays labelled among the others.
        SettingsGroup(
            showsRingContentTitle ? localization.string(.settingsRingContentGroupTitle) : nil
        ) {
            SettingsVisualChoicePicker(
                descriptionText: localization.string(.settingsRingContentRowDescription),
                choicesAccessibilityLabel: localization.string(.settingsRingContentRowTitle),
                accessibilityIdentifier: "appIcon.outerRingContent",
                selection: $store.outerRingContent,
                options: OuterRingContent.allCases,
                caption: { ringContentLabel($0) },
                preview: { OuterRingContentPreview(content: $0, store: store) }
            )

            if store.outerRingContent == .systemBattery, store.isDevelopmentBuild {
                // Developer-only helper: force the battery-less look so a Mac
                // with a battery can preview this page without one. It lives in
                // the Mac battery card and a packaged release never shows it.
                SettingsDivider(inset: SettingsMetrics.rowPaddingH)
                SettingsToggleRow(
                    symbol: "eyeglasses",
                    tint: .gray,
                    title: localization.string(.settingsBatterySimulateNoBattery),
                    subtitle: localization.string(.settingsBatterySimulateNoBatteryDescription),
                    isOn: $store.simulatesNoBattery
                )
            }
        }
    }

    /// Mac battery top-marker card. Pulled out of the picker card so every
    /// source starts with the same「顶部标识」group; the shared size row is the
    /// first row, then the per-power-state marker choices.
    private var batteryTopMarkerGroup: some View {
        SettingsGroup(localization.string(.settingsTopMarkerGroup)) {
            if store.isBatterySymbolSizeEnabled {
                topMarkerSizeRow
                SettingsDivider()
            }
            topMarkersContent
        }
    }

    private func ringContentLabel(_ content: OuterRingContent) -> String {
        switch content {
        case .systemBattery: return localization.string(.settingsRingContentSystemBattery)
        case .airPodsBattery: return localization.string(.settingsRingContentAirPodsBattery)
        case .hardwareMonitor: return localization.string(.settingsRingContentHardwareMonitor)
        }
    }

    /// AirPods-ring options: two-arc layout, the small top glyph, and whether an
    /// unavailable AirPods ring falls back to the Mac battery ring.
    /// AirPods top-marker card: shared size row first, then the AirPods glyph
    /// toggle. Split out of the old single AirPods card so this source also
    /// starts with a「顶部标识」group.
    private var airPodsTopMarkerGroup: some View {
        SettingsGroup(localization.string(.settingsTopMarkerGroup)) {
            if store.showsAirPodsTopSymbolInRing {
                topMarkerSizeRow
                SettingsDivider()
            }
            SettingsToggleRow(
                symbol: "airpods",
                tint: .blue,
                title: localization.string(.settingsRingAirPodsTopSymbol),
                subtitle: localization.string(.settingsRingAirPodsTopSymbolDescription),
                isOn: $store.showsAirPodsTopSymbolInRing
            )
        }
    }

    /// AirPods arc layout (single vs left/right dual).
    private var airPodsArcGroup: some View {
        SettingsGroup(localization.string(.settingsHardwareRingGroupArc)) {
            SettingsToggleRow(
                symbol: "airpods",
                tint: .blue,
                title: localization.string(.settingsRingAirPodsDualRing),
                subtitle: localization.string(.settingsRingAirPodsDualRingDescription),
                isOn: $store.airPodsRingUsesDualRing
            )
        }
    }

    /// Fallback when no AirPods are connected / readable.
    private var airPodsFallbackGroup: some View {
        SettingsGroup {
            SettingsToggleRow(
                symbol: "battery.100",
                tint: .green,
                title: localization.string(.settingsRingAirPodsFallback),
                subtitle: localization.string(.settingsRingAirPodsFallbackDescription),
                isOn: $store.airPodsRingFallsBackToBattery
            )
        }
    }

    // MARK: System monitoring (hardware ring)

    /// Internal settings for the `hardwareMonitor` source: arc layout, metrics,
    /// top marker, colour strategy and per-metric thresholds. These are grouped
    /// exactly like the other icon pickers — no bespoke control style is
    /// introduced; they reuse `SettingsGroup` / `SettingsMenuRow` / `SettingsRow`.
    @ViewBuilder
    private var hardwareRingGroups: some View {
        hardwareTopGroup
        hardwareArcGroup
        hardwareColorGroup
        hardwareAdvancedGroup
    }

    private var hardwareSecondaryMetric: HardwareMonitorMetric {
        store.hardwareRingConfiguration.normalizedSecondaryMetric ?? .gpuUsage
    }

    private var hardwareArcGroup: some View {
        SettingsGroup(localization.string(.settingsHardwareRingGroupArc)) {
            SettingsMenuRow(
                symbol: "circle.dashed",
                tint: .blue,
                title: localization.string(.settingsHardwareRingLayout),
                selection: Binding(
                    get: { store.hardwareRingConfiguration.layout },
                    set: { setHardwareLayout($0) }
                ),
                options: HardwareRingLayout.allCases,
                label: { layoutLabel($0) }
            )
            SettingsDivider()
            SettingsMenuRow(
                symbol: store.hardwareRingConfiguration.primaryMetric.systemImage,
                tint: .green,
                title: localization.string(.settingsHardwareRingPrimaryMetric),
                selection: Binding(
                    get: { store.hardwareRingConfiguration.primaryMetric },
                    set: { setPrimaryMetric($0) }
                ),
                options: HardwareMonitorMetric.allCases,
                label: { metricLabel($0) }
            )
            if store.hardwareRingConfiguration.layout == .dual {
                SettingsDivider()
                SettingsMenuRow(
                    symbol: hardwareSecondaryMetric.systemImage,
                    tint: .blue,
                    title: localization.string(.settingsHardwareRingSecondaryMetric),
                    selection: Binding(
                        get: { hardwareSecondaryMetric },
                        set: { setSecondaryMetric($0) }
                    ),
                    options: HardwareMonitorMetric.allCases,
                    label: { metricLabel($0) }
                )
            }
        }
    }

    private var hardwareTopGroup: some View {
        SettingsGroup(localization.string(.settingsTopMarkerGroup)) {
            if hardwareTopMode != .hidden {
                topMarkerSizeRow
                SettingsDivider()
            }
            SettingsMenuRow(
                symbol: "textformat",
                tint: .gray,
                title: localization.string(.settingsHardwareRingTopContent),
                selection: Binding(
                    get: { hardwareTopMode },
                    set: { setTopMode($0) }
                ),
                options: HardwareTopMode.allCases,
                label: { topModeLabel($0) }
            )
            if hardwareTopMode == .symbol || hardwareTopMode == .value {
                SettingsDivider()
                SettingsMenuRow(
                    symbol: hardwareTopMetric.systemImage,
                    tint: .gray,
                    title: localization.string(.settingsHardwareRingTopMetric),
                    selection: Binding(
                        get: { hardwareTopMetric },
                        set: { setTopMetric($0) }
                    ),
                    options: HardwareMonitorMetric.allCases,
                    label: { metricLabel($0) }
                )
            }
        }
    }

    /// One shared "top marker size" standard: the same value drives the Mac
    /// battery percentage/bolt, the AirPods top symbol and the hardware top
    /// marker. Shown wherever a top marker can be configured, editing any of
    /// them writes this single setting.
    private var topMarkerSizeRow: some View {
        SettingsRow(
            title: localization.string(.settingsTopMarkerScale),
            subtitle: localization.string(.settingsTopMarkerScaleDescription),
            leading: { SettingsIcon(symbol: "arrow.up.left.and.arrow.down.right", tint: .gray) },
            trailing: {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.batterySymbolScale },
                            set: { store.setBatterySymbolScaleFromSlider(($0 * 20).rounded() / 20) }
                        ),
                        in: SettingsStore.batterySymbolScaleRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsTopMarkerScale))
                    .accessibilityValue("\(Int(store.batterySymbolScale * 100))%")
                    Text("\(Int(store.batterySymbolScale * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        )
    }

    private var hardwareColorGroup: some View {
        SettingsGroup(localization.string(.settingsHardwareRingGroupColor)) {
            SettingsMenuRow(
                symbol: "paintpalette",
                tint: .purple,
                title: localization.string(.settingsHardwareRingColorMode),
                subtitle: colorModeDescription(store.hardwareRingConfiguration.color.mode),
                selection: Binding(
                    get: { store.hardwareRingConfiguration.color.mode },
                    set: { setColorMode($0) }
                ),
                options: HardwareRingColorMode.allCases,
                label: { colorModeLabel($0) }
            )
            if store.hardwareRingConfiguration.color.mode != .monochrome {
                SettingsDivider()
                hardwareColorRow(
                    title: .settingsHardwareRingLeftColor,
                    metric: store.hardwareRingConfiguration.primaryMetric
                )
                if store.hardwareRingConfiguration.layout == .dual {
                    SettingsDivider()
                    hardwareColorRow(
                        title: .settingsHardwareRingRightColor,
                        metric: hardwareSecondaryMetric
                    )
                }
            }
        }
    }

    private var hardwareAdvancedGroup: some View {
        SettingsGroup(localization.string(.settingsHardwareRingGroupAdvanced)) {
            ForEach(Array(store.hardwareRingConfiguration.referencedMetrics.enumerated()), id: \.element) { index, metric in
                if index > 0 { SettingsDivider() }
                hardwareAdvancedRow(for: metric)
            }
            SettingsDivider()
            SettingsRow(
                title: localization.string(.settingsHardwareRingReset),
                subtitle: nil,
                leading: { SettingsIcon(symbol: "arrow.counterclockwise", tint: .gray) },
                trailing: {
                    Button(localization.string(.settingsHardwareRingReset)) {
                        resetHardwareMetricOptions()
                    }
                    .controlSize(.small)
                }
            )
        }
    }

    @ViewBuilder
    private func hardwareAdvancedRow(for metric: HardwareMonitorMetric) -> some View {
        let options = store.hardwareRingConfiguration.options(for: metric)
        SettingsRow(
            title: metricLabel(metric),
            subtitle: hardwareRangeSubtitle(metric: metric, options: options),
            leading: { SettingsIcon(symbol: metric.systemImage, tint: .orange) },
            trailing: {
                VStack(alignment: .trailing, spacing: 6) {
                    hardwareStepper(
                        label: localization.string(.settingsHardwareRingWarning),
                        value: hardwareOptionBinding(metric, \HardwareMetricRingOptions.warningThreshold),
                        range: hardwareStepperRange(metric),
                        step: metric == .fan ? 100 : 1
                    )
                    hardwareStepper(
                        label: localization.string(.settingsHardwareRingCritical),
                        value: hardwareOptionBinding(metric, \HardwareMetricRingOptions.criticalThreshold),
                        range: hardwareStepperRange(metric),
                        step: metric == .fan ? 100 : 1
                    )
                    if !metric.isPercentageMetric && metric != .fan {
                        hardwareStepper(
                            label: "\(localization.string(.settingsHardwareRingRange)) ↓",
                            value: hardwareOptionBinding(metric, \HardwareMetricRingOptions.displayMinimum),
                            range: -50...150,
                            step: 1
                        )
                        hardwareStepper(
                            label: "\(localization.string(.settingsHardwareRingRange)) ↑",
                            value: hardwareOptionBinding(metric, \HardwareMetricRingOptions.displayMaximum),
                            range: -50...150,
                            step: 1
                        )
                    }
                }
            }
        )
    }

    private func hardwareStepper(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Stepper(value: value, in: range, step: step) {
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
            .controlSize(.small)
        }
    }

    private func hardwareColorRow(
        title: LocalizationKey,
        metric: HardwareMonitorMetric
    ) -> some View {
        SettingsRow(
            title: localization.string(title),
            subtitle: metricLabel(metric),
            leading: { SettingsIcon(symbol: metric.systemImage, tint: .purple) },
            trailing: {
                IconDesignerColorWell(
                    selection: hardwareColorBinding(metric: metric),
                    onEditingChanged: { _ in }
                )
                .frame(width: 44, height: 22)
            }
        )
    }

    // MARK: Hardware ring bindings & labels

    private var hardwareTopMode: HardwareTopMode {
        switch store.hardwareRingConfiguration.topContent {
        case .automatic: return .automatic
        case .hidden: return .hidden
        case .symbol: return .symbol
        case .value: return .value
        }
    }

    private var hardwareTopMetric: HardwareMonitorMetric {
        store.hardwareRingConfiguration.topContent.referencedMetric
            ?? store.hardwareRingConfiguration.primaryMetric
    }

    private func setHardwareLayout(_ layout: HardwareRingLayout) {
        var configuration = store.hardwareRingConfiguration
        configuration.layout = layout
        if layout == .dual, configuration.secondaryMetric == nil {
            configuration.secondaryMetric = HardwareRingConfiguration.default.secondaryMetric
        }
        store.hardwareRingConfiguration = configuration
    }

    private func setPrimaryMetric(_ metric: HardwareMonitorMetric) {
        var configuration = store.hardwareRingConfiguration
        if configuration.secondaryMetric == metric {
            configuration.secondaryMetric = configuration.primaryMetric
        }
        configuration.primaryMetric = metric
        if configuration.layout == .single { configuration.secondaryMetric = nil }
        store.hardwareRingConfiguration = configuration
    }

    private func setSecondaryMetric(_ metric: HardwareMonitorMetric) {
        var configuration = store.hardwareRingConfiguration
        if metric == configuration.primaryMetric {
            configuration.primaryMetric = configuration.normalizedSecondaryMetric ?? .gpuUsage
        }
        configuration.secondaryMetric = metric
        store.hardwareRingConfiguration = configuration
    }

    private func setTopMode(_ mode: HardwareTopMode) {
        var configuration = store.hardwareRingConfiguration
        let metric = hardwareTopMetric
        switch mode {
        case .automatic: configuration.topContent = .automatic
        case .hidden: configuration.topContent = .hidden
        case .symbol: configuration.topContent = .symbol(metric)
        case .value: configuration.topContent = .value(metric)
        }
        store.hardwareRingConfiguration = configuration
    }

    private func setTopMetric(_ metric: HardwareMonitorMetric) {
        var configuration = store.hardwareRingConfiguration
        switch hardwareTopMode {
        case .symbol: configuration.topContent = .symbol(metric)
        case .value: configuration.topContent = .value(metric)
        case .automatic, .hidden: break
        }
        store.hardwareRingConfiguration = configuration
    }

    private func setColorMode(_ mode: HardwareRingColorMode) {
        var configuration = store.hardwareRingConfiguration
        configuration.color.mode = mode
        store.hardwareRingConfiguration = configuration
    }

    /// Shared per-metric colour: the same field the status-panel bar uses and the
    /// monitor tab edits. Switching the side's metric switches which colour this
    /// well shows and writes.
    private func hardwareColorBinding(metric: HardwareMonitorMetric) -> Binding<Color> {
        Binding(
            get: { IconAppearanceColorConversion.color(from: store.hardwareColor(for: metric)) },
            set: { color in
                store.setHardwareColor(IconAppearanceColorConversion.iconRGBA(from: color), for: metric)
            }
        )
    }

    private func hardwareOptionBinding(
        _ metric: HardwareMonitorMetric,
        _ keyPath: WritableKeyPath<HardwareMetricRingOptions, Double>
    ) -> Binding<Double> {
        Binding(
            get: { store.hardwareRingConfiguration.options(for: metric)[keyPath: keyPath] },
            set: { newValue in
                var configuration = store.hardwareRingConfiguration
                var options = configuration.options(for: metric)
                options[keyPath: keyPath] = newValue
                configuration.overrides[metric] = options.normalized(for: metric)
                store.hardwareRingConfiguration = configuration
            }
        )
    }

    private func resetHardwareMetricOptions() {
        var configuration = store.hardwareRingConfiguration
        for metric in configuration.referencedMetrics {
            configuration.overrides[metric] = nil
        }
        store.hardwareRingConfiguration = configuration
    }

    private func hardwareStepperRange(_ metric: HardwareMonitorMetric) -> ClosedRange<Double> {
        switch metric {
        case .cpuUsage, .gpuUsage, .memoryUsage: return 0...100
        case .cpuTemperature: return 30...120
        case .batteryTemperature: return 20...80
        case .fan: return 0...10_000
        }
    }

    private func hardwareRangeSubtitle(metric: HardwareMonitorMetric, options: HardwareMetricRingOptions) -> String? {
        guard !metric.isPercentageMetric, metric != .fan else { return nil }
        return "\(localization.string(.settingsHardwareRingRange)): \(Int(options.displayMinimum))–\(Int(options.displayMaximum))°C"
    }

    private func layoutLabel(_ layout: HardwareRingLayout) -> String {
        switch layout {
        case .single: return localization.string(.settingsHardwareRingLayoutSingle)
        case .dual: return localization.string(.settingsHardwareRingLayoutDual)
        }
    }

    private func metricLabel(_ metric: HardwareMonitorMetric) -> String {
        localization.string(metric.titleKey)
    }

    private func colorModeLabel(_ mode: HardwareRingColorMode) -> String {
        switch mode {
        case .status: return localization.string(.settingsHardwareRingColorStatus)
        case .fixed: return localization.string(.settingsHardwareRingColorFixed)
        case .monochrome: return localization.string(.settingsHardwareRingColorMonochrome)
        }
    }

    private func colorModeDescription(_ mode: HardwareRingColorMode) -> String {
        switch mode {
        case .status: return localization.string(.settingsHardwareRingColorStatusDescription)
        case .fixed: return localization.string(.settingsHardwareRingColorFixedDescription)
        case .monochrome: return localization.string(.settingsHardwareRingColorMonochromeDescription)
        }
    }

    private func topModeLabel(_ mode: HardwareTopMode) -> String {
        switch mode {
        case .automatic: return localization.string(.settingsHardwareRingTopAutomatic)
        case .symbol: return localization.string(.settingsHardwareRingTopSymbol)
        case .value: return localization.string(.settingsHardwareRingTopValue)
        case .hidden: return localization.string(.settingsHardwareRingTopHidden)
        }
    }

    /// Explains what still applies on a battery-less Mac (ring colour follows
    /// connected power and Low/High Power Mode) and what does not (percentage,
    /// charging marker), so the kept controls are not misleading.
    private var noBatteryHintGroup: some View {        SettingsGroup {
            SettingsHintRow(text: localization.string(.settingsBatteryNoBatteryHiddenOptions))
        }
    }

    // MARK: Top markers

    /// Top-marker rows, without their own card: they are embedded in the
    /// ring-content card while the Mac battery source is selected.
    private var topMarkersContent: some View {
        Group {
            if effectiveHasBattery {
                // #315: one plain choice per power state, so the plug and bolt no
                // longer hide behind a "show percentage" toggle or a combined
                // "connected without charging" option.
                markerRow(
                    symbol: "percent",
                    tint: .green,
                    title: .settingsBatteryMarkerOnBattery,
                    selection: $store.batteryOnBatteryMarker,
                    options: BatteryTopMarker.onBatteryOptions
                )

                SettingsDivider()

                markerRow(
                    symbol: "bolt.fill",
                    tint: .yellow,
                    title: .settingsBatteryMarkerCharging,
                    selection: $store.batteryChargingMarker,
                    options: BatteryTopMarker.onPowerOptions
                )

                SettingsDivider()

                markerRow(
                    symbol: "powerplug.portrait.fill",
                    tint: .teal,
                    title: .settingsBatteryMarkerConnected,
                    selection: $store.batteryConnectedMarker,
                    options: BatteryTopMarker.onPowerOptions
                )
            } else {
                // A Mac with no battery: the only top marker to configure is a
                // decorative plug / bolt (or nothing).
                markerRow(
                    symbol: "bolt.fill",
                    tint: .yellow,
                    title: .settingsBatteryNoBatteryTopIndicator,
                    selection: $store.batteryNoBatteryMarker,
                    options: BatteryTopMarker.noBatteryOptions
                )
            }
        }
    }

    private func markerRow(
        symbol: String,
        tint: Color,
        title: LocalizationKey,
        selection: Binding<BatteryTopMarker>,
        options: [BatteryTopMarker]
    ) -> some View {
        SettingsMenuRow(
            symbol: symbol,
            tint: tint,
            title: localization.string(title),
            selection: selection,
            options: options,
            label: markerLabel
        )
    }

    private func markerLabel(_ marker: BatteryTopMarker) -> String {
        switch marker {
        case .percentage:
            localization.string(.settingsBatteryConnectedIndicatorPercentage)
        case .bolt:
            localization.string(.settingsBatteryConnectedIndicatorBolt)
        case .plug:
            localization.string(.settingsBatteryConnectedIndicatorPlug)
        case .hidden:
            localization.string(.settingsBatteryMarkerHidden)
        }
    }

    // MARK: Progress

    private var progressGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupProgress)) {
            SettingsToggleRow(
                symbol: "circle.lefthalf.filled",
                tint: .blue,
                title: localization.string(.settingsBatterySplitGapProgress),
                subtitle: localization.string(.settingsBatterySplitGapProgressDescription),
                isOn: $store.batterySplitGapProgress
            )

            SettingsDivider()

            fullThresholdRow

            systemChargeLimitUnavailableNote
        }
    }

    /// Full-ring visual threshold (how complete the ring reads), not a charging
    /// limit. Kept apart from the real charge management controls.
    private var fullThresholdRow: some View {
        SettingsRow(
            "battery100.bolt",
            tint: .green,
            title: localization.string(.settingsBatteryFullThreshold),
            subtitle: localization.string(.settingsBatteryFullThresholdDescription),
            subtitleLink: Text(
                localization.string(.settingsBatteryFullThresholdUseChargeLimit)
            )
            .foregroundColor(Color.accentColor),
            subtitleLinkAction: {
                store.applySystemChargeLimit()
            },
            trailing: {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.batteryFullThreshold },
                            set: { store.batteryFullThreshold = $0.rounded() }
                        ),
                        in: SettingsStore.batteryFullThresholdRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(
                        localization.string(.settingsBatteryFullThreshold)
                    )
                    .accessibilityValue("\(Int(store.batteryFullThreshold))%")

                    Text("\(Int(store.batteryFullThreshold))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        )
    }

    @ViewBuilder
    private var systemChargeLimitUnavailableNote: some View {
        // Shown only after the user pressed “使用充电上限” and the private plist
        // could not be read. Not proactive: an idle page stays quiet.
        if store.batteryFullThresholdReadFailed {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.secondary)
                (
                    Text(localization.string(
                        .settingsBatteryFullThresholdSystemUnavailable
                    ))
                    + Text(" ")
                    + Text(localization.string(
                        .settingsBatteryFullThresholdOpenSystemSettings
                    ))
                    .foregroundColor(Color.accentColor)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { openBatteryChargeSettings() }
                .accessibilityAddTraits(.isLink)
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.bottom, 6)
        }
    }

    /// Opens System Settings at Battery → Charging, where the user can read the
    /// real charge limit that this machine does not expose through a public API.
    private func openBatteryChargeSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: Colours

    private var colorsGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupColors)) {
            // #309: use black/white for the charging / connected state, while
            // Low/High Power Mode and critical keep their own colours. nil means
            // automatic — on by default on a battery-less Mac, off otherwise.
            SettingsToggleRow(
                symbol: "circle.lefthalf.filled",
                tint: .gray,
                title: localization.string(.settingsBatteryMonochromeCharging),
                subtitle: localization.string(.settingsBatteryMonochromeChargingDescription),
                isOn: Binding(
                    get: { store.monochromeChargingRing ?? !effectiveHasBattery },
                    set: { store.monochromeChargingRing = $0 }
                )
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "paintpalette.fill",
                tint: .orange,
                title: localization.string(.settingsBatteryStatusColors),
                subtitle: localization.string(.settingsBatteryStatusColorsDescription),
                isOn: $store.usesBatteryStatusColors
            )

            BatteryStatusColorsView(store: store)

            if store.usesBatteryStatusColors {
                SettingsDivider()

                SettingsRow(
                    "exclamationmark.triangle.fill",
                    tint: .red,
                    title: localization.string(.settingsBatteryCriticalThreshold),
                    subtitle:
                        localization.string(.settingsBatteryCriticalThresholdDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.batteryCriticalThreshold },
                                set: { store.batteryCriticalThreshold = $0.rounded() }
                            ),
                            in: SettingsStore.batteryCriticalThresholdRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryCriticalThreshold)
                        )
                        .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                        Text("\(Int(store.batteryCriticalThreshold))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Animations

    private var effectsGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupChargingEffects)) {
            SettingsToggleRow(
                symbol: "menubar.rectangle",
                tint: .green,
                title: localization.string(.settingsBatteryMenuBarChargingEffect),
                subtitle: localization.string(
                    .settingsBatteryMenuBarChargingEffectDescription
                ),
                isOn: $store.showsMenuBarChargingEffect
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "dock.rectangle",
                tint: .green,
                title: localization.string(.settingsBatteryDockChargingEffect),
                subtitle: localization.string(
                    .settingsBatteryDockChargingEffectDescription
                ),
                isOn: $store.showsDockChargingEffect
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: localization.string(.settingsBatteryChargingBoltHeartbeat),
                subtitle: localization.string(.settingsBatteryChargingBoltHeartbeatDescription),
                isOn: $store.showsChargingBoltHeartbeat
            )
            .disabled(!store.showsChargingEffect || store.batteryChargingMarker != .bolt)

            if ChargingEffectTestMode.isAvailable() {
                SettingsDivider()

                SettingsToggleRow(
                    symbol: SymbolFallback.name("flask.fill", "testtube.2"),
                    tint: .orange,
                    title: localization.string(.settingsBatteryChargingEffectTest),
                    subtitle: localization.string(.settingsBatteryChargingEffectTestDescription),
                    isOn: Binding(
                        get: { store.testsChargingEffect },
                        set: { store.setChargingEffectTestEnabled($0) }
                    )
                )
                .disabled(!store.showsChargingEffect)
            }
        }
    }
}

/// A small picture tile for the ring-content picker. It renders the real Status
/// Trio icon scene for a fixed sample status through `IconCompositionResolver` —
/// the same path the menu bar and Dock draw — with only the outer-ring source
/// swapped between the two options. Everything else (the sample status, the
/// current appearance: stroke width, colours, centre and scale, and the
/// rendering environment) is identical for both tiles, so they differ only in
/// the ring.
private struct OuterRingContentPreview: View {
    let content: OuterRingContent
    @ObservedObject var store: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            MenuBarPreviewBackdrop(isDarkBackground: dark, cornerRadius: 6)
            if let image = RingContentPreviewScene.image(
                for: content,
                store: store,
                isDarkBackground: dark
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Builds the still preview for one ring-content option from the runtime
/// composition resolver — the same path the menu bar and Dock render — using a
/// fixed sample status so the tile never depends on a live AirPods connection
/// and switching options triggers no device query or sampling.
@MainActor
enum RingContentPreviewScene {
    static let sampleDate = Date(timeIntervalSince1970: 1_789_555_974)

    /// The configuration a ring-content tile renders. Starts from the live
    /// appearance so the preview matches the real menu-bar/Dock rendering, then
    /// swaps only the outer-ring source plus the AirPods ring behaviour the tile
    /// is meant to preview. Exposed for tests.
    static func configuration(
        for content: OuterRingContent,
        store: SettingsStore
    ) -> IconConfigurationV1 {
        var configuration = store.derivedIconConfigurationFromSettings()
        switch content {
        case .systemBattery:
            configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        case .airPodsBattery:
            configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery)
        case .hardwareMonitor:
            configuration.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        }
        // The derived configuration only carries the AirPods ring behaviour when
        // the stored selection is already AirPods; the tile must preview the real
        // design regardless of which option is currently selected.
        configuration.behaviors.airPodsRing = store.airPodsRingUsesDualRing ? .dual : .single
        configuration.behaviors.showsAirPodsTopSymbol = store.showsAirPodsTopSymbolInRing
        return configuration
    }

    static func image(
        for content: OuterRingContent,
        store: SettingsStore,
        isDarkBackground: Bool
    ) -> NSImage? {
        let configuration = configuration(for: content, store: store)
        let inputs = IconPreviewInputBuilder.simulated(
            samples: IconPreviewSampleValues(),
            configuration: configuration,
            target: .currentAudioOutput,
            now: sampleDate,
            hardwareMetricColors: store.hardwareMonitorMetricColors
        )
        let scene = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: configuration,
            now: sampleDate
        ).scene
        return StatusIconPreviewCache.shared.image(
            scene: scene,
            size: 28,
            scale: 2,
            appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: isDarkBackground)
        )
    }
}
