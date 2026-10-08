import CoreAudio
import Foundation

@MainActor
enum AudioPanelMapper {
    static func volume(
        _ status: VolumeStatus,
        controllerAvailable: Bool,
        deviceList: AudioOutputListPreferences = .default,
        listeningModes: BluetoothListeningModeController? = nil,
        listeningModeTaskID: String = "",
        previewDevices: [AudioOutputDevice] = [],
        previewLanguageCode: String = "",
        previewLocalization: Localization? = nil,
        localization: Localization
    ) -> VolumePanelState {
        let scalar = readableScalar(status.scalar)
        let percentageText = percentage(scalar, locale: localization.resolvedLanguage.locale)
        let currentDevice = status.outputDevices.first(where: \.isCurrent)
        let summaryIconDevice: AudioOutputDevice?
        if let currentDevice,
           let liveName = status.deviceName,
           let cachedName = currentDevice.name,
           liveName != cachedName {
            summaryIconDevice = nil
        } else {
            summaryIconDevice = currentDevice
        }
        let name = cleanedName(status.deviceName)
            ?? cleanedName(currentDevice?.name)
            ?? localization.string(.volumeNoDefaultDevice)
        let subtitle: String
        if status.isMuted {
            subtitle = localization.string(.volumeMuted)
        } else if let scalar {
            let value = Int((scalar * 100).rounded())
            subtitle = localization.format(.volumeTitle, value)
        } else {
            subtitle = localization.string(.volumeTitleUnavailable)
        }
        let summary = PanelSummaryState(
            title: name,
            subtitle: subtitle,
            measurements: nil,
            symbol: summaryIconDevice.map { iconSource(for: $0) }
                ?? .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil),
            tint: .secondary,
            accessibilityLabel: localization.format(.commonLabelValue, name, subtitle),
            accessibilityValue: subtitle,
            showsSettings: true,
            intent: .none
        )

        let orderedDevices = OutputDeviceListPresentation.orderedDevices(
            status.outputDevices,
            using: deviceList.order
        )
        let rows = outputRows(orderedDevices, listeningModes: listeningModes, localization: localization)
        let previewRows = outputRows(
            previewDevices,
            listeningModes: listeningModes,
            isPreview: true,
            localization: previewLocalization ?? localization
        )

