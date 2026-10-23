import SwiftUI

/// Makes the complete header a keyboard-accessible disclosure button.
struct IconDesignerDisclosureStyle: DisclosureGroupStyle {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(localization.string(
                SettingsDisclosurePresentation.accessibilityValueKey(isExpanded: configuration.isExpanded)
            ))
            .accessibilityHint(localization.string(
                SettingsDisclosurePresentation.accessibilityHintKey(isExpanded: configuration.isExpanded)
            ))

            if configuration.isExpanded {
                configuration.content
                    .padding([.horizontal, .bottom], 12)
            }
        }
    }
}
