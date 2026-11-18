enum BuiltinIconPlugins {
    private static let registry: IconContentPluginRegistry = {
        do {
            return try IconContentPluginRegistry(plugins: [
                InputSourceIconPlugin(), NetworkIconPlugin(), BluetoothDeviceIconPlugin(),
                SystemBatteryIconPlugin(), AirPodsBatteryIconPlugin(),
                HardwareMonitorIconPlugin(), SystemVolumeIconPlugin(), LegacyIconPlugin()
            ])
        } catch {
            preconditionFailure("Invalid compiled icon plugin catalogue: \(error)")
        }
    }()

    static func makeRegistry() -> IconContentPluginRegistry { registry }
}