        return VolumePanelState(
            summary: summary,
            scalar: scalar,
            percentageText: percentageText,
            muted: status.isMuted,
            canAdjust: controllerAvailable && status.canSetVolume && scalar != nil,
            canMute: controllerAvailable && status.canMute,
            muteSymbol: volumeSymbol(scalar: scalar, muted: status.isMuted),
            muteHelp: localization.string(status.isMuted ? .volumeUnmuted : .volumeMuted),
            sliderLabel: localization.string(.volumeAccessibilityLabel),
            showsDeviceList: status.outputDevices.count > 1 || !previewRows.isEmpty,
            rows: rows,
            previewRows: previewRows,
            visibleLimit: deviceList.visibleLimit,
            expandLabel: localization.string(.volumeOutputExpand),
            collapseLabel: localization.string(.volumeOutputCollapse),
            listeningModeTaskID: listeningModeTaskID,
            previewLanguageCode: previewLanguageCode
        )
    }

    static func input(
        _ status: AudioInputStatus,
        localization: Localization
    ) -> AudioInputPanelState {
        let presentation = AudioInputPresentation(
            status: status,
            locale: localization.resolvedLanguage.locale
        )
        let unknownName = localization.string(.audioInputUnknownDevice)
        let orderedDevices = AudioInputPresentation.ordered(
            status.devices,
            currentID: status.defaultDeviceID,
            locale: presentation.locale,
            unknownName: unknownName
        )
        let rows = inputRows(
            orderedDevices,
            currentID: status.defaultDeviceID,
            isBusy: status.isBusy,
            unknownName: unknownName,
            locale: presentation.locale,
            localization: localization
        )
        let name = inputDefaultName(status, unknownName: unknownName, localization: localization)
        let usageText = presentation.isDefaultInputInUse
            ? localization.string(.audioInputInUse)
            : nil
        let summary = PanelSummaryState(
            title: localization.string(.audioInputTitle),
            subtitle: name,
            measurements: usageText,
            symbol: .symbol(name: "mic.fill", variableValue: nil, fallback: nil),
            tint: usageText == nil ? .secondary : .caution,
            accessibilityLabel: localization.format(
                .commonLabelValue,
                localization.string(.audioInputTitle),
                name
            ),
            accessibilityValue: usageText ?? "",
            showsSettings: true,
            intent: .none
        )

        let muteSymbol: String
        switch status.muteState {
        case .muted:
            muteSymbol = "mic.slash.fill"
        case .partial, .unmuted, .none:
            muteSymbol = "mic.fill"
        }

        let errorText = status.error.map {
            localization.string(AudioInputPresentation.errorLocalizationKey(for: $0))
        }
        let muteHelp = presentation.muteEnabled
            ? localization.string(presentation.nextMuteValue ? .audioInputMute : .audioInputUnmute)
            : localization.string(.audioInputMuteUnavailable)

        return AudioInputPanelState(
            summary: summary,
            selectedDeviceIdentity: status.defaultDeviceID.map {
                PanelAudioInputIdentity(rawValue: $0)
            },
            scalar: presentation.hasReadableVolume ? status.scalar : nil,
            percentageText: presentation.visibleVolumeValue,
            muteSymbol: muteSymbol,
            muteTint: status.muteState == .muted ? .critical : .secondary,
            muteHelp: muteHelp,
            muteState: status.muteState,
            canAdjust: presentation.volumeEnabled,
            canMute: presentation.muteEnabled,
            isBusy: status.isBusy,
            errorText: errorText,
            showsDeviceList: presentation.showsDeviceList,
            rows: rows,
            sliderLabel: localization.string(.audioInputVolume),
            usageText: usageText
        )
    }

    private static func outputRows(
        _ devices: [AudioOutputDevice],
        listeningModes: BluetoothListeningModeController?,
        isPreview: Bool = false,
        localization: Localization
    ) -> [PanelAudioDeviceRow] {
        devices.enumerated().map { index, device in
            let name = cleanedName(device.name) ?? localization.string(.volumeOutputUnknownDevice)
            let needsPosition = AudioInputPresentation.needsDevicePosition(
                name: device.name,
                id: device.id,
                among: devices.map { (id: $0.id, name: $0.name) },
                unknownName: localization.string(.volumeOutputUnknownDevice),
                locale: localization.resolvedLanguage.locale
            )
            let position = needsPosition ? String(index + 1) : nil
            let current = device.isCurrent ? localization.string(.volumeOutputCurrent) : nil
            let label = AudioInputPresentation.deviceAccessibilityLabel(
                name: name,
                position: position,
                current: current
            ) { first, second in
                localization.format(.commonParenthetical, first, second)
            }
            return PanelAudioDeviceRow(
                key: PanelAudioDeviceID(id: device.id, uid: device.uid),
                name: name,
                symbol: iconSource(for: device),
                selected: device.isCurrent,
                enabled: true,
                accessibilityLabel: label,
                helpText: device.isCurrent
                    ? localization.format(.commonLabelValue, name, localization.string(.volumeOutputCurrent))
                    : localization.format(.volumeOutputSwitchTo, name),
                volumeText: device.volume.flatMap { value in
                    guard value.isFinite else { return nil }
                    return value.formatted(.percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale))
                },
                listeningModeAddress: listeningModes?.control(forEndpoint: device.id)?.address,
                listeningMode: listeningModes?.control(forEndpoint: device.id)?.presentation,
                isPreview: isPreview
            )
        }
    }

    private static func inputRows(
        _ devices: [AudioInputDevice],
        currentID: AudioDeviceID?,
        isBusy: Bool,
        unknownName: String,
        locale: Locale,
        localization: Localization
    ) -> [PanelAudioDeviceRow] {
        devices.enumerated().map { index, device in
            let name = AudioInputPresentation.displayName(for: device, unknownName: unknownName)
            let needsPosition = AudioInputPresentation.needsDevicePosition(
                for: device,
                among: devices,
                unknownName: unknownName,
                locale: locale
            )
            let position = needsPosition
                ? localization.format(.audioInputDevicePosition, index + 1)
                : nil
            let selected = device.id == currentID
            let current = selected ? localization.string(.audioInputCurrent) : nil
            let label = AudioInputPresentation.deviceAccessibilityLabel(
                name: name,
                position: position,
                current: current
            ) { first, second in
                localization.format(.commonParenthetical, first, second)
            }
            return PanelAudioDeviceRow(
                key: PanelAudioDeviceID(id: device.id, uid: device.uid),
                name: name,
                symbol: .symbol(name: selected ? "mic.fill" : "mic", variableValue: nil, fallback: nil),
                selected: selected,
                enabled: !isBusy,
                accessibilityLabel: label
            )
        }
    }

    private static func inputDefaultName(
        _ status: AudioInputStatus,
        unknownName: String,
        localization: Localization
    ) -> String {
        guard let defaultDeviceID = status.defaultDeviceID else {
            return localization.string(.audioInputNoDefault)
        }
        if let deviceName = cleanedName(status.deviceName) { return deviceName }
        if let device = status.devices.first(where: { $0.id == defaultDeviceID }) {
            return AudioInputPresentation.displayName(for: device, unknownName: unknownName)
        }
        return unknownName
    }

    private static func volumeSymbol(scalar: Double?, muted: Bool) -> String {
        if muted { return "speaker.slash.fill" }
        guard let scalar, scalar > 0 else { return "speaker.fill" }
        if scalar < 0.33 { return "speaker.wave.1.fill" }
        if scalar < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func iconSource(for device: AudioOutputDevice) -> IconSymbolSource {
        switch AudioOutputDeviceIcon.source(for: device) {
        case .image(let url):
            .image(url: url, fallbackSymbol: AudioOutputDeviceIcon.symbolName(for: device))
        case .symbol(let name):
            .symbol(name: name, variableValue: nil, fallback: nil)
        }
    }

    private static func percentage(_ scalar: Double?, locale: Locale) -> String {
        guard let scalar else { return "—" }
        return scalar.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private static func readableScalar(_ scalar: Double?) -> Double? {
        guard let scalar, scalar.isFinite, (0...1).contains(scalar) else { return nil }
        return scalar
    }

    private static func cleanedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Stable localized input-device presentation shared by the view adapter and panel mapper.
struct AudioInputPresentation {
    let status: AudioInputStatus
    let locale: Locale

    init(status: AudioInputStatus, locale: Locale = .current) {
        self.status = status
        self.locale = locale
    }

    static func ordered(
        _ devices: [AudioInputDevice],
        currentID: AudioDeviceID?,
        locale: Locale,
        unknownName: String
    ) -> [AudioInputDevice] {
        devices.sorted { lhs, rhs in
            let lhsIsCurrent = lhs.id == currentID
            let rhsIsCurrent = rhs.id == currentID
            if lhsIsCurrent != rhsIsCurrent { return lhsIsCurrent }

            let comparison = displayName(for: lhs, unknownName: unknownName)
                .compare(
                    displayName(for: rhs, unknownName: unknownName),
                    options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                    range: nil,
                    locale: locale
                )
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return comparison == .orderedAscending
        }
    }

    static func displayName(for device: AudioInputDevice, unknownName: String) -> String {
        guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return unknownName }
        return name
    }

    static func needsDevicePosition(
        for device: AudioInputDevice,
        among devices: [AudioInputDevice],
        unknownName: String,
        locale: Locale
    ) -> Bool {
        guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return true }
        return devices.contains { candidate in
            guard candidate.id != device.id else { return false }
            return displayName(for: candidate, unknownName: unknownName)
                .compare(
                    displayName(for: device, unknownName: unknownName),
                    options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                    range: nil,
                    locale: locale
                ) == .orderedSame
        }
    }

    static func needsDevicePosition(
        name: String?,
        id: AudioDeviceID,
        among devices: [(id: AudioDeviceID, name: String?)],
        unknownName: String,
        locale: Locale
    ) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return true }
        return devices.contains { candidate in
            guard candidate.id != id else { return false }
            let candidateName = candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCandidateName = candidateName.flatMap { $0.isEmpty ? nil : $0 } ?? unknownName
            return resolvedCandidateName.compare(
                name,
                options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                range: nil,
                locale: locale
            ) == .orderedSame
        }
    }

    static func deviceAccessibilityLabel(
        name: String,
        position: String?,
        current: String?,
        combine: (String, String) -> String
    ) -> String {
        var label = name
        if let position, !position.isEmpty { label = combine(label, position) }
        if let current, !current.isEmpty { label = combine(label, current) }
        return label
    }

    static func errorLocalizationKey(for error: AudioInputError) -> LocalizationKey {
        switch error {
        case .refreshFailed: .audioInputRefreshFailed
        case .switchFailed: .audioInputSwitchFailed
        case .volumeFailed: .audioInputVolumeFailed
        case .muteFailed: .audioInputMuteFailed
        case .timedOut: .audioInputTimedOut
        }
    }

    var showsDeviceList: Bool { !status.devices.isEmpty }

    var volumeEnabled: Bool {
        status.defaultDeviceID != nil
            && status.canSetVolume
            && hasReadableVolume
            && !status.isBusy
    }

    var hasReadableVolume: Bool {
        guard let scalar = status.scalar else { return false }
        return scalar.isFinite && (0...1).contains(scalar)
    }

    var muteEnabled: Bool {
        status.defaultDeviceID != nil
            && status.canSetMute
            && status.muteState != nil
            && !status.isBusy
    }

    var nextMuteValue: Bool { status.muteState != .muted }
    var isDefaultInputInUse: Bool { status.isDefaultInputInUse == true }

    var visibleVolumeValue: String {
        guard hasReadableVolume, let scalar = status.scalar else { return "—" }
        return scalar.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    var volumeAccessibilityValue: String { visibleVolumeValue }
}
