import AppKit
import SwiftUI

/// Control Center uses private symbol names for these three listening modes.
/// Resolve the installed system artwork at runtime; older systems get public fallbacks.
@MainActor
enum AirPodsControlSymbols {
    static func offImage(_ name: String, dark: Bool) -> NSImage {
        let color = dark ? NSColor.white : NSColor.black
        let source = image(name)
        // Stereo artwork puts waves in the primary layer; conversation artwork
        // puts the person there. Explicit palettes keep the person solid in both.
        let dimmed = color.withAlphaComponent(0.35)
        let colors = name == "person.spatialaudio.stereo.fill" ? [dimmed, color] : [color, dimmed]
        let result = source.withSymbolConfiguration(.init(paletteColors: colors)) ?? source
        let copy = (result.copy() as? NSImage) ?? result
        copy.isTemplate = false
        return copy
    }

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
    private let deviceID: PanelAudioDeviceID
    private let listenerBackend: any BluetoothListeningModePropertyListening
    private let spatialReader: (@MainActor () throws -> [AirPodsSystemOption])?
    private var observation: AirPodsSpatialObservation?
    private var observationGeneration = 0
    private var spatialRevision = 0
    private var spatialTask: Task<Void, Never>?
    private var spatialWriteTask: Task<Void, Never>?
    @Published private(set) var spatialWriting = false

    var spatialDisabled: Bool {
        if spatialWriting { return true }
        if case .refresh? = activeChange { return false }
        return busy
    }
    private var spatialDirty = false
    private var activeChange: Change?
    enum Change { case refresh, option(AirPodsSystemControls.Group), adaptive }

    init(deviceID: PanelAudioDeviceID, deviceName: String, snapshot: AirPodsSystemSnapshot = .init(),
         listenerBackend: any BluetoothListeningModePropertyListening = CoreAudioBluetoothListeningModeListenerBackend(),
         spatialReader: (@MainActor () throws -> [AirPodsSystemOption])? = nil) {
        self.deviceID = deviceID
        self.listenerBackend = listenerBackend
        self.spatialReader = spatialReader
        self.snapshot = snapshot
        controls = AirPodsSystemControls(target: deviceID, name: deviceName)
    }

