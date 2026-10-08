import Foundation

enum IconDesignerPreviewResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1) -> IconResolutionOutput {
        IconCompositionResolver.resolve(inputs: inputs, configuration: configuration)
    }

    @MainActor
    static func resolve(liveInputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        scenario: IconPreviewScenario) -> IconResolutionOutput {
        IconCompositionResolver.resolve(inputs: scenario.makeInputs(basedOn: liveInputs), configuration: configuration)
    }
}
