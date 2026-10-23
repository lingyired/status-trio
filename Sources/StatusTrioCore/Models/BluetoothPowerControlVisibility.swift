import Foundation

enum BluetoothPowerControlVisibility {
    static func canConfigure(
        authorization: BluetoothAuthorizationStatus,
        showsInStatusPanel: Bool
    ) -> Bool {
        authorization == .allowed && showsInStatusPanel
    }

    static func showsPanelControl(
        authorization: BluetoothAuthorizationStatus,
        showsInStatusPanel: Bool,
        isEnabled: Bool
    ) -> Bool {
        isEnabled && canConfigure(
            authorization: authorization,
            showsInStatusPanel: showsInStatusPanel
        )
    }
}
