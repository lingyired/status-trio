import AppKit
import Combine
import SwiftUI

@MainActor
final class ShortcutRecorderButton: NSButton {
    private let settings: SettingsStore
    private let controller: GlobalShortcutController
    private let localization: Localization
    private let layoutLabelProvider: ((StatusPanelShortcut) -> String)?
    private let inputSourceNotificationObserver: any InputSourceNotificationObserving
    private let currentModifierFlagsProvider: () -> NSEvent.ModifierFlags
    private let capturesCurrentPhysicalModifiers: Bool
    private var cancellables = Set<AnyCancellable>()
    private var layoutChangeObserver: NSObjectProtocol?
    private var windowKeyObserver: NSObjectProtocol?
    private weak var observedWindow: NSWindow?
    private var currentIsRecording = false
    private var currentShortcut: StatusPanelShortcut?
    private var currentLanguage: AppLanguage

    init(
        settings: SettingsStore,
        controller: GlobalShortcutController,
        localization: Localization,
        layoutLabelProvider: ((StatusPanelShortcut) -> String)? = nil,
        inputSourceNotificationObserver: (any InputSourceNotificationObserving)? = nil,
        currentModifierFlagsProvider: @escaping () -> NSEvent.ModifierFlags = {
            NSEvent.modifierFlags
        },
        capturesCurrentPhysicalModifiers: Bool = true
    ) {
        self.settings = settings
        self.controller = controller
        self.localization = localization
        self.layoutLabelProvider = layoutLabelProvider
        self.inputSourceNotificationObserver =
            inputSourceNotificationObserver ?? SystemInputSourceNotificationObserver()
        self.currentModifierFlagsProvider = currentModifierFlagsProvider
        self.capturesCurrentPhysicalModifiers = capturesCurrentPhysicalModifiers
        self.currentShortcut = settings.statusPanelShortcut
        self.currentLanguage = localization.resolvedLanguage
        super.init(frame: .zero)
        configure()
        observePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func performClick(_ sender: Any?) {
        beginRecording()
    }

    func beginRecording() {
        guard !controller.isRecording else { return }
        controller.beginRecording()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard controller.isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordingEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard controller.isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingEvent(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard !controller.isRecording else { return }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if controller.isRecording {
            controller.endRecording()
        }
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        updateWindowObservers(for: newWindow)
        if newWindow == nil, window != nil, controller.isRecording {
            controller.endRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func endRecordingForRemoval() {
        controller.endRecording()
        removeWindowKeyObserver()
        removeLayoutChangeObserver()
    }

    func handleWindowDidResignKey() {
        guard controller.isRecording else { return }
        controller.endRecording()
    }

    private func configure() {
        title = localization.string(.settingsShortcutRecord)
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        target = self
        action = #selector(beginRecordingFromClick)
        setAccessibilityIdentifier("settings.shortcut.recorder")
    }

    private func observePresentation() {
        controller.$isRecording
            .combineLatest(
                settings.$statusPanelShortcut,
                localization.$resolvedLanguage
            )
            .sink { [weak self] isRecording, shortcut, language in
                guard let self else { return }
                currentIsRecording = isRecording
                currentShortcut = shortcut
                currentLanguage = language
                refreshPresentation(
                    isRecording: isRecording,
                    shortcut: shortcut,
                    language: language
                )
            }
            .store(in: &cancellables)
    }

    private func refreshPresentation(
        isRecording: Bool,
        shortcut: StatusPanelShortcut?,
        language: AppLanguage
    ) {
        if isRecording {
            title = localization.string(.settingsShortcutRecording, language: language)
            setAccessibilityLabel(
                localization.string(.settingsShortcutRecording, language: language)
            )
            setAccessibilityHelp(
                localization.string(.settingsShortcutInvalid, language: language)
            )
            return
        }

        if let shortcut {
            let display = layoutLabelProvider?(shortcut)
                ?? ShortcutKeyLabel.string(for: shortcut)
            title = display
            setAccessibilityLabel(
                localization.string(.settingsShortcutChange, language: language)
            )
            setAccessibilityValue(
                String(
                    format: localization.string(
                        .settingsShortcutAccessibilityCurrent,
                        language: language
                    ),
                    locale: language.locale,
                    arguments: [display]
                )
            )
        } else {
            title = localization.string(.settingsShortcutRecord, language: language)
            setAccessibilityLabel(
                localization.string(.settingsShortcutRecord, language: language)
            )
            setAccessibilityValue(
                localization.string(
                    .settingsShortcutAccessibilityUnassigned,
                    language: language
                )
            )
        }
    }

    private func updateWindowObservers(for newWindow: NSWindow?) {
        guard newWindow !== observedWindow else { return }
        removeWindowKeyObserver()
        observedWindow = newWindow
        guard let newWindow else { return }
        windowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWindowDidResignKey()
            }
        }

        if layoutChangeObserver == nil {
            layoutChangeObserver = inputSourceNotificationObserver.observe(
                InputSourceNotifications.selectedSourceChanged
            ) { [weak self] in
                self?.refreshForLayoutChange()
            }
        }
    }

    private func removeWindowKeyObserver() {
        guard let windowKeyObserver else { return }
        NotificationCenter.default.removeObserver(windowKeyObserver)
        self.windowKeyObserver = nil
    }

    private func removeLayoutChangeObserver() {
        guard let layoutChangeObserver else { return }
        inputSourceNotificationObserver.remove(layoutChangeObserver)
        self.layoutChangeObserver = nil
    }

    private func refreshForLayoutChange() {
        guard !currentIsRecording else { return }
        refreshPresentation(
            isRecording: currentIsRecording,
            shortcut: currentShortcut,
            language: currentLanguage
        )
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        switch event.keyCode {
        case 53:
            controller.cancelRecording()
            window?.makeFirstResponder(nil)
            return
        case 51, 117:
            controller.clearShortcut()
            window?.makeFirstResponder(nil)
            return
        default:
            break
        }

        let modifiers = recordingModifiers(for: event)
        guard let shortcut = StatusPanelShortcut(
            keyCode: UInt32(event.keyCode),
            modifierFlags: modifiers
        ) else {
            controller.reportInvalidShortcut()
            return
        }
        if controller.setShortcut(shortcut) {
            window?.makeFirstResponder(nil)
        }
    }

    private func recordingModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        guard capturesCurrentPhysicalModifiers else {
            return event.modifierFlags
        }
        // WeType can replace the first Space key event with an Option-less
        // event. The physical modifier state is still authoritative.
        return currentModifierFlagsProvider()
            .intersection(.deviceIndependentFlagsMask)
    }

    @objc private func beginRecordingFromClick() {
        beginRecording()
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let settings: SettingsStore
    let controller: GlobalShortcutController
    let localization: Localization

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(
            settings: settings,
            controller: controller,
            localization: localization
        )
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {}

    static func dismantleNSView(
        _ nsView: ShortcutRecorderButton,
        coordinator: ()
    ) {
        nsView.endRecordingForRemoval()
    }
}

struct ShortcutSettingsRow: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: GlobalShortcutController
    @ObservedObject var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                "keyboard",
                tint: .indigo,
                title: localization.string(.settingsShortcutTitle),
                subtitle: localization.string(.settingsShortcutDescription),
                subtitleStatus: statusText
            ) {
                HStack(spacing: 8) {
                    ShortcutRecorder(
                        settings: store,
                        controller: controller,
                        localization: localization
                    )
                    .frame(width: 132, height: 24)

                    if store.statusPanelShortcut != nil {
                        ShortcutClearButton(
                            title: localization.string(.settingsShortcutClear),
                            action: { controller.clearShortcut() }
                        )
                        .frame(width: 54, height: 24)
                    }
                }
            }

            if let feedback = controller.feedback {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(localization.string(feedback.localizationKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 9)
            }
        }
    }

    private var statusText: Text {
        if controller.isRecording {
            return Text(localization.string(.settingsShortcutRecording))
        }
        if store.statusPanelShortcut == nil {
            return Text(localization.string(.settingsShortcutNotSet))
        }
        return Text("")
    }
}

struct ShortcutClearButton: NSViewRepresentable {
    let title: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier("settings.shortcut.clear")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = title
        nsView.setAccessibilityLabel(title)
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}
