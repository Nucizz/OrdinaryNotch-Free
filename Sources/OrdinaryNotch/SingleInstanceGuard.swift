import Darwin
import Foundation

final class SingleInstanceGuard {
    private let lockURL: URL
    private var descriptor: Int32 = -1

    init(lockURL: URL) {
        self.lockURL = lockURL
    }

    convenience init(bundleIdentifier: String) {
        let filename = "\(bundleIdentifier).instance.lock"
        self.init(lockURL: FileManager.default.temporaryDirectory.appendingPathComponent(filename))
    }

    var isAcquired: Bool { descriptor >= 0 }

    func acquire() -> Bool {
        if isAcquired { return true }

        let flags = O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC
        let fileDescriptor = Darwin.open(lockURL.path, flags, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else { return false }

        descriptor = fileDescriptor
        return true
    }

    func release() {
        guard isAcquired else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
