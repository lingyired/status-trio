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
    private let imageCache: DockIconImageCache
    private let renderCoalescer: IconRenderCoalescer
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentBackgroundPreference: DockIconBackgroundPreference
    private var latestIconOutput: IconPresentationOutput
    private var isDockTileVisible: Bool
    private var isDockChargingEffectEnabled: Bool
    private var isStarted = false
    /// While the Dock presenter owns `dockTile.contentView`, changing
    /// `applicationIconImage` would replace the animated tile with a static
    /// image. The presenter is then the only writer of the Dock's visuals.
    private var isDockChargingAnimationActive = false
    /// Fires when the user's placement or the live activation policy changes
    /// whether the Dock may own the animation.
    var dockChargingAnimationEligibilityDidChange: (@MainActor () -> Void)?
    /// Fires when the scene or resolved tile style the Dock should draw changes.
    var dockContentDidChange: (@MainActor () -> Void)?
    /// Re-exposes the existing system-appearance poll to AppEnvironment.
    var systemPollDidFire: (@MainActor () -> Void)?
    private var reportedDockAnimationEligibility: Bool?
    /// The placement is the user's own choice; a window that temporarily makes
    /// the app regular must not claim the animation's only surface.
    var isDockChargingAnimationEligible: Bool {
        currentPlacement.showsDockIcon && isDockTileVisible && activationPolicy.isRegularApp
    }
    var latestScene: IconSceneState { latestIconOutput.scene }
    /// The Dock animation follows the synthetic charging preview only while the
    /// explicit test switch is on; a normal launch stays on the real scene.
    var latestAnimationScene: IconSceneState {
        (latestIconOutput.menuBarTestScene ?? latestIconOutput.scene)
            .withChargingEffectEnabled(isDockChargingEffectEnabled)
    }
    var currentDockBackgroundStyle: DockIconBackgroundStyle { currentBackgroundStyle() }

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
        notificationCenter: NotificationCenter = .default,
        renderCoalescer: IconRenderCoalescer? = nil,
        imageCache: DockIconImageCache? = nil
    ) {
        self.settings = settings
        self.iconPresentation = iconPresentation
        self.activationPolicy = activationPolicy
        self.application = application
        self.setMenuBarVisible = setMenuBarVisible
        self.renderDockIcon = renderDockIcon
        self.renderCoalescer = renderCoalescer ?? IconRenderCoalescer()
        self.imageCache = imageCache ?? DockIconImageCache()
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
        self.isDockChargingEffectEnabled = settings.showsDockChargingEffect
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
            self?.dockContentDidChange?()
        }
        monitor.onPoll = { [weak self] in
            self?.systemPollDidFire?()
        }
        monitor.start()
        subscribeToPlacement()
        subscribeToIconPresentation()
        subscribeToBackgroundStyle()
        subscribeToChargingEffectPreference()
    }

    func stop() {
        guard isStarted else {
            imageCache.reset()
            return
        }
        isStarted = false
        cancellables.removeAll()
        renderCoalescer.cancel()
        monitor.onChange = nil
        monitor.onPoll = nil
        monitor.stop()
        dockChargingAnimationEligibilityDidChange = nil
        dockContentDidChange = nil
        systemPollDidFire = nil
        isDockChargingAnimationActive = false
        reportedDockAnimationEligibility = nil
        clearDockIcon()
    }

    func refreshCurrentPresentation() {
        renderLatestDockIcon()
    }

    func flushPendingPresentationForTesting() {
        renderCoalescer.flushPending()
    }

    func setDockChargingAnimationActive(_ isActive: Bool) {
        guard isDockChargingAnimationActive != isActive else { return }
        isDockChargingAnimationActive = isActive
        renderCache.reset()
        if !isActive {
            renderLatestDockIcon()
        }
    }

    private func dockTileVisibilityChanged() {
        defer { notifyDockAnimationEligibility() }
        guard isDockTileVisible else {
            clearDockIcon()
            dockContentDidChange?()
            return
        }
        renderLatestDockIcon()
    }

    func releaseCachedImages() {
        imageCache.reset()
    }

    private func clearDockIcon() {
        imageCache.reset()
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
                dockContentDidChange?()
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
                dockContentDidChange?()
            }
            .store(in: &cancellables)
    }

    private func subscribeToChargingEffectPreference() {
        settings.$showsDockChargingEffect
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                isDockChargingEffectEnabled = isEnabled
                renderCache.reset()
                renderLatestDockIcon()
            }
            .store(in: &cancellables)
    }

    private func apply(_ placement: AppIconPlacement) {
        currentPlacement = placement
        defer { notifyDockAnimationEligibility() }

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
        guard !isDockChargingAnimationActive else { return }

        let backgroundStyle = currentBackgroundStyle()
        let scene = latestIconOutput.scene
            .withChargingEffectEnabled(isDockChargingEffectEnabled)
        let key = DockIconRenderKey(
            scene: scene,
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

        guard let image = renderDockIcon(scene, backgroundStyle, key.pixelLength) else {
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

    private func currentBackgroundStyle() -> DockIconBackgroundStyle {
        DockIconBackgroundResolver.style(
            for: currentBackgroundPreference,
            theme: theme(),
            isDarkAppearance: isDarkAppearance()
        )
    }

    /// Reports only real transitions: a placement change that also moves the
    /// activation policy would otherwise notify the same state twice.
    private func notifyDockAnimationEligibility() {
        let isEligible = isDockChargingAnimationEligible
        guard reportedDockAnimationEligibility != isEligible else { return }
        reportedDockAnimationEligibility = isEligible
        dockChargingAnimationEligibilityDidChange?()
    }
}
