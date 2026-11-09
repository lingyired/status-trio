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
    @ObservedObject var model: AirPodsSystemControlsModel
    @EnvironmentObject private var localization: Localization

    private var showSpatial: Bool {
        model.snapshot.supportsSpatial != false
            && (!model.snapshot.spatialLoaded || !model.snapshot.spatial.isEmpty)
    }

    private var showConversation: Bool {
        model.snapshot.supportsConversation != false
            && (!model.snapshot.conversationLoaded || !model.snapshot.conversation.isEmpty)
    }

    private var isLoading: Bool {
        let spatialPending = showSpatial && !model.snapshot.spatialLoaded
        let conversationPending = showConversation && !model.snapshot.conversationLoaded
        return spatialPending || conversationPending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading && model.snapshot.spatial.isEmpty && model.snapshot.conversation.isEmpty {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel(localization.string(.batteryDetailsLoading))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        group(.spatial, visible: showSpatial, options: model.snapshot.spatial, fixed: true)
                        if showSpatial && showConversation { Spacer(minLength: 8) }
                        group(.conversation, visible: showConversation, options: model.snapshot.conversation, fixed: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        group(.spatial, visible: showSpatial, options: model.snapshot.spatial, fixed: true)
                        group(.conversation, visible: showConversation, options: model.snapshot.conversation, fixed: true)
                    }
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
        fixed: Bool
    ) -> some View {
        if visible {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string(group == .spatial ? .airPodsSpatial : .airPodsConversation))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if options.isEmpty {
                    Text(localization.string(.airPodsNotAvailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
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
            .fixedSize(horizontal: fixed, vertical: false)
        }
    }
}
