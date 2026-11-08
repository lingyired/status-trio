#if DEBUG
import AppKit
import Combine

/// In-memory render fixtures for local screen-pixel measurements. No settings,
/// battery, radio, display or user data is changed, and no timer is installed.
/// Active only in a Debug dev bundle launched with both environment variables
/// and an `--alignment-fixture=` argument.
struct StatusBarAlignmentRequest: Equatable {
    enum Scenario: String {
        case wifi, weakWifi, bluetooth, charging, plug, inputSource, animatedWifi
    }
    enum Isolation: String { case composite, ring, center, accessory, blank }

    let scenario: Scenario
    let isolation: Isolation
    let size: Double
    let animated: Bool
    let phaseStep: Int

    init?(argument: String, phaseStep: Int) {
        let parts = argument.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let scenario = Scenario(rawValue: parts[0]),
              let isolation = Isolation(rawValue: parts[1]),
              let size = Double(parts[2]),
              size.isFinite, (16...36).contains(size)
        else { return nil }
        self.scenario = scenario
        self.isolation = isolation
        self.size = size
        self.animated = scenario == .animatedWifi
        self.phaseStep = max(0, min(39, phaseStep))
    }

    var scene: IconSceneState {
        let wifi = IconSymbolState(
            source: .symbol(name: "wifi", variableValue: scenario == .weakWifi ? 0.33 : 1, fallback: nil),
            color: .primary,
            scale: 1.6
        )
        let center: CenterState
        switch scenario {
        case .bluetooth:
            center = .symbol(IconSymbolState(
                source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
                color: .bluetoothIcon,
                scale: 1.6
            ))
        case .inputSource:
            center = .text(IconTextState(text: "ABC", color: .primary, scale: 1.6))
        default:
            center = .symbol(wifi)
        }
        let accessory: RingAccessoryState?
        switch scenario {
        case .charging:
            accessory = .symbol(IconSymbolState(
                source: .primitive(.bolt), color: .primary, scale: 1.8))
        case .plug:
            accessory = .symbol(IconSymbolState(
                source: .primitive(.plug), color: .primary, scale: 1.8))
        default:
            accessory = nil
        }
        let gap: RingGapStyle = accessory == nil ? .closed : .indicator
        let animated = scenario == .animatedWifi
        let ring = OuterRingState(
            segments: [RingSegmentState(progress: 1, color: .powered)],
            gap: gap,
            accessory: accessory,
            effect: animated ? RingEffectState(pulsesAccessory: true, tintsAccessory: true) : nil
        )
        switch isolation {
        case .blank:
            return IconSceneState()
        case .center:
            return IconSceneState(center: center)
        case .ring:
            return IconSceneState(outerRing: OuterRingState(
                segments: ring.segments, gap: gap, accessory: nil, effect: ring.effect))
        case .accessory:
            // Zero progress: no bright fill, and the faint full-circle track is
            // below the analyser's diff threshold, so only the accessory ink is
            // measured.
            return IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0, color: .powered)],
                gap: gap, accessory: accessory, effect: nil))
        case .composite:
            return IconSceneState(
                outerRing: ring,
                center: center,
                footer: .dots(DotsState(count: 4, activeCount: 2, color: .primary))
            )
        }
    }
}

@MainActor
final class StatusBarAlignmentDiagnostics {
    static let environmentKey = "STATUS_TRIO_ALIGNMENT_DIAGNOSTICS"
    static let fixtureArgumentPrefix = "--alignment-fixture="
    static let phaseArgumentPrefix = "--alignment-phase-step="

    let outputURL: URL
    private(set) var request: StatusBarAlignmentRequest?
    private var lastWrittenData: Data?
    private var observation: AnyCancellable?
    var didChange: (() -> Void)?

    private var notificationName: Notification.Name? {
        Bundle.main.bundleIdentifier.map {
            Notification.Name("\($0).alignment.\(ProcessInfo.processInfo.processIdentifier)")
        }
    }

