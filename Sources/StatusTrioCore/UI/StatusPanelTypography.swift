import SwiftUI

/// When false, the status panel drops every semibold/bold title and value so the
/// user can compare a "no bold" look. Defaults to true (current design).
private struct StatusPanelBoldTextEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct StatusPanelMediumTextEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var statusPanelBoldTextEnabled: Bool {
        get { self[StatusPanelBoldTextEnabledKey.self] }
        set { self[StatusPanelBoldTextEnabledKey.self] = newValue }
    }

    /// When false, medium-weight text also drops to regular (on top of the bold
    /// switch). Lets the user compare a fully flat panel.
    var statusPanelMediumTextEnabled: Bool {
        get { self[StatusPanelMediumTextEnabledKey.self] }
        set { self[StatusPanelMediumTextEnabledKey.self] = newValue }
    }
}
