import SwiftUI

struct IconDesignerFallbackSection<Content: View>: View {
    @Binding var isExpanded: Bool
    let summary: String
    var setupNotice: String? = nil
    @ViewBuilder let content: Content
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) { content }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.string(.iconDesignerUnavailableTitle))
                        .font(.body)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disclosureGroupStyle(IconDesignerDisclosureStyle())
            .accessibilityIdentifier("iconDesigner.source.fallbackDisclosure")
            if let setupNotice, !isExpanded {
                HStack {
                    Text(setupNotice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(localization.string(.settingsTitle)) { isExpanded = true }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("iconDesigner.source.configureFallback")
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
    }
}
