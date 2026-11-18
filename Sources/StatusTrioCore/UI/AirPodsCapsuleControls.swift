import SwiftUI

/// A capsule group in the same visual language as the legacy listening-mode
/// quick switch, reused for the Spatial Audio and Conversation Awareness rows.
///
/// It is a pure function of the options the model publishes; tapping a capsule
/// asks the model to select that option and never reads the device directly.
struct AirPodsOptionCapsuleGroup: View {
    let options: [AirPodsSystemOption]
    let disabled: Bool
    let onSelect: (AirPodsSystemOption) -> Void

    @EnvironmentObject private var localization: Localization

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                capsule(option)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func capsule(_ option: AirPodsSystemOption) -> some View {
        Button {
            onSelect(option)
        } label: {
            HStack(spacing: 3) {
                if let symbol = option.symbol {
                    Image(nsImage: AirPodsControlSymbols.image(symbol))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(height: AirPodsControlMetrics.capsuleHeight)
                .background(
                    Capsule().fill(
                        option.selected
                            ? Color.accentColor
                            : Color.secondary.opacity(0.10)
                    )
                )
                .foregroundStyle(option.selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityAddTraits(option.selected ? .isSelected : [])
    }
}

/// The disclosure content behind the chevron: Spatial Audio on the left of one
/// row and Conversation Awareness on the right. When localized labels are too
/// wide to share a row, `ViewThatFits` falls back to two stacked rows — Spatial
/// Audio first, then Conversation Awareness.
struct AirPodsSpatialConversationView: View {
    @Environment(\.statusPanelBoldTextEnabled) private var panelBoldText
    @ObservedObject var model: AirPodsSystemControlsModel
    @EnvironmentObject private var localization: Localization

    /// A supported model keeps its group visible even when no options can be
    /// read (no active media client, or a failed HAL read). The group then shows
    /// the disabled "unavailable" placeholder instead of disappearing, matching
    /// both the native Sound menu and the original direct-control design.
    static func showsSpatial(_ snapshot: AirPodsSystemSnapshot) -> Bool {
        snapshot.supportsSpatial != false
    }

    static func showsConversation(_ snapshot: AirPodsSystemSnapshot) -> Bool {
        snapshot.supportsConversation != false
    }

    private var showSpatial: Bool { Self.showsSpatial(model.snapshot) }

    private var showConversation: Bool { Self.showsConversation(model.snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    group(.spatial, visible: showSpatial, options: model.snapshot.spatial,
                          loaded: model.snapshot.spatialLoaded, fixed: true)
                    if showSpatial && showConversation { Spacer(minLength: 8) }
                    group(.conversation, visible: showConversation, options: model.snapshot.conversation,
                          loaded: model.snapshot.conversationLoaded, fixed: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    group(.spatial, visible: showSpatial, options: model.snapshot.spatial,
                          loaded: model.snapshot.spatialLoaded, fixed: true)
                    group(.conversation, visible: showConversation, options: model.snapshot.conversation,
                          loaded: model.snapshot.conversationLoaded, fixed: true)
                }
            }
            if let key = model.errorKey {
                Button { model.refresh() } label: {
                    Label(localization.string(.airPodsRetry), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.busy || model.spatialWriting)
                .font(.caption)
                VStack(alignment: .leading) {
                    Text(localization.string(key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func group(
        _ group: AirPodsSystemControls.Group,
        visible: Bool,
        options: [AirPodsSystemOption],
        loaded: Bool,
        fixed: Bool
    ) -> some View {
        if visible {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string(group == .spatial ? .airPodsSpatial : .airPodsConversation))
                    .font(.caption2.weight(panelBoldText ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                // Reserve the width of the full option set even while showing
                // the loading or "unavailable" stand-in. `ViewThatFits` must
                // choose one row or two from the widest real content, or the
                // layout jumps rows the moment playback makes options readable.
                ZStack(alignment: .leading) {
                    referenceCapsuleRow(for: group)
                        .hidden()
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                    if options.isEmpty {
                        if loaded {
                            unavailableCapsule(for: group)
                        } else {
                            ProgressView().controlSize(.mini)
                                .frame(height: AirPodsControlMetrics.capsuleHeight)
                                .accessibilityLabel(localization.string(.batteryDetailsLoading))
                        }
                    } else {
                        AirPodsOptionCapsuleGroup(
                            options: options,
                            disabled: group == .spatial ? model.spatialDisabled : (model.busy || model.spatialWriting)
                        ) { option in
                            if !option.selected { model.select(option.title, group: group) }
                        }
                        .fixedSize(horizontal: fixed, vertical: false)
                    }
                }
            }
            .fixedSize(horizontal: fixed, vertical: false)
        }
    }

    /// The canonical full option set a group can ever show. Its measured width
    /// is what the one-row/two-row decision must use, independent of the current
    /// read state. Titles and symbols mirror `spatialOptions()` /
    /// `conversationOptions()` so the reserved width matches the real capsules.
    private func canonicalOptions(for group: AirPodsSystemControls.Group) -> [AirPodsSystemOption] {
        switch group {
        case .spatial:
            return [
                AirPodsSystemOption(title: localization.string(.bluetoothListeningModeOff),
                                    selected: false, symbol: "person.spatialaudio.stereo.fill", dimWaves: true),
                AirPodsSystemOption(title: localization.string(.airPodsSpatialFixed),
                                    selected: false, symbol: "person.spatialaudio.stereo.fill"),
                AirPodsSystemOption(title: localization.string(.airPodsSpatialHeadTracked),
                                    selected: false, symbol: "spatialize-stereo-head-tracked")
            ]
        case .conversation:
            return [
                AirPodsSystemOption(title: localization.string(.bluetoothListeningModeOff),
                                    selected: false, symbol: "person.wave.2.fill", dimWaves: true),
                AirPodsSystemOption(title: localization.string(.batteryDetailsOn),
                                    selected: true, symbol: "person.wave.2.fill")
            ]
        }
    }

    /// Non-interactive twin of `AirPodsOptionCapsuleGroup`, used only to hold
    /// layout width. It must not be a Button: a hidden Button would still
    /// generate focus targets and make the stand-in look clickable to tests.
    private func referenceCapsuleRow(for group: AirPodsSystemControls.Group) -> some View {
        HStack(spacing: 6) {
            ForEach(canonicalOptions(for: group)) { option in
                HStack(spacing: 3) {
                    if let symbol = option.symbol {
                        Image(nsImage: AirPodsControlSymbols.image(symbol))
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                    }
                    Text(option.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(height: AirPodsControlMetrics.capsuleHeight)
                .background(Capsule().fill(Color.secondary.opacity(0.10)))
            }
        }
    }

    /// The "unavailable" stand-in an unsupported read leaves behind: a single
    /// disabled capsule in the same shape as a real option, never a Button, so
    /// it cannot be activated. This is what keeps a supported model's group
    /// visible (as "not available") when no media client is playing.
    private func unavailableCapsule(for group: AirPodsSystemControls.Group) -> some View {
        let symbol = group == .spatial ? "person.spatialaudio.stereo.fill" : "person.wave.2.fill"
        return HStack(spacing: 3) {
            Image(nsImage: AirPodsControlSymbols.image(symbol))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text(localization.string(.airPodsNotAvailable))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: AirPodsControlMetrics.capsuleHeight)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localization.string(.airPodsNotAvailable))
    }
}
