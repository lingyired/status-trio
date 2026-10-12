import AppKit
import Combine
import SwiftUI

@MainActor
final class IconPreviewDataWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 380, height: 520)
    static let minimumContentSize = NSSize(width: 340, height: 360)

    let previewSession: IconDesignerPreviewSession
    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let localization: Localization
    private weak var parentWindow: NSWindow?
    private var localizationCancellable: AnyCancellable?

    init(store: SettingsStore, statusStore: SystemStatusStore, localization: Localization,
         previewSession: IconDesignerPreviewSession) {
        self.store = store
        self.statusStore = statusStore
        self.localization = localization
        self.previewSession = previewSession
        super.init(window: nil)
        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyLocalization() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(relativeTo parent: NSWindow) {
        parentWindow = parent
        let panel = window as? IconPreviewDataPanel ?? makePanel()
        window = panel
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        applyLocalization()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSWindow, let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        window?.contentView = nil
        window = nil
        parentWindow = nil
    }

    private func makePanel() -> IconPreviewDataPanel {
        let panel = IconPreviewDataPanel(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                                         styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                         backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = true
        panel.contentMinSize = Self.minimumContentSize
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LocalizedRootView(localization: localization) {
            IconPreviewDataView(session: previewSession, store: store, statusStore: statusStore,
                                localization: localization)
        })
        let restored = panel.setFrameAutosaveName("IconPreviewDataWindow.v1")
        if restored {
            Self.clampRestoredFrame(panel, to: panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame)
        } else {
            position(panel, relativeTo: parentWindow)
        }
        return panel
    }

    private func applyLocalization() {
        (window as? NSPanel)?.title = localization.string(.iconPreviewDataTitle)
    }

    static func clampRestoredFrame(_ panel: NSWindow, to visibleFrame: NSRect) {
        var frame = panel.frame
        let maxContent = NSWindow.contentRect(forFrameRect: visibleFrame, styleMask: panel.styleMask).size
        if frame.width > visibleFrame.width || frame.height > visibleFrame.height {
            let width = min(contentSize.width, maxContent.width)
            let height = min(contentSize.height, maxContent.height)
            panel.setContentSize(NSSize(width: width, height: height))
            frame = panel.frame
        }
        if frame.width > visibleFrame.width { frame.size.width = visibleFrame.width }
        if frame.height > visibleFrame.height { frame.size.height = visibleFrame.height }
        frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        if frame != panel.frame { panel.setFrame(frame, display: false) }
    }

    private func position(_ panel: NSWindow, relativeTo parent: NSWindow?) {
        let visible = parent?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let origin = NSPoint(x: parent?.frame.maxX ?? visible.midX, y: parent?.frame.maxY ?? visible.midY)
        var frame = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: panel.styleMask)
        frame.origin = origin
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }
}

@MainActor
private final class IconPreviewDataPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
