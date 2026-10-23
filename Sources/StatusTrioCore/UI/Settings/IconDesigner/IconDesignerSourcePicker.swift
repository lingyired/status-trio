import SwiftUI

struct IconDesignerSourcePicker: View {
    @Binding var selection: IconDesignerSource?
    let sources: [IconDesignerSource]
    let allowsEmpty: Bool
    let title: String
    let identifier: String
    @EnvironmentObject private var localization: Localization

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsEmpty {
                Text(localization.string(.iconDesignerNone)).tag(IconDesignerSource?.none)
            }
            ForEach(sources, id: \.self) { source in
                Text(localization.string(source.localizationKey)).tag(Optional(source))
            }
            if let selection, !sources.contains(selection) {
                Text(localization.string(selection.localizationKey)).tag(Optional(selection))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
