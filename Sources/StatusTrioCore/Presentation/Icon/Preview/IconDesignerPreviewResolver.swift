import Foundation

enum IconDesignerPreviewResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1) -> IconResolutionOutput {
        IconCompositionResolver.resolve(inputs: inputs, configuration: configuration)
    }

    static func resolve(
        liveInputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        mode: IconPreviewDataMode,
        samples: IconPreviewSampleValues,
        target: IconDesignerBluetoothTarget,
        now: Date
    ) -> IconResolutionOutput {
        let inputs: IconResolutionInputs
        switch mode {
        case .live:
            inputs = liveInputs
        case .simulated:
            inputs = IconPreviewInputBuilder.simulated(
                samples: samples,
                configuration: configuration,
                target: target,
                now: now
            )
        }
        return IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)
    }

    @MainActor
    static func resolve(liveInputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        scenario: IconPreviewScenario,
                        customAirPodsSample: CustomAirPodsPreviewSample = CustomAirPodsPreviewSample()) -> IconResolutionOutput {
        IconCompositionResolver.resolve(
            inputs: scenario.makeInputs(basedOn: liveInputs, customAirPodsSample: customAirPodsSample),
            configuration: configuration
        )
    }
}
