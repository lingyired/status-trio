import Foundation

struct BetterDisplayVolumeSettingsState: Equatable, Sendable {
    let outputUID: String?
    let configuration: ExternalVolumeConfiguration
    let devices: [BetterDisplayDevice]
    let availability: BetterDisplayAvailability
    var runtime: BetterDisplayCatalogUpdate? = nil
    var usesNativeVolumeControl = false

    var hasLoadedCatalog: Bool {
        runtime?.isCatalogLoaded
            ?? (availability == .available || availability == .deviceUnassociated)
    }

    var normalizedOutputUID: String? {
        let uid = outputUID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !uid.isEmpty else { return nil }
        return uid
    }

    var selectedDisplayUUID: String? {
        guard configuration.backend == .betterDisplay else { return nil }
        let uuid = configuration.betterDisplayUUID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid, !uuid.isEmpty else { return nil }
        return uuid
    }

    var pickerOptions: [BetterDisplayDisplayPickerOption] {
        var options: [BetterDisplayDisplayPickerOption] = [.unassociated]
        var availableUUIDs = Set<String>()

        for device in devices {
            let uuid = device.uuid
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uuid.isEmpty, availableUUIDs.insert(uuid).inserted else {
                continue
            }
            options.append(
                .device(
                    uuid: uuid,
                    name: normalized(device.name)
                )
            )
        }

        if let selectedDisplayUUID,
           !availableUUIDs.contains(selectedDisplayUUID) {
            options.append(
                hasLoadedCatalog
                    ? .unavailable(uuid: selectedDisplayUUID)
                    : .saved(uuid: selectedDisplayUUID)
            )
        }
        return options
    }

    var canEditConfiguration: Bool {
        normalizedOutputUID != nil
    }

    var canSelectDisplay: Bool {
        showsConnectionControls && hasLoadedCatalog && !devices.isEmpty
    }

    var showsConnectionControls: Bool {
        canEditConfiguration
            && configuration.backend == .betterDisplay
            && !usesNativeVolumeControl
    }

    var automaticDisplayUUID: String? {
        guard runtime?.outputUID == normalizedOutputUID,
              hasLoadedCatalog,
              let uuid = runtime?.automaticDisplayUUID,
              devices.contains(where: { $0.uuid == uuid })
        else { return nil }
        return uuid
    }

    var showsDisplayPicker: Bool {
        showsConnectionControls
            && hasLoadedCatalog
            && (automaticDisplayUUID == nil
                || (selectedDisplayUUID != nil && selectedDisplayUUID != automaticDisplayUUID))
    }

    var setupStatus: BetterDisplaySetupStatus {
        guard canEditConfiguration else { return .noOutput }
        guard configuration.backend == .betterDisplay else { return .standard }
        if usesNativeVolumeControl { return .native }
        if let scope = runtime?.outputUID, scope != normalizedOutputUID {
            return .discovering
        }
        switch availability {
        case .appAbsent, .unresponsive, .invalidResponse, .requestFailed, .writeNotConfirmed:
            return .failure(availability)
        case .idle, .discovering, .available, .syncing, .deviceUnassociated:
            break
        }
        guard hasLoadedCatalog else { return .discovering }
        guard let selectedDisplayUUID else {
            if automaticDisplayUUID != nil { return .checking }
            return devices.isEmpty ? .noDisplays : .chooseDisplay
        }
        guard devices.contains(where: { $0.uuid == selectedDisplayUUID }) else {
            return .missingDisplay
        }
        guard runtime?.outputUID == normalizedOutputUID,
              runtime?.displayUUID == selectedDisplayUUID
        else {
            return .checking
        }
        if availability == .syncing { return .updating }
        return availability == .available && runtime?.canSetVolume == true
            ? .ready : .checking
    }

    func deviceLabel(uuid: String, name: String?) -> String? {
        guard let name else { return nil }
        let duplicates = devices.filter {
            $0.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(name) == .orderedSame
        }.count
        return duplicates > 1 ? "\(name) · \(uuid.prefix(8))" : name
    }