    func start(read: Reader? = nil) {
        guard observation == nil else { return }
        observationGeneration += 1
        let token = observationGeneration
        observation = AirPodsSpatialObservation(deviceID: deviceID.id, backend: listenerBackend) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == token else { return }
                self.spatialChanged()
            }
        }
        refresh(read: read)
        spatialChanged()
    }

    private func spatialChanged() {
        spatialDirty = true
        if spatialWriting { return }
        if case .option(.spatial)? = activeChange { return }
        guard spatialTask == nil else { return }
        let token = observationGeneration
        spatialTask = Task { [weak self] in
            await Task.yield() // coalesce notifications from the same HAL update
            guard let self, !Task.isCancelled, self.observationGeneration == token else { return }
            self.spatialTask = nil
            if self.spatialWriting { return }
            if case .option(.spatial)? = self.activeChange { return }
            self.spatialDirty = false
            self.spatialRevision += 1
            do {
                self.snapshot.spatial = try self.spatialReader?() ?? self.controls.readSpatial()
                self.snapshot.spatialLoaded = true
            } catch {
                self.snapshot.spatial = []
                self.snapshot.spatialLoaded = true
                if error as? AirPodsSystemControlError == .routeChanged {
                    self.snapshot = AirPodsSystemSnapshot()
                    self.errorKey = .airPodsRouteChanged
                    self.stop()
                }
            }
        }
    }

    typealias Reader = (@escaping @MainActor (AirPodsSystemSnapshot) -> Void) async throws -> AirPodsSystemSnapshot

    func refresh(read: Reader? = nil) {
        run(.refresh) {
            let revision = self.spatialRevision
            let publish: @MainActor (AirPodsSystemSnapshot) -> Void = { [weak self] snapshot in
                guard !Task.isCancelled else { return }
                guard let self else { return }
                var updated = snapshot
                if self.spatialRevision != revision {
                    updated.spatial = self.snapshot.spatial
                    updated.spatialLoaded = self.snapshot.spatialLoaded
                }
                self.snapshot = updated
            }
            let result: AirPodsSystemSnapshot
            if let read { result = try await read(publish) }
            else { result = try await self.controls.read(onUpdate: publish) }
            try Task.checkCancellation()
            publish(result)
        }
    }

    func select(_ title: String, group: AirPodsSystemControls.Group) {
        if group == .spatial {
            writeSpatial { try await self.controls.select(title, group: .spatial) }
            return
        }
        run(.option(group)) {
            let options = try await self.controls.select(title, group: group)
            switch group {
            case .conversation: self.snapshot.conversation = options
            case .spatial: self.snapshot.spatial = options
            }
        }
    }

    // Spatial HAL writes are independent of the supplementary Bluetooth read.
    func writeSpatial(_ operation: @escaping @MainActor () async throws -> [AirPodsSystemOption]) {
        guard !spatialDisabled else { return }
        spatialWriting = true
        spatialRevision += 1
        let token = observationGeneration
        spatialWriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let options = try await operation()
                try Task.checkCancellation()
                guard observationGeneration == token else { return }
                snapshot.spatial = options
            } catch {
                guard !Task.isCancelled, observationGeneration == token else { return }
                snapshot.spatial = []
                if error as? AirPodsSystemControlError == .routeChanged {
                    snapshot = AirPodsSystemSnapshot()
                    errorKey = .airPodsRouteChanged
                    stop()
                    return
                }
                errorKey = .airPodsUnconfirmed
            }
            guard !Task.isCancelled, observationGeneration == token else { return }
            snapshot.spatialLoaded = true
            spatialWriting = false
            spatialWriteTask = nil
            if spatialDirty, observation != nil { spatialChanged() }
        }
    }

    func setAdaptive(_ value: Int) {
        run(.adaptive) { self.snapshot.adaptive = try await self.controls.setAdaptive(value) }
    }

    func stop() {
        observationGeneration += 1
        observation = nil
        spatialWriteTask?.cancel()
        spatialWriteTask = nil
        spatialWriting = false
        spatialTask?.cancel()
        spatialTask = nil
        spatialDirty = false
        activeChange = nil
        task?.cancel()
        task = nil
        controls.stop()
        busy = false
    }

    func run(_ change: Change, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy, !spatialWriting else { return }
        busy = true
        activeChange = change
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
            activeChange = nil
            if spatialDirty, observation != nil { spatialChanged() }
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var adaptiveDraft: Double = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let listeningMode, listeningMode.isControllable {
                Divider()
                heading(.bluetoothListeningModeGroup)
                ForEach([BluetoothListeningMode.off, .transparency, .adaptive, .noiseCancellation]
                    .filter { listeningMode.availableModes.contains($0) }, id: \.self) { mode in
                    option(localization.string(mode.titleKey), symbol: symbol(mode), selected: listeningMode.selectedMode == mode, dimWaves: mode == .off) {
                        onSelectListeningMode(mode)
                    }.disabled(listeningMode.isChanging)
                    if mode == .adaptive, listeningMode.selectedMode == mode { adaptiveControl }
                }
                if listeningMode.isChanging { ProgressView().controlSize(.mini) }
                if listeningMode.isFailed {
                    Text(localization.string(.bluetoothListeningModeChangeFailed)).font(.caption)
                }
            }
            if model.snapshot.supportsSpatial != false {
                Divider()
                heading(.airPodsSpatial)
                options(model.snapshot.spatial, group: .spatial, symbol: "person.spatialaudio.stereo.fill")
            }
            if model.snapshot.supportsConversation != false {
                Divider()
                heading(.airPodsConversation)
                options(model.snapshot.conversation, group: .conversation, symbol: "person.wave.2.fill")
            }
            if model.busy || model.spatialWriting {
                ProgressView().controlSize(.mini)
            }
            if let key = model.errorKey {
                Divider()
                Button { model.refresh() } label: {
                    Label(localization.string(.airPodsRetry), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.busy || model.spatialWriting)
                .font(.caption)
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
                        .disabled(model.busy || model.spatialWriting)
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
                    option(value.title, symbol: value.symbol ?? symbol, selected: value.selected, dimWaves: value.dimWaves) {
                        if !value.selected { model.select(value.title, group: group) }
                    }.disabled(group == .spatial ? model.spatialDisabled : (model.busy || model.spatialWriting))
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

    private func option(_ title: String, symbol: String, selected: Bool, dimWaves: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.body.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    .opacity(selected ? 1 : 0).frame(width: 16)
                    .accessibilityHidden(true)
                Image(nsImage: dimWaves ? AirPodsControlSymbols.offImage(symbol, dark: colorScheme == .dark) : AirPodsControlSymbols.image(symbol))
                    .renderingMode(dimWaves ? .original : .template).resizable().scaledToFit()
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
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
        case .off: return "person.closed.fill"
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
