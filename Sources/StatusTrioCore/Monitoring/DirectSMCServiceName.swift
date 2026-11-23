import Foundation

extension SMCReadOnlyClient {
    /// Installs the concrete AppleSMC IOKit service name for the Direct build.
    static func installDirectDefaults() {
        smcServiceName = "AppleSMC"
    }
}