    private func normalized(_ value: String?) -> String? {
        let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum BetterDisplayDisplayPickerOption:
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    case unassociated
    case device(uuid: String, name: String?)
    case unavailable(uuid: String)
    case saved(uuid: String)

    var id: String {
        switch self {
        case .unassociated:
            return "unassociated"
        case .device(let uuid, _):
            return "device:\(uuid)"
        case .unavailable(let uuid):
            return "unavailable:\(uuid)"
        case .saved(let uuid):
            return "saved:\(uuid)"
        }
    }

    var uuid: String? {
        switch self {
        case .unassociated:
            return nil
        case .device(let uuid, _), .unavailable(let uuid), .saved(let uuid):
            return uuid
        }
    }
}

enum BetterDisplaySetupStatus: Equatable {
    case noOutput
    case standard
    case native
    case discovering
    case chooseDisplay
    case noDisplays
    case checking
    case ready
    case updating
    case missingDisplay
    case failure(BetterDisplayAvailability)

    var localizationKey: LocalizationKey {
        switch self {
        case .noOutput: return .settingsAudioExternalVolumeNoStableOutput
        case .standard: return .settingsAudioExternalVolumeFootnote
        case .native: return .settingsAudioExternalVolumeStatusNative
        case .discovering: return .settingsAudioExternalVolumeStatusBusy
        case .chooseDisplay: return .settingsAudioExternalVolumeStatusChooseDisplay
        case .noDisplays: return .settingsAudioExternalVolumeStatusNoDisplays
        case .checking: return .settingsAudioExternalVolumeStatusChecking
        case .ready: return .settingsAudioExternalVolumeStatusReady
        case .updating: return .settingsAudioExternalVolumeStatusUpdating
        case .missingDisplay: return .settingsAudioExternalVolumeUnavailableDisplay
        case .failure(let availability): return availability.settingsStatusLocalizationKey
        }
    }

    var isBusy: Bool {
        self == .discovering || self == .checking
    }

}

struct BetterDisplayVolumeSettingsActions {
    private let state: BetterDisplayVolumeSettingsState
    private let setConfiguration: (ExternalVolumeConfiguration, String) -> Void
    private let refresh: () -> Void

    init(
        state: BetterDisplayVolumeSettingsState,
        setConfiguration: @escaping (
            ExternalVolumeConfiguration,
            String
        ) -> Void,
        refresh: @escaping () -> Void
    ) {
        self.state = state
        self.setConfiguration = setConfiguration
        self.refresh = refresh
    }

    func setBackend(_ backend: ExternalVolumeBackend) {
        guard let uid = state.normalizedOutputUID else { return }

        switch backend {
        case .directDDC:
            setConfiguration(.default, uid)
        case .betterDisplay:
            let displayUUID = state.configuration.backend == .betterDisplay
                ? state.selectedDisplayUUID
                : nil
            setConfiguration(
                ExternalVolumeConfiguration(
                    backend: .betterDisplay,
                    betterDisplayUUID: displayUUID
                ),
                uid
            )
        }
    }

    func selectDisplayUUID(_ uuid: String?) {
        guard let uid = state.normalizedOutputUID,
              state.configuration.backend == .betterDisplay
        else { return }

        let displayUUID = uuid?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        setConfiguration(
            ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: displayUUID?.isEmpty == false
                    ? displayUUID
                    : nil
            ),
            uid
        )
    }

    func refreshDevices() {
        refresh()
    }
}

extension BetterDisplayAvailability {
    var settingsStatusLocalizationKey: LocalizationKey {
        switch self {
        case .idle:
            return .settingsAudioExternalVolumeStatusIdle
        case .discovering:
            return .settingsAudioExternalVolumeStatusBusy
        case .available:
            return .settingsAudioExternalVolumeStatusReady
        case .syncing:
            return .settingsAudioExternalVolumeStatusUpdating
        case .appAbsent:
            return .settingsAudioExternalVolumeStatusAppAbsent
        case .unresponsive:
            return .settingsAudioExternalVolumeStatusUnresponsive
        case .invalidResponse:
            return .settingsAudioExternalVolumeStatusInvalidResponse
        case .requestFailed:
            return .settingsAudioExternalVolumeStatusRequestFailed
        case .deviceUnassociated:
            return .settingsAudioExternalVolumeStatusChooseDisplay
        case .writeNotConfirmed:
            return .settingsAudioExternalVolumeStatusNotConfirmed
        }
    }
}
