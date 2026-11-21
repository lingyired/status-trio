import Testing
@testable import StatusTrioCore

@MainActor
struct PanelLevelSliderColorSelectionTests {
    @Test func storageIsLosslessAndInvalidValuesFallBackToAutomatic() {
        let custom = PanelLevelSliderColorSelection.custom(
            IconRGBA(red: 0.2, green: 0.45, blue: 0.8, alpha: 1)
        )
        for selection in [PanelLevelSliderColorSelection.automatic, custom] {
            #expect(PanelLevelSliderColorSelection(storageValue: selection.storageValue) == selection)
        }
        for invalid in ["", "custom:2,0.5,0.5,1", "custom:0.5,0.5,0.5", "custom:nan,0,0,1", "white"] {
            #expect(PanelLevelSliderColorSelection(storageValue: invalid) == .automatic)
        }
    }

    @Test func defaultIsAutomatic() {
        #expect(PanelLevelSliderColorSelection.default == .automatic)
    }
}
