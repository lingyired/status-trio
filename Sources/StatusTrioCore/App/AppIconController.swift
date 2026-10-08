import AppKit
import Combine

@MainActor
protocol ApplicationDockIconApplying: AnyObject {
    func setApplicationIconImage(_ image: NSImage?)
}

extension NSApplication: ApplicationDockIconApplying {
    func setApplicationIconImage(_ image: NSImage?) {
        applicationIconImage = image
    }
}

@MainActor
final class AppIconController {
    typealias DockRenderer = (
        _ scene: IconSceneState,
        _ backgroundStyle: DockIconBackgroundStyle,
        _ pixelLength: Int
    ) -> NSImage?

    private let settings: SettingsStore
    private let iconPresentation: IconPresentationViewModel
    private let activationPolicy: AppActivationPolicy
    private let application: any ApplicationDockIconApplying
    private let setMenuBarVisible: (Bool) -> Void
    private let renderDockIcon: DockRenderer
    private let theme: () -> SystemIconAppearanceTheme
    private let isDarkAppearance: () -> Bool
    private let monitor: SystemIconAppearanceMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var renderCache = DockIconRenderCache()
    private let imageCache = DockIconImageCache()
    private let renderCoalescer = IconRenderCoalescer()
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentBackgroundPreference: DockIconBackgroundPreference
    private var latestIconOutput: IconPresentationOutput
    private var isDockTileVisible: Bool
    private var isStarted = false

    init(
        settings: SettingsStore,
        iconPresentation: IconPresentationViewModel,
        activationPolicy: AppActivationPolicy,
        application: any ApplicationDockIconApplying = NSApplication.shared,
        setMenuBarVisible: @escaping (Bool) -> Void,
        renderDockIcon: @escaping DockRenderer,
        theme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        isDarkAppearance: @escaping () -> Bool = {
            NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.settings = settings
        self.iconPresentation = iconPresentation
        self.activationPolicy = activationPolicy
        self.application = application
        self.setMenuBarVisible = setMenuBarVisible
        self.renderDockIcon = renderDockIcon
        self.theme = theme
        self.isDarkAppearance = isDarkAppearance
        self.monitor = SystemIconAppearanceMonitor(
            readTheme: theme,
            notificationCenter: notificationCenter
        )
        self.currentPlacement = settings.appIconPlacement
        self.currentBackgroundPreference = settings.dockIconBackgroundPreference
        self.latestIconOutput = iconPresentation.output
        self.isDockTileVisible = activationPolicy.isRegularApp
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Adopt whatever the settings hold now: they can change between
        // construction and the first start.
        currentPlacement = settings.appIconPlacement
        currentBackgroundPreference = settings.dockIconBackgroundPreference
        latestIconOutput = iconPresentation.output
        apply(currentPlacement)
        activationPolicy.$isRegularApp
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isRegular in
                // @Published emits before the stored value changes, so use the
                // value the publisher delivered.
                guard let self else { return }
                isDockTileVisible = isRegular
                dockTileVisibilityChanged()
            }
            .store(in: &cancellables)
        monitor.onChange = { [weak self] _ in
            self?.renderLatestDockIcon()
        }
        monitor.start()
        subscribeToPlacement()
        subscribeToIconPresentation()
        subscribeToBackgroundStyle()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        renderCoalescer.cancel()
        monitor.onChange = nil
        monitor.stop()
        clearDockIcon()
    }

    func refreshCurrentPresentation() {
        renderLatestDockIcon()
    }

    func flushPendingPresentationForTesting() {
        renderCoalescer.flushPending()
    }

    private func dockTileVisibilityChanged() {
        guard isDockTileVisible else {
            clearDockIcon()
            return
        }
        renderLatestDockIcon()
    }

    private func clearDockIcon() {
        defer { renderCache.reset() }
        guard hasRenderedDockIcon else { return }
        application.setApplicationIconImage(nil)
        hasRenderedDockIcon = false
    }

    private func subscribeToPlacement() {
        settings.$appIconPlacement
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] placement in
                self?.apply(placement)
            }
            .store(in: &cancellables)
    }

    private func subscribeToIconPresentation() {
        iconPresentation.$output
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] output in
                guard let self else { return }
                latestIconOutput = output
                renderCoalescer.submit { [weak self] in
                    self?.renderLatestDockIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToBackgroundStyle() {
        settings.$dockIconBackgroundPreference
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] preference in
                guard let self else { return }
                currentBackgroundPreference = preference
                renderLatestDockIcon()
            }
            .store(in: &cancellables)
    }

    private func apply(_ placement: AppIconPlacement) {
        currentPlacement = placement

        if placement.showsDockIcon {
            let didActivate = activationPolicy.setDockIconVisible(true)
            isDockTileVisible = activationPolicy.isRegularApp
            guard didActivate else {
                // Never trade the Menu Bar away for a Dock tile AppKit refused.
                setMenuBarVisible(true)
                return
            }
            renderLatestDockIcon()
            setMenuBarVisible(placement.showsMenuBarIcon)
        } else {
            setMenuBarVisible(true)
            _ = activationPolicy.setDockIconVisible(false)
            isDockTileVisible = activationPolicy.isRegularApp
        }
    }

    private func renderLatestDockIcon() {
        guard isDockTileVisible else { return }

        let backgroundStyle = DockIconBackgroundResolver.style(
            for: currentBackgroundPreference,
            theme: theme(),
            isDarkAppearance: isDarkAppearance()
        )
        let key = DockIconRenderKey(
            scene: latestIconOutput.scene,
            backgroundStyle: backgroundStyle,
            pixelLength: DockIconRenderer.pixelSize
        )
        guard renderCache.needsRender(key) else { return }

        if let cached = imageCache.image(for: key) {
            application.setApplicationIconImage(cached)
            renderCache.recordSuccessfulRender(key)
            hasRenderedDockIcon = true
            return
        }

        guard let image = renderDockIcon(latestIconOutput.scene, backgroundStyle, key.pixelLength) else {
            if !hasRenderedDockIcon {
                application.setApplicationIconImage(nil)
            }
            return
        }

        imageCache.store(image, for: key)
        renderCache.recordSuccessfulRender(key)
        application.setApplicationIconImage(image)
        hasRenderedDockIcon = true
    }
}
