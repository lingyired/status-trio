import AppKit
import SwiftUI

/// One child per root panel. Ownership tokens prevent a stale entry's teardown
/// from closing the replacement that the pointer has already opened.
@MainActor
final class CascadingSubmenuCoordinator: ObservableObject {
    private var owner: UUID?
    private var closeChild: (() -> Void)?
    var hasOpenChild: Bool { owner != nil }
    /// Binding setters may preserve a remembered detail route on whole-group close.
    private(set) var isClosingParent = false

    func closeForParent() {
        isClosingParent = true
        defer { isClosingParent = false }
        close()
    }

    func activate(owner: UUID, close: @escaping () -> Void) {
        guard self.owner != owner else { return }
        self.close()
        self.owner = owner
        closeChild = close
    }

    func close(owner: UUID) {
        guard self.owner == owner else { return }
        close()
    }

    func close() {
        let operation = closeChild
        owner = nil
        closeChild = nil
        operation?()
    }
}

private struct CascadingSubmenuCoordinatorKey: EnvironmentKey {
    static let defaultValue: CascadingSubmenuCoordinator? = nil
}

private struct IsCascadingSubmenuKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var cascadingSubmenuCoordinator: CascadingSubmenuCoordinator? {
        get { self[CascadingSubmenuCoordinatorKey.self] }
        set { self[CascadingSubmenuCoordinatorKey.self] = newValue }
    }

    var isCascadingSubmenu: Bool {
        get { self[IsCascadingSubmenuKey.self] }
        set { self[IsCascadingSubmenuKey.self] = newValue }
    }
}

extension View {
    /// Keep this modifier on the entry's complete hit area. A caller's Button
    /// opens immediately by setting the binding; resting on the entry also
    /// opens it after 220ms. Leaving the entry and child closes after a short grace period.
    func cascadingSubmenu<Content: View>(
        isPresented: Binding<Bool>,
        backgroundStyle: PanelBackgroundStyle = .systemDefault,
        @ViewBuilder content: () -> Content
    ) -> some View {
        modifier(CascadingSubmenuModifier(
            isPresented: isPresented,
            backgroundStyle: backgroundStyle,
            childContent: content()
        ))
    }
}

struct CascadingSubmenuButton<Content: View>: View {
    let title: String
    @Binding var isPresented: Bool
    private let content: Content

    init(title: String, isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        _isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cascadingSubmenu(isPresented: $isPresented) { content }
    }
}

private struct CascadingSubmenuModifier<ChildContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let backgroundStyle: PanelBackgroundStyle
    let childContent: ChildContent
    @Environment(\.cascadingSubmenuCoordinator) private var coordinator
    @Environment(\.isCascadingSubmenu) private var isChild
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var fallbackCoordinator = CascadingSubmenuCoordinator()

    func body(content: Content) -> some View {
        if isChild {
            content
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isPresented ? (colorScheme == .dark ? 0.10 : 0.07) : 0))
                }
                .background(CascadingSubmenuAnchor(
                    isPresented: $isPresented,
                    sharedCoordinator: coordinator ?? fallbackCoordinator,
                    backgroundStyle: backgroundStyle,
                    childContent: AnyView(childContent)
                ))
        }
    }
}

private struct CascadingSubmenuRoot: View {
    @ObservedObject var metrics: StatusPanelLayoutMetrics
    let content: AnyView
    let onHoverEntered: () -> Void
    let onHoverExited: () -> Void

    var body: some View {
        StatusPanelScrollArea(maximumHeight: metrics.maximumPanelHeight) {
            content.padding(14)
        } footer: {
            EmptyView()
        }
        .frame(width: 330)
        .background(CascadingSubmenuHoverRegion(onEntered: onHoverEntered, onExited: onHoverExited))
    }
}

private struct CascadingSubmenuHoverRegion: NSViewRepresentable {
    let onEntered: () -> Void
    let onExited: () -> Void

    func makeNSView(context: Context) -> CascadingSubmenuHoverView { CascadingSubmenuHoverView() }

    func updateNSView(_ view: CascadingSubmenuHoverView, context: Context) {
        view.onEntered = onEntered
        view.onExited = onExited
    }

