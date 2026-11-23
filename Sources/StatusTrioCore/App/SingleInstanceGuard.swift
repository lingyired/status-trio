import Darwin
import Foundation

final class SingleInstanceGuard {
    /// Why an attempt to become the sole running instance did not win the lock.
    ///
    /// The two cases are deliberately separate: "another copy is already
    /// running" is normal and expected, while an unusable lock is a real
    /// failure that must stay diagnosable instead of looking like a second
    /// instance. Both still stop this process from running twice.
    enum Rejection: Error, Equatable, Sendable {
        /// Another process - or another guard in this process - holds the lock.
        case alreadyRunning
        /// The lock file could not be created, opened, or locked for a reason
        /// that is not "someone else owns it".
        case lockUnavailable(reason: String)
    }

    /// The outcome of one acquisition attempt.
    enum Acquisition {
        case acquired(SingleInstanceGuard)
        case rejected(Rejection)

        /// The guard, when this attempt won the lock.
        var instance: SingleInstanceGuard? {
            guard case .acquired(let instance) = self else { return nil }
            return instance
        }

        /// The reason this attempt lost, when it did.
        var rejection: Rejection? {
            guard case .rejected(let rejection) = self else { return nil }
            return rejection
        }
    }

    static var defaultLockPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StatusTrio", isDirectory: true)
            .appendingPathComponent(lockFileName(for: Bundle.main.bundleIdentifier))
            .path
    }

    static func lockFileName(for bundleIdentifier: String?) -> String {
        let fallbackIdentifier = "com.lingsmbp.StatusTrio"
        let identifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIdentifier = identifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? fallbackIdentifier
        let sanitizedIdentifier = resolvedIdentifier.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
                ? character
                : "_"
        }
        return "\(String(sanitizedIdentifier)).lock"
    }

    private let descriptor: Int32

    /// Takes the single-instance lock, reporting *why* it was refused instead
    /// of collapsing every failure into `nil`.
    static func acquire(lockPath: String = defaultLockPath) -> Acquisition {
        switch openLockDescriptor(lockPath: lockPath) {
        case .success(let descriptor):
            return .acquired(SingleInstanceGuard(descriptor: descriptor))
        case .failure(let rejection):
            return .rejected(rejection)
        }
    }

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    // MARK: - Lock plumbing

    private static func openLockDescriptor(lockPath: String) -> Result<Int32, Rejection> {
        let lockURL = URL(fileURLWithPath: lockPath)
        let directoryURL = lockURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(.lockUnavailable(
                reason: "cannot create \(directoryURL.path): \(error.localizedDescription)"
            ))
        }

        let descriptor = lockPath.withCString { path in
            open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            // Capture errno before any other call can overwrite it.
            let failure = errno
            return .failure(.lockUnavailable(
                reason: "open(\(lockPath)) failed: \(description(ofErrno: failure))"
            ))
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            // Capture errno before `close` can overwrite it.
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK || failure == EAGAIN {
                return .failure(.alreadyRunning)
            }
            return .failure(.lockUnavailable(
                reason: "flock(\(lockPath)) failed: \(description(ofErrno: failure))"
            ))
        }

        return .success(descriptor)
    }

    private static func description(ofErrno failure: Int32) -> String {
        guard let message = strerror(failure) else { return "errno \(failure)" }
        return "\(String(cString: message)) (errno \(failure))"
    }
}