    init?(environment: [String: String] = ProcessInfo.processInfo.environment,
          arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard Bundle.main.bundleIdentifier?.contains(".dev.") == true,
              let path = environment[Self.environmentKey], path.hasPrefix("/") else { return nil }
        outputURL = URL(fileURLWithPath: path)
        let fixture = arguments.first { $0.hasPrefix(Self.fixtureArgumentPrefix) }
            .map { String($0.dropFirst(Self.fixtureArgumentPrefix.count)) }
        let step = arguments.first { $0.hasPrefix(Self.phaseArgumentPrefix) }
            .flatMap { Int($0.dropFirst(Self.phaseArgumentPrefix.count)) } ?? 8
        request = fixture.flatMap { StatusBarAlignmentRequest(argument: $0, phaseStep: step) }
        if let name = notificationName {
            observation = DistributedNotificationCenter.default().publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    guard let text = notification.userInfo?["fixture"] as? String,
                          let request = StatusBarAlignmentRequest(argument: text, phaseStep: step)
                    else { return }
                    self?.request = request
                    self?.lastWrittenData = nil
                    self?.didChange?()
                }
        }
    }

    func write(button: NSStatusBarButton, scale: CGFloat, size: CGFloat, overlayFrame: CGRect?,
               statusItemLength: CGFloat, overlayContentsScale: CGFloat?) {
        guard let request, let window = button.window else { return }
        let bounds = button.bounds
        let imageRect = (button.cell as? NSButtonCell)?.imageRect(forBounds: bounds) ?? .zero
        let rect = window.convertToScreen(button.convert(bounds, to: nil))
        // AppKit global coordinates use a bottom-left origin; screenshot/AX
        // coordinates use the primary screen's top-left origin.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        func array(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        var result: [String: Any] = [
            "scenario": request.scenario.rawValue,
            "isolation": request.isolation.rawValue,
            "animated": request.animated,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "iconSize": size,
            "displayScale": scale,
            "buttonBounds": array(bounds),
            "imageRect": array(imageRect),
            "buttonRectAXPoints": [rect.minX, primaryTop - rect.maxY, rect.width, rect.height],
            "imageRectCenterOffset": imageRect.midX - bounds.midX,
            "windowBackingScale": window.backingScaleFactor,
            "templateFrames": button.subviews.compactMap { ($0 as? NSImageView).map { array($0.frame) } },
            "buttonFrame": array(button.frame),
            "imageSize": [button.image?.size.width ?? -1, button.image?.size.height ?? -1],
            "statusItemLength": statusItemLength,
            "overlayContentsScale": overlayContentsScale ?? -1,
            "buttonCenterX": bounds.midX,
            "imageRectCenterX": imageRect.midX,
            "imageRectCenterOffsetFromButton": imageRect.midX - bounds.midX,
        ]
        if let templateCenter = button.subviews.compactMap({ $0 as? NSImageView }).first.map({ $0.frame.midX }) {
            result["templateCenterOffsetFromButton"] = templateCenter - bounds.midX
            if let overlayFrame { result["layerCenterDelta"] = templateCenter - overlayFrame.midX }
        }
        if let overlayFrame { result["overlayFrame"] = array(overlayFrame) }
        // Sub-pixel screen rect of the button, for an exact container centre.
        let inWindow = button.convert(bounds, to: nil)
        let wf = window.frame
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let absMinX = wf.minX + inWindow.minX
        let absMaxY = wf.minY + inWindow.maxY
        result["buttonRectScreenPoints"] = [absMinX, primaryHeight - absMaxY, inWindow.width, inWindow.height]
        result["windowFrame"] = array(wf)
        result["primaryHeight"] = primaryHeight
        if let screen = window.screen {
            result["screenID"] = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value as Any
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           data != lastWrittenData {
            try? data.write(to: outputURL, options: .atomic)
            lastWrittenData = data
        }
    }
}
#endif
