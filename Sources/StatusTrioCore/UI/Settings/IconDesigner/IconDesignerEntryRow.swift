import SwiftUI

struct IconDesignerEntryRow: View {
    let title: String
    let onOpen: () -> Void

    var body: some View {
        SettingsGroup {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "slider.horizontal.3", tint: .indigo)

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.vertical, SettingsMetrics.rowPaddingV)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(title)
        }
    }
}
