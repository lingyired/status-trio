import Combine
import Foundation

/// Temporary bridge from the in-memory preview samples to the real Menu Bar and
/// Dock presentation. The opt-in lives only on the preview session.
@MainActor
final class IconDesignerRealIconOverrideBridge {
    private let session: IconDesignerPreviewSession
    private let settings: SettingsStore
    private let iconPresentation: IconPresentationViewModel
    private var subscription: AnyCancellable?

    init(
        session: IconDesignerPreviewSession,
        settings: SettingsStore,
        iconPresentation: IconPresentationViewModel
    ) {
        self.session = session
        self.settings = settings
        self.iconPresentation = iconPresentation
    }

    func start() {
        guard subscription == nil else { return }
        subscription = Publishers.CombineLatest(
            session.realIconOverrideChanges
                .prepend(()),
            settings.iconPresentationPublisher
        )
        .sink { [weak self] _, presentationSettings in
            guard let self else { return }
            self.apply(presentationSettings: presentationSettings)
        }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        iconPresentation.clearRealIconOverride()
    }

    private func apply(presentationSettings: IconPresentationSettings) {
        guard session.mode == .simulated, session.appliesToRealIcons else {
            iconPresentation.clearRealIconOverride()
            return
        }

        let target = settings.connectedBluetoothIconDeviceAddress.map {
            IconDesignerBluetoothTarget.connectedDevice(
                address: BluetoothBatteryReader.normalizedAddress($0)
            )
        } ?? .currentAudioOutput
        let inputs = IconPreviewInputBuilder.simulated(
            samples: session.samples,
            configuration: settings.iconConfiguration,
            target: target,
            now: .now,
            runtimeOptions: settings.iconRuntimePresentationOptions
        )
        let resolution = IconCompositionResolver.resolve(
            inputs: inputs,
            configuration: settings.iconConfiguration
        )
        iconPresentation.setRealIconOverride(IconPresentationOutput(
            scene: resolution.scene,
            menuBarSize: presentationSettings.menuBarSize,
            trace: resolution.trace
        ))
    }
}
