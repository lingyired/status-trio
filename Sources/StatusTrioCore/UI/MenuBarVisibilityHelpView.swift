import AppKit
import SwiftUI

/// Version-specific help for finding a menu bar icon among crowded menu bar
/// items. The content is bounded so it can live in a popover without moving
/// the onboarding footer.
struct MenuBarVisibilityHelpView: View {
    static let contentWidth: CGFloat = 480
    static let contentHeight: CGFloat = 372

    /// Diameter of a numbered step marker.
    static let stepMarkerSize: CGFloat = 22
    /// Horizontal gap between a step marker and its text.
    static let stepMarkerTextSpacing: CGFloat = 10

    let policy: MenuBarHelpPolicy
    let onClose: () -> Void
    let openSettings: ([URL]) -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    reason
                    steps
                    reopenHint
                    Link(
                        localization.string(.guideMenuBarHelpLearnMore),
                        destination: URL(string: "https://support.apple.com/guide/mac-help/mchl4af84660/mac")!
                    )
                    .font(.caption)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer(minLength: 8)

                Button(localization.string(.guideMenuBarHelpClose), action: onClose)
                    .keyboardShortcut(.cancelAction)

                Button {
                    openSettings(policy.systemSettingsURLs)
                } label: {
                    Text(localization.string(policy.systemSettingsButtonKey))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: Self.contentWidth, height: Self.contentHeight)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string(.guideMenuBarHelpTitle))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localization.string(.guideMenuBarHelpClose))
        }
    }

    private var reason: some View {
        Text(localization.string(.guideMenuBarHelpReason))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(policy.stepKeys.enumerated()), id: \.offset) { index, key in
                // Center the marker against the whole step, including wrapped
                // second lines, rather than pinning it to the first line.
                HStack(alignment: .center, spacing: Self.stepMarkerTextSpacing) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .frame(
                            width: Self.stepMarkerSize,
                            height: Self.stepMarkerSize
                        )
                        .background(
                            Circle().fill(Color.accentColor.opacity(0.16))
                        )
                        .accessibilityHidden(true)

                    Text(localization.string(key))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var reopenHint: some View {
        Label(
            localization.string(.guideMenuBarHelpReopen),
            systemImage: "arrow.clockwise"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
