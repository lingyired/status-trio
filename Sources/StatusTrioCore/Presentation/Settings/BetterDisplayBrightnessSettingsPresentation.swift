import Foundation

/// Presents the optional BetterDisplay display picker for one external
/// brightness row (#313).
///
/// The automatic mapper correlates EDID identity, but some displays (serial
/// `0`, duplicate same-model units) cannot be resolved that way. This state
/// backs a manual picker so the user can pin the exact BetterDisplay device;
/// the chosen UUID is stored in `ExternalBrightnessConfiguration` and wins in
/// `BrightnessMonitor.resolvedBetterDisplayUUID`.
struct BetterDisplayBrightnessSettingsState: Equatable, Sendable {
    let configuration: ExternalBrightnessConfiguration
    let devices: [BetterDisplayDevice]
    let hasLoadedCatalog: Bool

    /// The picker is only meaningful for the BetterDisplay backend.
    var showsDisplayPicker: Bool {
        configuration.backend == .betterDisplay
    }

    /// The manually pinned BetterDisplay UUID, or `nil` for automatic matching.
    var selectedDisplayUUID: String? {
        let uuid = configuration.betterDisplayUUID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid, !uuid.isEmpty else { return nil }
        return uuid
    }

    /// Automatic first, then each named device, then a saved/unavailable option
    /// when the stored UUID is not in the current catalog.
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
                .device(uuid: uuid, name: normalized(device.name))
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

    /// A human label for one device, disambiguating duplicate names by UUID.
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
