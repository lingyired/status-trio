import SwiftUI

struct WiFiNetworkListView: View {
    @EnvironmentObject private var localization: Localization
    let state: WiFiPanelState
    let onBack: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenLocationSettings: () -> Void
    let onSetPower: (Bool) -> Void
    let onRefresh: () -> Void
    let onOpenSharingSettings: () -> Void
    let onCopyValue: (String) -> Void
    let showsDetails: Bool
    let showsMore: Bool
    let onSetShowsDetails: (Bool) -> Void
    let onSetShowsMore: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Toggle(
                localization.string(.wifiPower),
                isOn: Binding(get: { state.powerIsOn }, set: { onSetPower($0) })
            )
            .disabled(!state.canSetPower)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    personalHotspotSection
                    knownNetworksSection
                    otherNetworksSection
                    stateMessage(
                        hasVisibleNetworks: !state.personalHotspotRows.isEmpty
                            || !state.knownRows.isEmpty
                            || !state.otherRows.isEmpty
                    )
                }
            }
            .frame(maxHeight: 330)

            Divider()
            Text(localization.string(.wifiActionSwitchingHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(localization.string(.wifiActionOpenSettings), action: onOpenWiFiSettings)
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.wifiActionOpenSettings))
            // Internet Sharing can share from the Wi-Fi connection too, so this
            // is offered here and not only on the wired details page.
            Button(localization.string(.networkActionShareInternet), action: onOpenSharingSettings)
                .buttonStyle(.plain)
                .help(localization.string(.networkActionShareInternetHelp))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: localization.string(.wifiTitle),
                action: onBack
            )
            Button(action: onRefresh) {
                PanelActionGlyph(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(!state.canRefresh)
            .accessibilityLabel(localization.string(.wifiRefresh))
        }
    }

    @ViewBuilder
    private var personalHotspotSection: some View {
        if !state.personalHotspotRows.isEmpty {
            sectionTitle(localization.string(.wifiPersonalHotspot))
            ForEach(state.personalHotspotRows, id: \.key) { row in
                networkRow(row)
            }
            if state.personalHotspotRows.contains(where: \.selected), state.showsConnectionDetails {
                detailsToggle
            }
        }
    }

    @ViewBuilder
    private var knownNetworksSection: some View {
        if !state.knownRows.isEmpty || state.showsConnectionDetails {
            sectionTitle(localization.string(.wifiKnownNetworks))
            ForEach(state.knownRows, id: \.key) { row in
                networkRow(row)
            }
            if state.showsConnectionDetails {
                detailsToggle
            }
        }
    }

    @ViewBuilder
    private var otherNetworksSection: some View {
        if !state.otherRows.isEmpty {
            sectionTitle(localization.string(.wifiOtherNetworks))
            ForEach(state.otherRows, id: \.key) { row in
                networkRow(row)
            }
        }
    }

    @ViewBuilder
    private var detailsToggle: some View {
        WiFiDetailsToggleRow(isExpanded: showsDetailsBinding)

        if showsDetails {
            WiFiDetailsView(
                state: state,
                showsMore: showsMoreBinding,
                onCopyValue: onCopyValue
            )
        }
    }

    private var showsDetailsBinding: Binding<Bool> {
        Binding(
            get: { showsDetails },
            set: { value in onSetShowsDetails(value) }
        )
    }

    private var showsMoreBinding: Binding<Bool> {
        Binding(
            get: { showsMore },
            set: { value in onSetShowsMore(value) }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var stateMessage: some View {
        EmptyView()
    }

    @ViewBuilder
    private func stateMessage(hasVisibleNetworks _: Bool) -> some View {
        if let message = state.message {
            switch state.messageIntent {
            case .requestWiFiNameAccess:
                Button(message, action: onRequestNameAccess)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .locationSettings:
                Button(message, action: onOpenLocationSettings)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                HStack(spacing: 8) {
                    if state.isScanning { ProgressView().controlSize(.small) }
                    Text(message)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func networkRow(_ row: PanelWiFiNetworkRow) -> some View {
        Button {
            if row.opensSettings { onOpenWiFiSettings() }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if row.selected {
                    Image(systemName: "checkmark")
                        .frame(width: 16, height: 16, alignment: .center)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "wifi")
                        .frame(width: 16, height: 16, alignment: .center)
                        .foregroundStyle(.secondary)
                }
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let marker = row.securityMarker {
                    Image(systemName: marker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16, alignment: .center)
                        .accessibilityHidden(true)
                }
                if let systemImage = row.signalSystemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16, alignment: .center)
                        .accessibilityHidden(true)
                } else {
                    PanelSymbolView(source: row.signalSymbol, size: 14, weight: .regular)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16, alignment: .center)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.opensSettings)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct WiFiDetailsView: View {
    let state: WiFiPanelState
    @Binding var showsMore: Bool
    let onCopyValue: (String) -> Void

    var body: some View {
        VStack(spacing: 5) {
            PanelDetailRowsView(
                detailRows: state.visibleDetailRows(expanded: showsMore),
                onCopyValue: onCopyValue
            )
            Button(showsMore ? state.showLessTitle : state.showMoreTitle) {
                showsMore.toggle()
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 26)
        .font(.caption)
    }
}
