import SwiftUI

struct IconDesignerCurrentDisplay: View {
    let trace: SlotResolutionTrace
    var value: String? = nil
    let reason: String
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text([localization.format(.iconDesignerCurrentDisplayFormat,
                    localization.string(IconDesignerInspectorModel.displayedSourceName(for: trace))), value]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.callout.weight(.semibold))
            if !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("iconDesigner.currentDisplay")
    }
}
