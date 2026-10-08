import SwiftUI

/// The wired network row: the port's name heads it and the BSD name follows,
/// while the address belongs in the details panel. A restricted path adds one
/// clause to the subtitle.
struct EthernetStatusView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var primaryLink: PrimaryLinkController
    /// A property of the path rather than of the port, so it is passed in from
    /// the store instead of read off the link controller.
    let isConstrained: Bool
    let onOpenDetails: () -> Void
    let onOpenNetworkSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onOpenDetails()
            } label: {
                HStack(spacing: 10) {
                    EthernetStatusIcon()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(subtitle)

            Button(
                localization.string(.ethernetActionOpenSettings),
                systemImage: "gearshape",
                action: onOpenNetworkSettings
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(localization.string(.ethernetActionOpenSettings))
            .frame(width: 24, height: 24)
        }
    }

    private var title: String {
        WiredLinkPresentation.title(primaryLink.details, localization: localization)
    }

    /// Never the address: the row says which port is up, and the panel says with
    /// which address. Until the read names the interface — a cable that is up
    /// before DHCP answers has no service yet, so nothing names it — the row
    /// falls back to the state rather than to an address it does not have.
    private var subtitle: String {
        WiredLinkPresentation.subtitle(
            primaryLink.details,
            isConstrained: isConstrained,
            localization: localization
        )
    }
}

/// The cable glyph used by the wired summary row.
struct EthernetStatusIcon: View {
    var body: some View {
        Image(systemName: "cable.connector")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}
