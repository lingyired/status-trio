import SwiftUI

/// When false, the status panel drops every semibold/bold title and value so the
/// user can compare a "no bold" look. Defaults to true (current design).
private struct StatusPanelBoldTextEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var statusPanelBoldTextEnabled: Bool {
        get { self[StatusPanelBoldTextEnabledKey.self] }
        set { self[StatusPanelBoldTextEnabledKey.self] = newValue }
    }
}
