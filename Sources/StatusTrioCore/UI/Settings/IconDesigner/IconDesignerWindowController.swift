import AppKit
import Combine
import SwiftUI

@MainActor
final class IconDesignerWindowController: NSWindowController, NSWindowDelegate {
    static let initialContentSize = NSSize(width: 1120, height: 800)
    static let minimumContentSize = NSSize(width: 900, height: 680)

    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private let chargingEffectClock: ChargingEffectClock
    let previewSession: IconDesignerPreviewSession
    private lazy var previewDataWindowController = IconPreviewDataWindowController(
        store: store, statusStore: statusStore, localization: localization, previewSession: previewSession
    )
    private var localizationCancellable: AnyCancellable?
    private var authorizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    private var lastBluetoothAuthorization: BluetoothAuthorizationStatus

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        chargingEffectClock: ChargingEffectClock,
        previewSession: IconDesignerPreviewSession = IconDesignerPreviewSession()
    ) {
        self.store = store
        self.statusStore = statusStore
        self.localization = localization
        self.activationPolicy = activationPolicy
        self.chargingEffectClock = chargingEffectClock
        self.previewSession = previewSession
        self.lastBluetoothAuthorization = statusStore.bluetoothDevices.authorizationStatus
        super.init(window: nil)

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] language in self?.applyLocalization(language: language) }
        authorizationCancellable = statusStore.bluetoothDevices.$authorizationStatus
            .dropFirst()
            .sink { [weak self] status in
                guard let self else { return }
                let wasUndetermined = self.lastBluetoothAuthorization == .notDetermined
                self.lastBluetoothAuthorization = status
                if wasUndetermined, status != .notDetermined { self.resurface() }
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(slot: IconSlot = .outerRing) {
        previewSession.selectedSlot = slot
        let window = window ?? makeWindow()
        self.window = window
        statusStore.setSettingsVisible(true, owner: SettingsSurfaceVisibility.designerOwner)
        applyLocalization()
        if !ownsActivationPolicy {
            ownsActivationPolicy = true
            activationPolicy.enterTemporaryRegularMode()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        previewDataWindowController.window?.close()
        statusStore.setSettingsVisible(false, owner: SettingsSurfaceVisibility.designerOwner)
        if ownsActivationPolicy {
            ownsActivationPolicy = false
            activationPolicy.leaveTemporaryRegularMode()
        }
        window?.contentView = nil
        window = nil
    }

    func resurface() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeDesignerView() -> IconDesignerView {
        IconDesignerView(
            store: store,
            statusStore: statusStore,
            onEditSamples: { [weak self] in
                guard let self, let parent = self.window else { return }
                self.previewDataWindowController.show(relativeTo: parent)
            },
            previewSession: previewSession
        )
    }

    private func makeWindow() -> NSWindow {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: Self.initialContentSize)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let size = Self.contentSizeThatFits(
            Self.initialContentSize, in: screenFrame, styleMask: styleMask
        )
        let initialFrame = Self.centeredFrame(contentSize: size, in: screenFrame, styleMask: styleMask)
        let initialContentRect = NSWindow.contentRect(forFrameRect: initialFrame, styleMask: styleMask)
        let window = NSWindow(
            contentRect: initialContentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(
            width: min(Self.minimumContentSize.width, size.width),
            height: min(Self.minimumContentSize.height, size.height)
        )
        window.contentView = NSHostingView(rootView: LocalizedRootView(localization: localization) {
            makeDesignerView()
                .environmentObject(chargingEffectClock)
        })
        window.delegate = self
        window.isReleasedWhenClosed = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Registering the autosave name may restore the user's prior frame. Keep
        // it when valid; only constrain a restored frame that escaped this screen.
        window.setFrameAutosaveName("IconDesignerWindow.v1")
        Self.clampRestoredFrame(window, to: screenFrame, styleMask: styleMask)
        return window
    }

    static func contentSizeThatFits(
        _ requestedSize: NSSize,
        in visibleFrame: NSRect,
        styleMask: NSWindow.StyleMask
    ) -> NSSize {
        let maximumContentSize = NSWindow.contentRect(forFrameRect: visibleFrame, styleMask: styleMask).size
        return NSSize(
            width: min(requestedSize.width, maximumContentSize.width),
            height: min(requestedSize.height, maximumContentSize.height)
        )
    }

    static func centeredFrame(
        contentSize: NSSize,
        in visibleFrame: NSRect,
        styleMask: NSWindow.StyleMask
    ) -> NSRect {
        let fittedSize = contentSizeThatFits(contentSize, in: visibleFrame, styleMask: styleMask)
        let frame = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: fittedSize),
            styleMask: styleMask
        )
        return NSRect(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
    }

    private static func clampRestoredFrame(
        _ window: NSWindow,
        to visibleFrame: NSRect,
        styleMask: NSWindow.StyleMask
    ) {
        var frame = window.frame
        if frame.width > visibleFrame.width || frame.height > visibleFrame.height {
            let maximumContentSize = NSWindow.contentRect(forFrameRect: visibleFrame, styleMask: styleMask).size
            window.setContentSize(NSSize(
                width: min(window.contentView?.bounds.width ?? maximumContentSize.width, maximumContentSize.width),
                height: min(window.contentView?.bounds.height ?? maximumContentSize.height, maximumContentSize.height)
            ))
            frame = window.frame
        }
        guard !visibleFrame.contains(frame) else { return }
        frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.iconDesignerTitle, language: language)
        window?.contentView?.userInterfaceLayoutDirection = language.nsLayoutDirection
    }
}
