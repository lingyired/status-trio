import CoreLocation

enum WiFiNameAccessRequestResult: Equatable, Sendable {
    case requested
    case openLocationSettings
    case notNeeded
}

@MainActor
protocol WiFiNameAuthorizing: AnyObject {
    var access: WiFiNameAccess { get }
    var onAccessChange: (() -> Void)? { get set }

    @discardableResult
    func requestAccess() -> WiFiNameAccessRequestResult
}

@MainActor
final class CoreLocationWiFiNameAuthorizer: NSObject, WiFiNameAuthorizing {
    private let manager: CLLocationManager
    private var hasRequestedAuthorization = false

    /// The status Core Location last reported to the delegate. Every Wi-Fi reading
    /// checks this on the main actor, and `manager.authorizationStatus` can block
    /// on a synchronous reply from locationd that never comes while locationd is
    /// stuck. Until the first report, the network name is treated as undetermined.
    private(set) var access: WiFiNameAccess = .notDetermined

    var onAccessChange: (() -> Void)?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    @discardableResult
    func requestAccess() -> WiFiNameAccessRequestResult {
        switch access {
        case .notDetermined:
            // Core Location does not report whether its prompt was displayed.
            // A later explicit click must offer a way out if the first request
            // left permission undecided, instead of silently requesting forever.
            guard !hasRequestedAuthorization else { return .openLocationSettings }
            hasRequestedAuthorization = true
            manager.requestWhenInUseAuthorization()
            return .requested
        case .denied, .restricted:
            return .openLocationSettings
        case .authorized:
            return .notNeeded
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> WiFiNameAccess {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}

extension CoreLocationWiFiNameAuthorizer: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Core Location calls this once it holds locationd's report, so the
        // status read here is answered from that report.
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.access = Self.map(status)
            self.onAccessChange?()
        }
    }
}
