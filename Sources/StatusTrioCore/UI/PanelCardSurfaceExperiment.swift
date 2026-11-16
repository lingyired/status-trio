import SwiftUI

/// Runtime A/B switch for the Liquid Glass material experiment. Off (default)
/// keeps the current tuned translucent surfaces; on (macOS 26+, visual only)
/// renders the same components with Apple's native glass so the two can be
/// compared in one build without changing any layout, size or content.
///
/// Flip with: defaults write com.lingsmbp.StatusTrio glassVisualExperiment -bool true
enum PanelCardSurfaceExperiment {
    static let defaultsKey = "glassVisualExperiment"

    static var isNativeGlassEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true } else { return false }
    }

    /// Default on for macOS 26+ (the chosen look); set the key to false to fall
    /// back to the tuned translucent wash without rebuilding.
    static var useNative: Bool {
        nativeGlassAvailable
            && (UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false)
    }
}

/// Applies interactive native glass to a tappable control when the experiment is
/// on; otherwise the control is untouched. Used only to A/B the battery row.
struct InteractiveGlassExperiment: ViewModifier {
    var cornerRadius: CGFloat = 12

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), PanelCardSurfaceExperiment.useNative {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}
