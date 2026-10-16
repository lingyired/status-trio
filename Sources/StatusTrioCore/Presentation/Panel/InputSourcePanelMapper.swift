import Foundation

/// Pure mapping from the controller's truth to the panel's presentation.
@MainActor
enum InputSourcePanelMapper {
    static func map(
        state: InputSourceState,
        failure: InputSourceController.SelectionFailure?,
        localization: Localization
    ) -> InputSourcePanelState {
        let rows = state.sources.map { source in
            InputSourcePanelState.Row(
                id: source.id,
                name: source.localizedName,
                iconURL: source.iconURL,
                marker: source.shortLabel,
                isCurrent: source.id == state.selectedID
            )
        }

        return InputSourcePanelState(
            title: localization.string(.inputSourceTitle),
            currentName: state.selectedDescriptor?.localizedName,
            rows: rows,
            emptyMessage: state.isEmpty ? localization.string(.inputSourceEmpty) : nil,
            failureText: failure.map { failureText(for: $0, state: state, localization: localization) },
            openSettingsLabel: localization.string(.inputSourceOpenSettings)
        )
    }

    private static func failureText(
        for failure: InputSourceController.SelectionFailure,
        state: InputSourceState,
        localization: Localization
    ) -> String {
        let name = state.sources.first { $0.id == failure.sourceID }?.localizedName
            ?? failure.sourceID
        switch failure.reason {
        case .unknownSource, .systemRefused:
            return String(
                format: localization.string(.inputSourceSwitchFailed),
                locale: localization.resolvedLanguage.locale,
                arguments: [name]
            )
        case .notConfirmed:
            return String(
                format: localization.string(.inputSourceSwitchUnconfirmed),
                locale: localization.resolvedLanguage.locale,
                arguments: [name]
            )
        }
    }
}
