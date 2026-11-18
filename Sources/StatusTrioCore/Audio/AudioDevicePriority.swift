import CoreAudio
import Foundation

struct RememberedAudioDevice: Codable, Equatable, Identifiable, Sendable {
    let uid: String
    var name: String
    var id: String { uid }
}

struct AudioPriorityDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String?
    let name: String?
}

struct AudioPriorityConfiguration: Equatable, Sendable {
    var enabled = false
    var order: [String] = []
    var hiddenUIDs: Set<String> = []
}

typealias AudioPriorityCompletion = @MainActor @Sendable (Bool) -> Void

/// Invalidated synchronously by a newer manual action or configuration change,
/// and checked on the serial HAL worker immediately before an automatic write.
final class AudioPriorityRequest: @unchecked Sendable {
    let expectedUID: String?
    init(expectedUID: String? = nil) { self.expectedUID = expectedUID }
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }
    func cancel() {
        lock.lock()
        valid = false
        lock.unlock()
    }
}

enum AudioPrioritySelector {
    static func target(devices: [AudioPriorityDevice],
                       configuration: AudioPriorityConfiguration) -> AudioPriorityDevice? {
        guard configuration.enabled else { return nil }
        let candidates = devices.filter {
            guard let uid = $0.uid, !uid.isEmpty else { return false }
            return !configuration.hiddenUIDs.contains(uid)
        }
        return AudioDeviceOrder.ordered(candidates, using: configuration.order, uid: \.uid).first
    }
}

/// One instance per direction. Only successful inventory snapshots enter this
/// state machine; volume/usage publications never constitute topology changes.
@MainActor
final class AudioPriorityCoordinator {
    private let respectsExternalDefaultChanges: Bool
    private var configuration = AudioPriorityConfiguration()
    private var connected: Set<String>?
    private var previousDefault: AudioDeviceID?
    private var needsEvaluation = false
    private var manualOverride = false
    private var request: AudioPriorityRequest?
    private var targetID: AudioDeviceID?
    private var targetUID: String?
    private var writeCompleted = false
    private var failed = false
    private var timeoutTask: Task<Void, Never>?
    var onFailure: ((Bool) -> Void)?
    var select: ((AudioDeviceID, AudioPriorityRequest, @escaping AudioPriorityCompletion) -> Void)?

    init(respectsExternalDefaultChanges: Bool = true) {
        self.respectsExternalDefaultChanges = respectsExternalDefaultChanges
    }

    deinit {
        request?.cancel()
        timeoutTask?.cancel()
    }

    func configure(_ next: AudioPriorityConfiguration) {
        guard next != configuration else { return }
        cancelRequest()
        configuration = next
        manualOverride = false
        needsEvaluation = next.enabled
        if !next.enabled { connected = nil; previousDefault = nil }
        setFailed(false)
    }

    func manuallySelected() {
        cancelRequest()
        manualOverride = true
        needsEvaluation = false
        previousDefault = nil
        setFailed(false)
    }

    func receive(devices: [AudioPriorityDevice], currentID: AudioDeviceID?) {
        guard configuration.enabled else { return }
        let identities = Set(devices.compactMap { device -> String? in
            guard let uid = device.uid, !uid.isEmpty else { return nil }
            return uid
        })
        let topologyChanged = connected != nil && connected != identities
        if topologyChanged {
            cancelRequest()
            manualOverride = false
            needsEvaluation = true
            setFailed(false)
        }
        connected = identities

        if let request {
            if respectsExternalDefaultChanges,
               let previousDefault, let currentID, currentID != previousDefault, currentID != targetID {
                manuallySelected()
                self.previousDefault = currentID
                return
            }
            if currentID == targetID,
               devices.contains(where: { $0.id == currentID && $0.uid == targetUID }) {
                cancelRequest()
                setFailed(false)
            } else if writeCompleted {
                request.cancel()
                cancelRequest()
                setFailed(true)
            }
            previousDefault = currentID
            return
        }
        if !topologyChanged, !needsEvaluation, previousDefault != currentID {
            if respectsExternalDefaultChanges, previousDefault != nil, currentID != nil {
                manualOverride = true
            } else if !respectsExternalDefaultChanges, !manualOverride, !failed {
                // HAL does not identify the writer. Input priority therefore
                // yields only to an explicit action in Status Trio, including
                // when macOS takes the route after the inventory notification.
                needsEvaluation = true
            }
        }
        previousDefault = currentID
        guard needsEvaluation, !manualOverride else { return }
        needsEvaluation = false
        guard let target = AudioPrioritySelector.target(devices: devices, configuration: configuration),
              target.id != currentID else { return }
        let request = AudioPriorityRequest(expectedUID: target.uid)
        self.request = request
        targetID = target.id
        targetUID = target.uid
        writeCompleted = false
        timeoutTask = Task { [weak self, weak request] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, let request, self.request === request, request.isValid else { return }
            self.cancelRequest()
            self.setFailed(true)
        }
        guard let select else {
            cancelRequest()
            setFailed(true)
            return
        }
        select(target.id, request) { [weak self, weak request] success in
            guard let self, let request, self.request === request, request.isValid else { return }
            if success { self.writeCompleted = true }
            else { self.cancelRequest(); self.setFailed(true) }
        }
    }

    func inventoryFailed() {
        guard configuration.enabled else { return }
        cancelRequest()
        setFailed(true)
    }

    func stop() {
        cancelRequest()
        configuration.enabled = false
        connected = nil
        previousDefault = nil
        needsEvaluation = false
    }

    private func cancelRequest() {
        timeoutTask?.cancel()
        timeoutTask = nil
        request?.cancel()
        request = nil
        targetID = nil
        targetUID = nil
        writeCompleted = false
    }

    private func setFailed(_ value: Bool) {
        guard failed != value else { return }
        failed = value
        onFailure?(value)
    }
}
