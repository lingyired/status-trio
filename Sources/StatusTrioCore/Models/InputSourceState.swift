import Foundation

/// Everything the icon and the status panel need to know about the system's
/// input sources, captured at one moment.
struct InputSourceState: Equatable, Sendable {
    /// The Input Source ID macOS reports as selected, or `nil` when nothing can
    /// be read.
    var selectedID: String?
    /// Enabled, select-capable keyboard sources in the order macOS lists them.
    var sources: [InputSourceDescriptor]

    static let empty = InputSourceState(selectedID: nil, sources: [])

    var selectedDescriptor: InputSourceDescriptor? {
        guard let selectedID else { return nil }
        return sources.first { $0.id == selectedID }
    }

    var isEmpty: Bool { sources.isEmpty }

    /// Resolves a raw reader answer into descriptors. Pure and therefore
    /// unit-testable without Carbon.
    static func resolved(
        selectedID: String?,
        rawSources: [RawInputSource]
    ) -> InputSourceState {
        let sources = rawSources
            .filter { $0.isEnabled && $0.isSelectCapable }
            .map { raw in
                InputSourceDescriptor(
                    id: raw.id,
                    localizedName: raw.localizedName,
                    primaryLanguage: raw.languages.first,
                    iconURL: raw.iconImageURL,
                    shortLabel: InputSourceShortLabel.make(
                        id: raw.id,
                        localizedName: raw.localizedName,
                        languages: raw.languages
                    )
                )
            }
        return InputSourceState(selectedID: selectedID, sources: sources)
    }
}
