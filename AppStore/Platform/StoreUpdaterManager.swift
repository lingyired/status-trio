import Combine
import Foundation
import SwiftUI

/// Store-side stand-in for the Direct-only `UpdaterManager` (Sparkle).
///
/// App Store builds use system-managed updates, so there is no in-app check.
/// This supplies the observable surface the shared settings/status UI reads.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(get: { self.automaticallyChecksForUpdates }, set: { _ in })
    }

    func start(activationPolicy: AppActivationPolicy) {}
    func checkForUpdates() {}
}
