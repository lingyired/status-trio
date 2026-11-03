import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The live menu bar simulation at the top of the icon panes must stay in place
/// while the option groups below it scroll, and it must share their width — a
/// scrollbar that takes layout space only narrows the scrolling content.
@MainActor
final class SettingsPagePinningTests: VisibleUITestCase {
    func testPinnedHeaderIsPinnedInsideThePageScrollView() throws {
        let hostingView = makeHostingView(
            SettingsPage(pinnedHeader: {
                ProbeView(kind: .pinned)
            }) {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )

        let pinned = try XCTUnwrap(findProbe(.pinned, in: hostingView))
        let content = try XCTUnwrap(findProbe(.content, in: hostingView))
        let scrollView = try XCTUnwrap(enclosingScrollView(of: content))

        XCTAssertEqual(
            enclosingScrollView(of: pinned),
            scrollView,
            """
            The preview is a pinned section header inside the page's scroll view, \
            so a scrollbar narrows it exactly as much as the groups below it.
            """
        )
    }

    func testPinnedHeaderIsLaidOutAboveTheContent() throws {
        let hostingView = makeHostingView(
            SettingsPage(pinnedHeader: {
                ProbeView(kind: .pinned)
                    .frame(height: 40)
            }) {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )

        let pinned = try XCTUnwrap(findProbe(.pinned, in: hostingView))
        let content = try XCTUnwrap(findProbe(.content, in: hostingView))
        let pinnedFrame = pinned.convert(pinned.bounds, to: hostingView)
        let contentFrame = content.convert(content.bounds, to: hostingView)

        // NSHostingView is flipped, so "above" means a smaller y there.
        if hostingView.isFlipped {
            XCTAssertLessThanOrEqual(
                pinnedFrame.maxY,
                contentFrame.minY + 0.5,
                "The pinned header must be stacked above the scrolling content."
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                pinnedFrame.minY,
                contentFrame.maxY - 0.5,
                "The pinned header must be stacked above the scrolling content."
            )
        }
    }

    func testPagesWithoutAPinnedHeaderStillScrollTheirContent() {
        let hostingView = makeHostingView(
            SettingsPage {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )

        XCTAssertNil(findProbe(.pinned, in: hostingView))
        XCTAssertNotNil(
            enclosingScrollView(of: findProbe(.content, in: hostingView)),
            "A page without a pinned header keeps its existing scrolling layout."
        )
    }

    /// The preview spans the same width as the card groups below it. The rows
    /// inside those groups are inset by one row padding, which is where the
    /// option cards' selection rings end.
    func testPinnedHeaderMatchesTheCardGroupWidth() throws {
        let hostingView = makeHostingView(Self.probePage)

        let pinned = try XCTUnwrap(findProbe(.pinned, in: hostingView))
        let group = try XCTUnwrap(findProbe(.group, in: hostingView))
        let lastCard = try XCTUnwrap(
            findProbes(.card, in: hostingView).last,
            "The picture row should lay out its cards."
        )

        let pinnedFrame = pinned.convert(pinned.bounds, to: hostingView)
        let groupFrame = group.convert(group.bounds, to: hostingView)
        let cardFrame = lastCard.convert(lastCard.bounds, to: hostingView)

        XCTAssertEqual(
            pinnedFrame.minX,
            groupFrame.minX,
            accuracy: 0.5,
            "The pinned header shares the card group's left edge."
        )
        XCTAssertEqual(
            pinnedFrame.maxX,
            groupFrame.maxX,
            accuracy: 0.5,
            "The pinned header is exactly as wide as the card group."
        )
        XCTAssertEqual(
            pinnedFrame.maxX - (cardFrame.maxX + SettingsMetrics.selectionRingInset),
            SettingsMetrics.rowPaddingH,
            accuracy: 0.5,
            "The cards' selection rings stay one row padding inside the group."
        )
    }

    /// A scrollbar that takes layout space narrows the scrolling content, never
    /// the pane, so an overflowing page is where the preview and the groups used
    /// to end up one scroller apart.
    func testOverflowingPanesKeepThePreviewAndTheGroupsTheSameWidth() throws {
        let window = makeWindow()
        defer { window.orderOut(nil) }
        let hostingView = try XCTUnwrap(window.contentView)

        let pinned = try XCTUnwrap(findProbe(.pinned, in: hostingView))
        let content = try XCTUnwrap(findProbe(.content, in: hostingView))
        let scrollView = try XCTUnwrap(enclosingScrollView(of: content))

        // Scrolling makes the scroller real, which is what takes the gutter.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        hostingView.layoutSubtreeIfNeeded()

        let pinnedFrame = pinned.convert(pinned.bounds, to: hostingView)
        let contentFrame = content.convert(content.bounds, to: hostingView)

        XCTAssertEqual(
            pinnedFrame.minX,
            contentFrame.minX,
            accuracy: 0.5,
            "The pinned preview and the scrolling content share a left edge."
        )
        XCTAssertEqual(
            pinnedFrame.maxX,
            contentFrame.maxX,
            accuracy: 0.5,
            "The pinned preview and the scrolling content share a right edge."
        )
        XCTAssertLessThan(
            contentFrame.minY,
            pinnedFrame.minY,
            "The content really did scroll underneath the preview."
        )
        XCTAssertEqual(
            pinnedFrame.minY,
            SettingsMetrics.pageTopMargin,
            accuracy: 0.5,
            "The preview stays pinned at the top of the pane while the page scrolls."
        )
    }

    private static var probePage: some View {
        SettingsPage(pinnedHeader: {
            ProbeView(kind: .pinned)
                .frame(height: 40)
        }) {
            SettingsGroup {
                ProbeView(kind: .group)
                    .frame(maxWidth: .infinity, minHeight: 10)

                SettingsPictureRow(
                    title: "Ring stroke",
                    selection: .constant(ProbeOption.light),
                    options: [ProbeOption.light, .bold],
                    previewSize: CGSize(width: 68, height: 44),
                    caption: { _ in "A" },
                    preview: { _ in
                        ProbeView(kind: .card)
                            .frame(width: 68, height: 44)
                    }
                )
            }
        }
    }

    private func makeHostingView<Content: View>(_ view: Content) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 530, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    /// A windowed page. The scroller only becomes real once the scroll view is in
    /// a window, and a real scroller is what takes the gutter out of the content.
    private func makeWindow() -> NSWindow {
        let hostingView = NSHostingView(
            rootView: SettingsPage(pinnedHeader: {
                ProbeView(kind: .pinned)
                    .frame(height: 40)
            }) {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 530, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    private func findProbe(_ kind: ProbeKind, in root: NSView) -> NSView? {
        findProbes(kind, in: root).first
    }

    private func findProbes(_ kind: ProbeKind, in root: NSView) -> [NSView] {
        var found: [NSView] = []
        if let probe = root as? ProbeNSView, probe.kind == kind {
            found.append(probe)
        }
        for subview in root.subviews {
            found.append(contentsOf: findProbes(kind, in: subview))
        }
        return found
    }

    private func enclosingScrollView(of view: NSView?) -> NSScrollView? {
        var current = view?.superview
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView { return scrollView }
            current = candidate.superview
        }
        return nil
    }
}

private enum ProbeKind {
    case pinned
    case content
    case group
    case card
}

private enum ProbeOption: String, CaseIterable, Identifiable {
    case light
    case bold

    var id: String { rawValue }
}

private final class ProbeNSView: NSView {
    let kind: ProbeKind

    init(kind: ProbeKind) {
        self.kind = kind
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ProbeView: NSViewRepresentable {
    let kind: ProbeKind

    func makeNSView(context: Context) -> ProbeNSView {
        ProbeNSView(kind: kind)
    }

    func updateNSView(_ nsView: ProbeNSView, context: Context) {}
}
