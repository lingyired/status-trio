import AppKit
import SwiftUI

/// Control Center uses private symbol names for these three listening modes.
/// Resolve the installed system artwork at runtime; older systems get public fallbacks.
@MainActor
enum AirPodsControlSymbols {
    static func image(_ name: String) -> NSImage {
        if name == "spatialize-stereo-head-tracked",
           let bundle = Bundle(path: "/System/Library/CoreServices/ControlCenter.app"),
           let image = bundle.image(forResource: name)?.copy() as? NSImage {
            image.isTemplate = true
            return image
        }
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) { return image }
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:")
        if NSImage.responds(to: selector),
           let image = NSImage.perform(selector, with: name)?.takeUnretainedValue() as? NSImage { return image }
        let fallback: String
        switch name {
        case "spatialize-stereo-head-tracked", "person.spatialaudio.stereo.fill": fallback = "person.fill"
        case "person.open.fill": fallback = "person.and.background.dotted"
        case "person.closed.fill": fallback = "person.crop.circle"
        case "person.and.sparkles.fill": fallback = "person.fill.badge.plus"
        default: fallback = "person.fill"
        }
        return NSImage(systemSymbolName: fallback, accessibilityDescription: nil) ?? NSImage()
    }
}

@MainActor
final class AirPodsSystemControlsModel: ObservableObject {
    @Published private(set) var snapshot = AirPodsSystemSnapshot()
    @Published private(set) var busy = false
    @Published private(set) var errorKey: LocalizationKey?
    private let controls: AirPodsSystemControls
    private var task: Task<Void, Never>?
    enum Change { case refresh, option(AirPodsSystemControls.Group), adaptive }

    init(deviceID: PanelAudioDeviceID, deviceName: String, snapshot: AirPodsSystemSnapshot = .init()) {
        self.snapshot = snapshot
        controls = AirPodsSystemControls(target: deviceID, name: deviceName)
    }

    typealias Reader = (@escaping @MainActor (AirPodsSystemSnapshot) -> Void) async throws -> AirPodsSystemSnapshot

    func refresh(read: Reader? = nil) {
        run(.refresh) {
            let publish: @MainActor (AirPodsSystemSnapshot) -> Void = { [weak self] snapshot in
                guard !Task.isCancelled else { return }
                self?.snapshot = snapshot
            }
            let result: AirPodsSystemSnapshot
            if let read { result = try await read(publish) }
            else { result = try await self.controls.read(onUpdate: publish) }
            try Task.checkCancellation()
            self.snapshot = result
        }
    }

    func select(_ title: String, group: AirPodsSystemControls.Group) {
        run(.option(group)) {
            let options = try await self.controls.select(title, group: group)
            switch group {
            case .conversation: self.snapshot.conversation = options
            case .spatial: self.snapshot.spatial = options
            }
        }
    }

    func setAdaptive(_ value: Int) {
        run(.adaptive) { self.snapshot.adaptive = try await self.controls.setAdaptive(value) }
    }

    func stop() {
        task?.cancel()
        task = nil
        controls.stop()
        busy = false
    }

    func run(_ change: Change, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        errorKey = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                snapshot = AirPodsSystemSnapshot(loaded: true)
                errorKey = .airPodsUnavailable
            } catch {
                guard !Task.isCancelled else { return }
                // Never leave a failed write displaying an earlier confirmed value
                // as if it were current; Refresh obtains a fresh system snapshot.
                switch change {
                case .refresh: snapshot = AirPodsSystemSnapshot(loaded: true)
                case .adaptive: snapshot.adaptive = nil
                case .option(.conversation): snapshot.conversation = []
                case .option(.spatial): snapshot.spatial = []
                }
                if let error = error as? AirPodsSystemControlError, error == .routeChanged {
                    snapshot = AirPodsSystemSnapshot()
                }
                switch error as? AirPodsSystemControlError {
                case .routeChanged: errorKey = .airPodsRouteChanged
                case .unconfirmed: errorKey = .airPodsUnconfirmed
                default: errorKey = .airPodsUnavailable
                }
            }
            guard !Task.isCancelled else { return }
            busy = false
            task = nil
        }
    }
}

