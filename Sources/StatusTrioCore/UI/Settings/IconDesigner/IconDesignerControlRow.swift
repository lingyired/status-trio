import SwiftUI

/// A labeled, full-width control row that keeps native controls trailing while
/// switching to a stacked label/control layout when the card cannot fit both.
struct IconDesignerControlRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var identifier: String?
    var showsDivider: Bool
    @ViewBuilder let control: Control

    init(
        _ title: String,
        subtitle: String? = nil,
        identifier: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.identifier = identifier
        self.showsDivider = showsDivider
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                SettingsRow(title: title, subtitle: subtitle) {
                    control
                }
                .frame(minHeight: 44)

                VStack(alignment: .leading, spacing: 8) {
                    rowLabel
                    HStack {
                        Spacer(minLength: 0)
                        control
                    }
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.vertical, SettingsMetrics.rowPaddingV)
            }

            if showsDivider {
                SettingsDivider(inset: SettingsMetrics.rowPaddingH)
            }
        }
        .accessibilityIdentifier(identifier ?? "iconDesigner.controlRow")
    }

    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
