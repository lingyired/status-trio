import SwiftUI

/// A card-local scale editor with a readable value and a full-width fine-adjustment slider.
struct IconDesignerScaleControl: View {
    let title: String
    @Binding var value: Double
    let formattedValue: String
    let range: ClosedRange<Double>
    let step: Double
    var showsDivider = false
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(formattedValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityValue(formattedValue)
                    .accessibilityIdentifier("iconDesigner.scale.slider")
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)

            if showsDivider {
                SettingsDivider(inset: SettingsMetrics.rowPaddingH)
            }
        }
        .accessibilityIdentifier("iconDesigner.scaleControl")
    }
}
