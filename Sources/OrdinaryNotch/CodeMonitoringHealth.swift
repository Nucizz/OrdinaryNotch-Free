import Foundation

/// Missing optional profiles are normal; unreadable profiles must not look like idle agents.
struct CodeMonitoringHealth {
    var available = true
    mutating func contents(of directory: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: .skipsHiddenFiles)
        } catch {
            record(error)
            return []
        }
    }
    mutating func dataIfPresent(at file: URL) -> Data? {
        do { return try Data(contentsOf: file) }
        catch { record(error); return nil }
    }
    private mutating func record(_ error: Error) {
        let error = error as NSError
        if error.domain != NSCocoaErrorDomain || ![NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            available = false
        }
    }
}
