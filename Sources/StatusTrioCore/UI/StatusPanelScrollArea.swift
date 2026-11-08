import SwiftUI

/// Whether an enclosing status panel already provides the only scroll surface
/// a page may use (issue #237).
///
/// The detail pages and the Bluetooth lists used to scroll themselves, each
/// with its own fixed viewport bound. Inside the panel that produced several
/// nested scrollers: the panel could never learn the page's natural height, so
/// it could not tell when the page overflowed, and a wheel gesture hit whichever
/// inner scroller happened to be under the pointer. The panel sets this value
/// for its page content; the components keep their own scroll behaviour when
/// they are used on their own (previews, tests and the Settings surfaces).
private struct StatusPanelManagesScrollingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var statusPanelManagesScrolling: Bool {
        get { self[StatusPanelManagesScrollingKey.self] }
        set { self[StatusPanelManagesScrollingKey.self] = newValue }
    }
}

/// The panel's one scroll surface, with the footer pinned below it (#237).
///
/// The area measures the page at its natural height and gives its stable
/// `ScrollView` exactly the smaller of that height and the screen budget. A
/// short page hugs its content with scrolling disabled; a tall one is capped
/// and scrolls. Keeping the same view tree preserves local expansion state
/// when the content or budget changes. While the page overflows, a slim 4pt
/// capsule rides along its trailing edge; it stays visible so the panel always
/// shows that more content is reachable. The footer stays outside the viewport
/// so Actions, Settings and Quit remain reachable.
struct StatusPanelScrollArea<Content: View, Footer: View>: View {
    /// The tallest the whole panel (page plus pinned footer) may become. `nil`
    /// while the panel has no placement yet, which leaves the page unconstrained.
    let maximumHeight: CGFloat?
    var fillsWindow: Bool
    var onNaturalHeight: ((CGFloat) -> Void)?
    let content: Content
    let footer: Footer

    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    /// How far the page has scrolled, in points. Feeds the slim indicator.
    @State private var scrollOffset: CGFloat = 0

    init(
        maximumHeight: CGFloat?,
        fillsWindow: Bool = false,
        onNaturalHeight: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.maximumHeight = maximumHeight
        self.fillsWindow = fillsWindow
        self.onNaturalHeight = onNaturalHeight
        self.content = content()
        self.footer = footer()
    }

    private var overflowsBudget: Bool {
        guard let maximumHeight else { return false }
        return contentHeight + footerHeight > maximumHeight + 0.5
    }

    private var viewportHeight: CGFloat {
        min(contentHeight, maximumHeight.map { max(0, $0 - footerHeight) } ?? contentHeight)
    }

    private var indicatorMetrics: PanelScrollIndicatorMetrics? {
        guard overflowsBudget else { return nil }
        return PanelScrollIndicatorMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            offset: scrollOffset
        )
    }

    var body: some View {
        // Keep the same content identity when expanding a list crosses the
        // budget. Switching between plain and scrolling branches would reset
        // the lists' local expansion state.
        // The native hosting bounds are the presentation clock. Reading a
        // published height into a fixed VStack can lag a frame and centre an
        // old-sized stack inside the new window, moving the footer by half the
        // last resize step. GeometryReader fills the actual current proposal.
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    measuredContent
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: !fillsWindow ? viewportHeight : max(0, geometry.size.height - footerHeight))
                .scrollDisabled(!overflowsBudget)
                // The system overlay scroller is ~15pt wide on current macOS and
                // cannot be made thinner; the panel draws its own 4pt bar instead
                // (#237 follow-up). Scrolling itself stays fully native.
                .scrollIndicators(.hidden)
                .overlay(alignment: .topTrailing) {
                    if let metrics = indicatorMetrics {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.28))
                            .frame(
                                width: PanelScrollIndicatorMetrics.width,
                                height: metrics.thumbHeight
                            )
                            .offset(y: metrics.thumbOffset)
                            .padding(.trailing, PanelScrollIndicatorMetrics.trailingInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                measuredFooter
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(height: !fillsWindow ? viewportHeight + footerHeight : nil)
        .onPreferenceChange(StatusPanelContentHeightKey.self) { height in
            contentHeight = height
            reportHeight(content: height, footer: footerHeight)
        }
        .onPreferenceChange(StatusPanelFooterHeightKey.self) { height in
            footerHeight = height
            reportHeight(content: contentHeight, footer: height)
        }
        .onChange(of: maximumHeight) { _ in
            reportHeight(content: contentHeight, footer: footerHeight)
        }
    }

    private func reportHeight(content: CGFloat, footer: CGFloat) {
        guard content > 0 else { return }
        // Report in the measurement callback itself. Waiting for another body
        // update after storing this preference delays the window by a frame.
        onNaturalHeight?(min(content + footer, maximumHeight ?? .infinity))
    }

    private var measuredContent: some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StatusPanelContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
        // SwiftUI does not re-run geometry inside a hosting `NSScrollView` while
        // it scrolls, so the thumb position comes from AppKit's clip-view bounds
        // instead of a `frame(in:)` preference.
        .background(PanelScrollBridge(offset: $scrollOffset))
    }

    private var measuredFooter: some View {
        footer.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StatusPanelFooterHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
    }
}

private struct StatusPanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StatusPanelFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Thumb geometry for the panel's slim scroll indicator (#237 follow-up).
///
/// The system overlay scroller cannot be narrowed through public API, so the
/// panel hides it and draws a 4pt capsule instead. The indicator is decorative:
/// the wheel, trackpad and keyboard keep scrolling the native `ScrollView`.
struct PanelScrollIndicatorMetrics: Equatable {
    static let width: CGFloat = 4
    static let minimumThumbHeight: CGFloat = 28
    static let trailingInset: CGFloat = 3