/// The output row owns this model while its disclosure is open.
/// Operations are bounded; collapsing the disclosure explicitly cancels them.
struct AirPodsSystemControlsView: View {
    @ObservedObject var model: AirPodsSystemControlsModel
    var listeningMode: BluetoothListeningModePresentation? = nil
    var onSelectListeningMode: (BluetoothListeningMode) -> Void = { _ in }
    @EnvironmentObject private var localization: Localization
    @State private var adaptiveDraft: Double = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            heading(.bluetoothListeningModeGroup)
            if let listeningMode {
                ForEach(listeningMode.availableModes, id: \.self) { mode in
                    option(localization.string(mode.titleKey), symbol: symbol(mode), selected: listeningMode.selectedMode == mode) {
                        onSelectListeningMode(mode)
                    }.disabled(listeningMode.isChanging)
                    if mode == .adaptive, listeningMode.selectedMode == mode { adaptiveControl }
                }
                if listeningMode.isChanging { ProgressView().controlSize(.mini) }
                if listeningMode.isFailed {
                    Text(localization.string(.bluetoothListeningModeChangeFailed)).font(.caption)
                }
            }
            Divider()
            heading(.airPodsSpatial)
            options(model.snapshot.spatial, group: .spatial, symbol: "person.spatialaudio.stereo.fill")
            Divider()
            heading(.airPodsConversation)
            options(model.snapshot.conversation, group: .conversation, symbol: "person.wave.2.fill")
            Divider()
            HStack(spacing: 8) {
                Button { model.refresh() } label: {
                    Label(localization.string(.bluetoothRefresh), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                Spacer(minLength: 0)
                if model.busy { ProgressView().controlSize(.mini) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let key = model.errorKey {
                Text(localization.string(key))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(.vertical, 8)
        .onDisappear { model.stop() }
    }

    private func heading(_ key: LocalizationKey) -> some View {
        Text(localization.string(key)).font(.callout.weight(.semibold))
    }

    @ViewBuilder private var adaptiveControl: some View {
        if let value = model.snapshot.adaptive {
            VStack(alignment: .trailing, spacing: 4) {
                AirPodsAdaptiveSlider(value: $adaptiveDraft, label: localization.string(.airPodsAdaptive))
                    .frame(height: 28)
                    .onAppear { adaptiveDraft = Double(value) }
                    .onChange(of: value) { adaptiveDraft = Double($0) }
                    .help(localization.string(.airPodsLessNoise) + " – " + localization.string(.airPodsMoreNoise))
                if Int(adaptiveDraft) != value {
                    Button(localization.string(.airPodsApply)) { model.setAdaptive(Int(adaptiveDraft)) }
                        .disabled(model.busy)
                        .controlSize(.small)
                }
            }
            .padding(.leading, 30)
        } else if !model.snapshot.loaded {
            loadingIndicator.padding(.leading, 30)
        } else {
            Text(localization.string(.airPodsAdaptiveUnavailable))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 30)
        }
    }

    private func options(_ values: [AirPodsSystemOption], group: AirPodsSystemControls.Group,
                         symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if values.isEmpty && !(model.snapshot.loaded || (group == .spatial ? model.snapshot.spatialLoaded : model.snapshot.conversationLoaded)) {
                loadingIndicator.padding(.leading, 30)
            } else if values.isEmpty {
                option(localization.string(.airPodsNotAvailable), symbol: symbol, selected: false) {}
                    .disabled(true)
            } else {
                ForEach(values) { value in
                    option(value.title, symbol: value.symbol ?? symbol, selected: value.selected) {
                        if !value.selected { model.select(value.title, group: group) }
                    }.disabled(model.busy)
                }
            }
        }
    }

    private var loadingIndicator: some View {
        ProgressView().controlSize(.small)
            .accessibilityLabel(localization.string(.batteryDetailsLoading))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func option(_ title: String, symbol: String, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.body.weight(.semibold))
                    .opacity(selected ? 1 : 0).frame(width: 16)
                    .accessibilityHidden(true)
                Image(nsImage: AirPodsControlSymbols.image(symbol)).resizable().scaledToFit()
                    .foregroundStyle(symbol == "person.fill" || symbol == "person.wave.2.fill" || symbol == "person.spatialaudio.stereo.fill" || symbol == "spatialize-stereo-head-tracked" ? Color.secondary : Color.primary)
                    .frame(width: 20, height: 20).accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func symbol(_ mode: BluetoothListeningMode) -> String {
        switch mode {
        case .transparency: return "person.open.fill"
        case .adaptive: return "person.and.sparkles.fill"
        case .noiseCancellation: return "person.closed.fill"
        case .off: return "speaker.slash"
        }
    }
}

/// NSSlider preserves keyboard and VoiceOver adjustment while its cell draws
/// the compact monochrome track and wide thumb used by Control Center.
private struct AirPodsAdaptiveSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = AirPodsAdaptiveSliderCell()
        slider.minValue = 0
        slider.maxValue = 100
        slider.numberOfTickMarks = 11
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription("\(Int(value))%")
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    @MainActor final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ sender: NSSlider) { value.wrappedValue = sender.doubleValue }
    }
}

private final class AirPodsAdaptiveSliderCell: NSSliderCell {
    override func drawTickMarks() {}

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let view = controlView else { return }
        let track = NSRect(x: 0, y: (view.bounds.height - 26) / 2, width: view.bounds.width, height: 26)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: 13, yRadius: 13).fill()
        for (symbol, x) in [("circle.dotted", track.minX + 10), ("circle", track.maxX - 22)] {
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.labelColor]))?
                .draw(in: NSRect(x: x, y: track.midY - 6, width: 12, height: 12))
        }
    }

    override func knobRect(flipped: Bool) -> NSRect {
        guard let view = controlView else { return super.knobRect(flipped: flipped) }
        let width: CGFloat = 40
        return NSRect(x: (view.bounds.width - width) * CGFloat(doubleValue / 100),
                      y: (view.bounds.height - 26) / 2, width: width, height: 26)
    }

    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: knobRect.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12).fill()
        AirPodsControlSymbols.image("person.and.sparkles.fill")
            .withSymbolConfiguration(.init(paletteColors: [.black]))?
            .draw(in: NSRect(x: knobRect.midX - 8, y: knobRect.midY - 8, width: 16, height: 16))
    }
}
