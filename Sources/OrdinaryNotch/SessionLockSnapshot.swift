import AppKit
struct SessionLockSnapshot {
    var locked: Bool
    var currentConsoleUser: Bool
    static func read() -> Self {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return Self(locked: false, currentConsoleUser: false)
        }
        return Self(locked: session["CGSSessionScreenIsLocked"] as? Bool == true,
                    currentConsoleUser: (session[kCGSessionOnConsoleKey as String] as? Bool == true) &&
                    (session[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value == getuid())
    }
}

