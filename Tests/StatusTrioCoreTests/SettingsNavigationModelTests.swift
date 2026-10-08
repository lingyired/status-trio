import Testing
@testable import StatusTrioCore

@Suite("Settings navigation model")
struct SettingsNavigationModelTests {
    @Test func defaultsToDesignerAndKeepsAllDevicePagesReachable() {
        let model = SettingsNavigationModel()
        #expect(model.selection == .iconDesigner)
        #expect(SettingsNavigationModel.devicePages == [.battery, .network, .bluetooth, .audio])
        #expect(SettingsNavigationModel.allPages == [
            .iconDesigner, .battery, .network, .bluetooth, .audio, .popover, .general, .about
        ])
    }

    @Test func legacyAppIconDestinationOpensDesignerPlacementGroup() {
        let destination = SettingsNavigationModel.destination(forLegacyPage: .appIcon)
        #expect(destination == .iconDesigner)
        #expect(destination.legacyFocus == .placement)
    }
}
