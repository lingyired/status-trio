import SwiftUI

struct IconSlotPicker: View {
    @Binding var selection: IconSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(IconSlot.allCases, id: \.self) { slot in
                    Button {
                        selection = slot
                    } label: {
                        Label(slot.title, systemImage: slot.symbol)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selection == slot ? Color.accentColor.opacity(0.16) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(slot.title)
                    .accessibilityAddTraits(selection == slot ? .isSelected : [])
                }
            }
            Picker("Icon slot", selection: $selection) {
                ForEach(IconSlot.allCases, id: \.self) { slot in
                    Text(slot.title).tag(slot)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }
}

private extension IconSlot {
    var title: String {
        switch self { case .outerRing: "Outer ring"; case .center: "Center"; case .footer: "Footer" }
    }
    var symbol: String {
        switch self { case .outerRing: "circle.dashed"; case .center: "circle.inset.filled"; case .footer: "circle.bottomhalf.filled" }
    }
}
