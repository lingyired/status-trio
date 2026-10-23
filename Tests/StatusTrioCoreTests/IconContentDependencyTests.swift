import Testing
@testable import StatusTrioCore

struct IconContentDependencyTests {
    @Test func oneBatterySampleServesTwoElements() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        configuration.composition.footer = SlotSelection(primary: .none)
        let dependencies = IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: false)
        #expect(dependencies.samples == [.macBattery])
        #expect(dependencies.requiresBluetoothMonitor == false)
    }

    @Test func fallbackAndOverrideDependenciesAreIncluded() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing.fallback = .airPodsBattery
        configuration.composition.center = SlotSelection(primary: .none)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        let dependencies = IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: false)
        #expect(dependencies.samples == [.macBattery, .airPods, .network, .systemVolume])
        #expect(dependencies.requiresBluetoothMonitor)
        #expect(dependencies.requiresAirPodsBattery)
    }

    @Test func onlyAudioBluetoothColorDependsOnVolume() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing = SlotSelection(primary: .none)
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.composition.footer = SlotSelection(primary: .none)
        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        #expect(IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: true).samples == [.bluetoothTarget, .systemVolume])
        #expect(IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: false).samples == [.bluetoothTarget])
        configuration.composition.center = SlotSelection(primary: .none, fallback: .connectedBluetoothDevice)
        #expect(IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: true).requiresBluetoothMonitor == false)
    }

    @Test func registryControlsDependenciesAndCapabilities() throws {
        let fake = TestIconContentPlugin(descriptor: .init(id: "builtin.system-battery", presentations: [
            .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceSystemBattery, isSelectable: true)
        ]))
        let registry = try IconContentPluginRegistry(plugins: [fake])
        #expect(IconContentDependencyResolver.dependencies(configuration: IconDesignerDefaults.configuration(), targetIsAudio: true, registry: registry).samples.isEmpty)
        #expect(IconDesignerEditingModel.selectableSources(for: .outerRing, registry: registry) == [.ring(.systemBattery), .ring(.none)])
        #expect(registry.capabilities(for: .init(pluginID: "builtin.system-battery", presentationID: "ring"), context: .init(configuration: .classic, targetIsAudio: false)).isEmpty)
    }
}