    static func dismantleNSView(_ view: CascadingSubmenuHoverView, coordinator: ()) {
        view.onEntered = nil
        view.onExited = nil
    }
}

private struct CascadingSubmenuAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let sharedCoordinator: CascadingSubmenuCoordinator
    let backgroundStyle: PanelBackgroundStyle
    let childContent: AnyView
    @Environment(\.self) private var inheritedEnvironment
    @EnvironmentObject private var localization: Localization

    func makeCoordinator() -> CascadingSubmenuPresenter { CascadingSubmenuPresenter() }

    func makeNSView(context: Context) -> CascadingSubmenuAnchorView {
        let view = CascadingSubmenuAnchorView()
        view.presenter = context.coordinator
        return view
    }

    func updateNSView(_ view: CascadingSubmenuAnchorView, context: Context) {
        let presenter = context.coordinator
        presenter.update(
            view: view,
            binding: $isPresented,
            coordinator: sharedCoordinator,
            backgroundStyle: backgroundStyle
        ) { [weak presenter] metrics in
            AnyView(CascadingSubmenuRoot(
                metrics: metrics, content: childContent,
                onHoverEntered: { [weak presenter] in presenter?.childHoverEntered() },
                onHoverExited: { [weak presenter] in presenter?.childHoverExited() }
            )
                .environmentObject(localization)
                .environment(\.cascadingSubmenuCoordinator, sharedCoordinator)
                .environment(\.isCascadingSubmenu, true)
                .environment(\.statusPanelManagesScrolling, true)
                .environment(\.self, inheritedEnvironment))
        }
    }

    static func dismantleNSView(_ view: CascadingSubmenuAnchorView, coordinator: CascadingSubmenuPresenter) {
        coordinator.detach()
    }
}

/// The invisible background participates in tracking without swallowing the
/// actual SwiftUI Button's clicks.
private class CascadingSubmenuHoverView: NSView {
    var onEntered: (() -> Void)?
    var onExited: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEntered?() }
    override func mouseExited(with event: NSEvent) { onExited?() }
}

private final class CascadingSubmenuAnchorView: CascadingSubmenuHoverView {
    weak var presenter: CascadingSubmenuPresenter?

    override func mouseEntered(with event: NSEvent) { presenter?.hoverEntered() }
    override func mouseExited(with event: NSEvent) { presenter?.hoverExited() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        presenter?.refreshPresentation()
    }
}

@MainActor
private final class CascadingSubmenuPresenter {
    private let owner = UUID()
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private var binding: Binding<Bool>?
    private var coordinator: CascadingSubmenuCoordinator?
    private var child: AnchoredStatusPanel?
    private var host: StatusPanelHostingController<AnyView>?
    private var backgroundStyle: PanelBackgroundStyle = .systemDefault
    private var makeContent: ((StatusPanelLayoutMetrics) -> AnyView)?
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var mouseMonitor: Any?
    private var parentGeometryObservers: [NSObjectProtocol] = []

    func update(
        view: NSView,
        binding: Binding<Bool>,
        coordinator: CascadingSubmenuCoordinator,
        backgroundStyle: PanelBackgroundStyle,
        makeContent: @escaping (StatusPanelLayoutMetrics) -> AnyView
    ) {
        anchor = view
        self.binding = binding
        self.coordinator = coordinator
        self.backgroundStyle = backgroundStyle
        self.makeContent = makeContent
        refreshPresentation()
    }

