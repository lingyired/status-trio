import SwiftUI

/// A separate visibility scope for each hosting tree. Preferences cannot cross
/// from a cascading NSPanel into its parent, so both report through callbacks.
struct BluetoothListVisibilityRegion<Content: View>: View {
    let rows: [BluetoothDisplayRow]
    let appleRowIDs: [String: AppleDeviceID]
    let onChange: (BluetoothDeviceList.VisibilityDemand) -> Void
    @ViewBuilder let content: Content

    @State private var frames: [String: CGRect] = [:]
    @State private var viewport = CGRect.zero

    private var demand: BluetoothDeviceList.VisibilityDemand {
        .visible(rows: rows, frames: frames, viewport: viewport, appleRowIDs: appleRowIDs)
    }

    var body: some View {
        content
            .coordinateSpace(name: BluetoothListVisibilityCoordinateSpace.rows)
            .background(BluetoothListViewportBridge(viewport: $viewport))
            .onPreferenceChange(BluetoothListVisibilityRegionRowFramesKey.self) { frames = $0 }
            .onChange(of: demand) { onChange($0) }
            .onAppear { onChange(demand) }
            .onDisappear { onChange(.init()) }
    }
}

enum BluetoothListVisibilityCoordinateSpace: Hashable {
    case rows
}

struct BluetoothListVisibilityRegionRowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Reads the actual AppKit clipped rectangle rather than the SwiftUI content
/// size. The panel owns scrolling, so a long child stack's own size is not its
/// viewport. Bounds observation updates demand while scrolling without polling.
struct BluetoothListViewportBridge: NSViewRepresentable {
    @Binding var viewport: CGRect

    func makeCoordinator() -> Coordinator { Coordinator(viewport: $viewport) }

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        context.coordinator.viewport = $viewport
        nsView.attach()
    }

    static func dismantleNSView(_ nsView: BridgeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class BridgeView: NSView {
        weak var coordinator: Coordinator?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attach()
        }

        override func layout() {
            super.layout()
            attach()
        }

        func attach() { coordinator?.bind(to: self) }
    }

    @MainActor
    final class Coordinator {
        var viewport: Binding<CGRect>
        private weak var view: BridgeView?
        private weak var clipView: NSClipView?
        private var observer: NSObjectProtocol?
        private let scheduler: StatusPanelLayoutUpdateScheduler

        init(viewport: Binding<CGRect>, scheduler: StatusPanelLayoutUpdateScheduler? = nil) {
            self.viewport = viewport
            self.scheduler = scheduler ?? StatusPanelLayoutUpdateScheduler { operation in
                Task { @MainActor in operation() }
            }
        }

        func bind(to view: BridgeView) {
            self.view = view
            let clip = view.enclosingScrollView?.contentView
            if clipView !== clip {
                removeObserver()
                clipView = clip
                if let clip {
                    clip.postsBoundsChangedNotifications = true
                    observer = NotificationCenter.default.addObserver(
                        forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor in self?.noteBoundsChanged() }
                    }
                }
            }
            schedulePublish()
        }

        func noteBoundsChanged() { schedulePublish() }

        func detach() {
            removeObserver()
            scheduler.invalidate()
            view = nil
            clipView = nil
        }

        private func removeObserver() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        private func schedulePublish() {
            scheduler.enqueue { [weak self] in
                guard let self, let view = self.view else { return }
                let rect = view.visibleRect
                guard self.viewport.wrappedValue != rect else { return }
                self.viewport.wrappedValue = rect
            }
        }
    }
}
