enum BuiltinIconPlugins {
    static func makePlugins() -> [any IconContentPlugin] {
        [
            InputSourceIconPlugin(), NetworkIconPlugin(), BluetoothDeviceIconPlugin(),
            SystemBatteryIconPlugin(), AirPodsBatteryIconPlugin(),
            HardwareMonitorIconPlugin(), SystemVolumeIconPlugin(), LegacyIconPlugin()
        ]
    }

    private static let registry: IconContentPluginRegistry = {
        do {
            return try IconContentPluginRegistry(plugins: makePlugins())
        } catch {
            preconditionFailure("Invalid compiled icon plugin catalogue: \(error)")
        }
    }()

    static func makeRegistry() -> IconContentPluginRegistry { registry }
}