    func refreshPresentation() {
        presentationTask?.cancel()
        presentationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            self?.presentIfNeeded()
        }
    }

    func hoverEntered() {
        cancelPendingHover()
        cancelPendingClose()
        guard binding?.wrappedValue == false else { return }
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard !Task.isCancelled, let self,
                  self.anchor?.window?.isVisible == true else { return }
            self.binding?.wrappedValue = true
            self.presentIfNeeded()
        }
    }

    func hoverExited() {
        cancelPendingHover()
        scheduleClose()
    }

    func childHoverEntered() { cancelPendingClose() }
    func childHoverExited() { scheduleClose() }

    private func cancelPendingHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func cancelPendingClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func scheduleClose() {
        cancelPendingClose()
        guard child != nil else { return }
        closeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.coordinator?.close(owner: self.owner)
        }
    }

    private func presentIfNeeded() {
        guard binding?.wrappedValue == true else {
            coordinator?.close(owner: owner)
            return
        }
        guard let anchor, let parent = anchor.window, parent.isVisible,
              let coordinator, let makeContent else { return }
        if let child {
            host?.rootView = makeContent(child.layoutMetrics)
            child.applyBackgroundStyle(effectiveBackgroundStyle(in: parent))
            return
        }
        cancelPendingHover()
        cancelPendingClose()
        // Separate standalone entries still share a single child through their
        // actual panel, even when no root environment was supplied by a fixture.
        let resolvedCoordinator = (parent as? AnchoredStatusPanel)?.submenuCoordinator ?? coordinator
        self.coordinator = resolvedCoordinator
        resolvedCoordinator.activate(owner: owner) { [weak self] in self?.closeChild() }
        self.parent = parent
        (parent as? AnchoredStatusPanel)?.submenuCoordinator = resolvedCoordinator
        let panel = AnchoredStatusPanel()
        let hostingController = StatusPanelHostingController(rootView: makeContent(panel.layoutMetrics))
        host = hostingController
        child = panel
        panel.installContent(hostingController, backgroundStyle: effectiveBackgroundStyle(in: parent))
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.coordinator?.close(owner: self.owner)
        }
        parent.addChildWindow(panel, ordered: .above)
        // Use the root panel's horizontal edges and the entry's vertical edges:
        // content padding must not make the child overlap its parent.
        let parentBounds = parent.contentView.map { $0.convert($0.bounds, to: anchor) } ?? anchor.bounds
        let placementRect = NSRect(x: parentBounds.minX, y: anchor.bounds.minY,
                                   width: parentBounds.width, height: anchor.bounds.height)
        panel.show(relativeTo: placementRect, of: anchor, preferredEdge: .maxX, alignsTop: true)
        panel.makeKey()
        panel.makeFirstResponder(nil)
        installMouseMonitor()
        for notification in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            parentGeometryObservers.append(NotificationCenter.default.addObserver(
                forName: notification, object: parent, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.coordinator?.close(owner: self.owner)
                }
            })
        }
    }

    private func effectiveBackgroundStyle(in parent: NSWindow) -> PanelBackgroundStyle {
        (parent.contentViewController as? StatusPanelContentViewController)?.backgroundStyle ?? backgroundStyle
    }

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDown(event) }
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard let child, let parent else { return }
        if event.type == .scrollWheel {
            if event.window === parent { coordinator?.close(owner: owner) }
            return
        }
        if event.window === child { return }
        if event.window === parent {
            if let anchor {
                let point = anchor.convert(event.locationInWindow, from: nil)
                if anchor.bounds.contains(point) { return }
            }
            coordinator?.close(owner: owner)
        } else {
            let point = event.window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
                ?? NSEvent.mouseLocation
            if let panel = parent as? AnchoredStatusPanel,
               !panel.shouldDismissForOutsideClick(at: point) { return }
            (parent as? AnchoredStatusPanel)?.close()
            coordinator?.close(owner: owner)
        }
    }

    private func closeChild() {
        cancelPendingHover()
        cancelPendingClose()
        presentationTask?.cancel()
        presentationTask = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        parentGeometryObservers.forEach { NotificationCenter.default.removeObserver($0) }
        parentGeometryObservers = []
        let panel = child
        let restoreKey = panel?.isKeyWindow == true
            && panel?.isClosingForFocusLoss != true
            && (parent as? AnchoredStatusPanel)?.isClosing != true
        child = nil
        host = nil
        panel?.onClose = nil
        if let panel { parent?.removeChildWindow(panel); panel.close() }
        if panel != nil, binding?.wrappedValue == true { binding?.wrappedValue = false }
        if restoreKey, parent?.isVisible == true { parent?.makeKey() }
        parent = nil
    }

    func detach() {
        cancelPendingHover()
        cancelPendingClose()
        presentationTask?.cancel()
        presentationTask = nil
        coordinator?.close(owner: owner)
        closeChild()
        makeContent = nil
        binding = nil
        anchor = nil
    }
}