    let thumbHeight: CGFloat
    /// Distance from the top of the viewport to the top of the thumb.
    let thumbOffset: CGFloat

    /// `nil` when the page fits and no indicator should be drawn.
    init?(
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        offset: CGFloat
    ) {
        guard viewportHeight > 0, contentHeight > viewportHeight + 0.5 else {
            return nil
        }
        let proportion = viewportHeight / contentHeight
        let height = min(
            viewportHeight,
            max(Self.minimumThumbHeight, viewportHeight * proportion)
        )
        let overflow = contentHeight - viewportHeight
        let progress = min(max(offset / overflow, 0), 1)
        self.thumbHeight = height
        self.thumbOffset = max(0, viewportHeight - height) * progress
    }
}

/// Converts AppKit's clip-view position into the panel's top-down scroll offset.
enum PanelScrollOffset {
    static func topOffset(
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        clipOriginY: CGFloat,
        documentIsFlipped: Bool
    ) -> CGFloat {
        let maximum = max(0, documentHeight - viewportHeight)
        guard maximum > 0 else { return 0 }
        let raw = documentIsFlipped ? clipOriginY : maximum - clipOriginY
        return min(max(raw, 0), maximum)
    }
}

/// Connects the panel's slim indicator to the hosting `NSScrollView`
/// (#237 follow-up).
///
/// Lives inside the document view, so it can find the enclosing scroll view and
/// observe its clip-view bounds while the user scrolls. It also switches the
/// system scroller off: `.scrollIndicators(.hidden)` still installs a ~17pt
/// legacy scroller when macOS is set to always show scroll bars, which would
/// appear beside the slim indicator and narrow the page. Scrolling itself stays
/// native, so the wheel, trackpad and keyboard are unchanged.
struct PanelScrollBridge: NSViewRepresentable {
    @Binding var offset: CGFloat

    /// The panel draws its own 4pt indicator. Force overlay chrome even when
    /// macOS prefers legacy scrollers, because a legacy scroller removes a
    /// 17pt gutter from the document and shifts the page's horizontal layout
    /// whenever content starts or stops overflowing.
    @MainActor
    static func configureScrollerChrome(_ scrollView: NSScrollView) {
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
        }
        if scrollView.hasHorizontalScroller {
            scrollView.hasHorizontalScroller = false
        }
        scrollView.autohidesScrollers = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset)
    }

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.updateBinding($offset)
        nsView.attach()
    }

    static func dismantleNSView(_ nsView: BridgeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class BridgeView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func layout() {
            super.layout()
            attach()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func attach() {
            guard let scrollView = enclosingScrollView else { return }
            PanelScrollBridge.configureScrollerChrome(scrollView)
            coordinator?.bind(to: scrollView)
        }
    }

    @MainActor
    final class Coordinator {
        private var offset: Binding<CGFloat>
        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private let scheduler: StatusPanelLayoutUpdateScheduler

        init(
            offset: Binding<CGFloat>,
            scheduler: StatusPanelLayoutUpdateScheduler? = nil
        ) {
            self.offset = offset
            self.scheduler = scheduler
                ?? StatusPanelLayoutUpdateScheduler { operation in
                    Task { @MainActor in operation() }
                }
        }

        /// Adopts a new binding without re-solving the scroll view. SwiftUI
        /// recreates the `@Binding` on every update, so the coordinator has to
        /// follow it rather than keep the one it was created with.
        func updateBinding(_ binding: Binding<CGFloat>) {
            offset = binding
            schedulePublish()
        }

        func bind(to scrollView: NSScrollView) {
            if self.scrollView === scrollView, !observers.isEmpty {
                schedulePublish()
                return
            }
            detach()
            self.scrollView = scrollView
            scrollView.postsFrameChangedNotifications = true
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.contentView.postsFrameChangedNotifications = true
            scrollView.documentView?.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.noteBoundsChanged()
                }
            })
            observeLayoutChanges(of: scrollView)
            schedulePublish()
        }

        /// The coalescing entry for a clip-view bounds change. `internal` so the
        /// behaviour is testable without a window; the observer calls it.
        func noteBoundsChanged() {
            schedulePublish()
        }

        func detach() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            scheduler.invalidate()
            observers.removeAll()
            scrollView = nil
        }

        /// SwiftUI can recreate scroller chrome after the bridge first attaches.
        /// Reassert overlay style whenever the scroll view, clip view or document
        /// changes shape, before the next scroll-offset publication.
        private func observeLayoutChanges(of scrollView: NSScrollView) {
            let frameObjects: [NSView] = [scrollView, scrollView.contentView]
                + (scrollView.documentView.map { [$0] } ?? [])
            for object in frameObjects {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: object,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reconfigureChrome()
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reconfigureChrome()
                }
            })
        }

        private func reconfigureChrome() {
            guard let scrollView else { return }
            PanelScrollBridge.configureScrollerChrome(scrollView)
        }

        /// Leaving the layout pass before writing the binding keeps SwiftUI from
        /// mutating state while it is still updating the view tree (issue #259).
        private func schedulePublish() {
            scheduler.enqueue { [weak self] in
                self?.publishNow()
            }
        }

        private func publishNow() {
            guard let scrollView, let documentView = scrollView.documentView else {
                return
            }
            let value = PanelScrollOffset.topOffset(
                documentHeight: documentView.frame.height,
                viewportHeight: scrollView.contentView.bounds.height,
                clipOriginY: scrollView.contentView.bounds.origin.y,
                documentIsFlipped: documentView.isFlipped
            )
            guard abs(offset.wrappedValue - value) > 0.5 else { return }
            offset.wrappedValue = value
        }
    }
}
